#!/usr/bin/env bash
# monitor.sh — Worker monitoring and completion handler
# Usage: monitor.sh <action> <project-id> [args...]
#   check <project>               — Check all running tasks, detect completions
#   complete <project> <task-id> <exit-code> [summary]  — Mark task as done/failed
#   log <project> <task-id>       — Get last N lines of task log
#   running <project>             — List currently running tasks
#
# Output: JSON for agent consumption.

set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

action="${1:-}"
project="${2:-}"
shift 2 2>/dev/null || true

json_error() { printf '{"error":"%s"}\n' "$1"; exit 1; }

[ -z "$action" ] && json_error "missing action"
[ -z "$project" ] && json_error "missing project id"

project_dir="$PROJECTS_DIR/$project"
task_dir="$project_dir/.orchestrator/tasks"
log_dir="$project_dir/.orchestrator/logs"

[ -d "$project_dir/.orchestrator" ] || json_error "project '$project' not found"

case "$action" in
  check)
    # Scan all running tasks and report their status
    printf '{"running":['
    first=true
    for f in "$task_dir"/task-*.json; do
      [ -f "$f" ] || continue
      grep -q '"status": *"running"' "$f" || continue
      tid=$(basename "$f" .json)

      if command -v jq &>/dev/null; then
        title=$(jq -r '.title' "$f")
        wt=$(jq -r '.worktree // ""' "$f")
        started=$(jq -r '.startedAt // ""' "$f")
        attempt=$(jq -r '.attempts // 1' "$f")
      else
        title=$(grep -o '"title": *"[^"]*"' "$f" | sed 's/"title": *"//;s/"$//')
        wt=$(grep -o '"worktree": *"[^"]*"' "$f" | sed 's/"worktree": *"//;s/"$//')
        started=""
        attempt=1
      fi

      # Check worktree status
      wt_exists="false"
      commits=0
      last_commit=""
      if [ -d "$wt" ]; then
        wt_exists="true"
        branch="task/$tid"
        base=$(git -C "$project_dir" symbolic-ref --short HEAD 2>/dev/null || echo "main")
        commits=$(git -C "$wt" rev-list --count "$base..$branch" 2>/dev/null || echo "0")
        last_commit=$(git -C "$wt" log -1 --format='%s (%ar)' 2>/dev/null || echo "")
      fi

      # Check log file size
      log_file="$log_dir/$tid.log"
      log_lines=0
      log_tail=""
      if [ -f "$log_file" ]; then
        log_lines=$(wc -l < "$log_file" | tr -d ' ')
        log_tail=$(tail -3 "$log_file" | tr '"' "'")
      fi

      $first || printf ','
      first=false
      printf '{"taskId":"%s","title":"%s","worktree":"%s","worktreeExists":%s,"commits":%s,"lastCommit":"%s","logLines":%s,"logTail":"%s","attempt":%s,"startedAt":"%s"}' \
        "$tid" "$title" "$wt" "$wt_exists" "$commits" "$last_commit" "$log_lines" "$log_tail" "$attempt" "$started"
    done
    printf ']}\n'
    ;;

  complete)
    tid="${1:-}"; exit_code="${2:-0}"; summary="${3:-}"; failure_type="${4:-}"
    [ -z "$tid" ] && json_error "missing task id"
    tfile="$task_dir/$tid.json"
    [ -f "$tfile" ] || json_error "task '$tid' not found"

    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ "$exit_code" = "0" ]; then
      new_status="done"
    else
      new_status="failed"
    fi

    # Check if this is a rate-limit failure — mark as "rate_limited" for smart retry
    if [ "$failure_type" = "rate_limit" ] || echo "$summary" | grep -qi "rate.limit\|429\|too many requests\|throttl"; then
      new_status="rate_limited"
    fi

    if command -v jq &>/dev/null; then
      jq --arg s "$new_status" --arg t "$now" --arg r "$summary" \
        '.status = $s | .completedAt = $t | .result = $r' \
        "$tfile" > "$tfile.tmp" && mv "$tfile.tmp" "$tfile"
    else
      sed -i.bak \
        -e "s/\"status\": *\"running\"/\"status\": \"$new_status\"/" \
        -e "s/\"completedAt\": *null/\"completedAt\": \"$now\"/" \
        "$tfile"
      rm -f "$tfile.bak"
    fi

    # If done, try to teardown worktree and merge
    merge_result=""
    if [ "$new_status" = "done" ]; then
      merge_result=$("$SCRIPT_DIR/worktree.sh" teardown "$project" "$tid" 2>&1 || echo '{"mergeStatus":"error"}')
    fi

    # Append to PROGRESS.md if there's a summary
    if [ -n "$summary" ] && [ "$new_status" = "done" ]; then
      printf '\n### %s: %s\n%s\n' "$tid" "$(date -u +%Y-%m-%d)" "$summary" >> "$project_dir/.orchestrator/PROGRESS.md"
    fi

    printf '{"taskId":"%s","status":"%s","completedAt":"%s","mergeResult":%s}\n' \
      "$tid" "$new_status" "$now" "${merge_result:-\"skipped\"}"
    ;;

  log)
    tid="${1:-}"; lines="${2:-50}"
    [ -z "$tid" ] && json_error "missing task id"
    log_file="$log_dir/$tid.log"
    if [ -f "$log_file" ]; then
      total=$(wc -l < "$log_file" | tr -d ' ')
      content=$(tail -n "$lines" "$log_file")
      printf '{"taskId":"%s","totalLines":%d,"showing":%d,"content":%s}\n' \
        "$tid" "$total" "$lines" "$(printf '%s' "$content" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')"
    else
      printf '{"taskId":"%s","totalLines":0,"content":""}\n' "$tid"
    fi
    ;;

  running)
    printf '['
    first=true
    for f in "$task_dir"/task-*.json; do
      [ -f "$f" ] || continue
      grep -qE '"status": *"(running|rate_limited)"' "$f" || continue
      $first || printf ','
      first=false
      cat "$f"
    done
    printf ']\n'
    ;;

  retry)
    # Reset a failed/rate_limited task to pending for re-dispatch (fresh start)
    tid="${1:-}"
    [ -z "$tid" ] && json_error "missing task id"
    tfile="$task_dir/$tid.json"
    [ -f "$tfile" ] || json_error "task '$tid' not found"
    if command -v jq &>/dev/null; then
      jq '.status = "pending" | .completedAt = null | .result = null | .sessionId = null | .copilotSessionId = null' \
        "$tfile" > "$tfile.tmp" && mv "$tfile.tmp" "$tfile"
    else
      sed -i.bak 's/"status": *"[^"]*"/"status": "pending"/' "$tfile"
      rm -f "$tfile.bak"
    fi
    # Clean up worktree if it exists
    wt=$(grep -o '"worktree": *"[^"]*"' "$tfile" | sed 's/"worktree": *"//;s/"$//')
    [ -n "$wt" ] && [ -d "$wt" ] && "$SCRIPT_DIR/worktree.sh" teardown "$project" "$tid" >/dev/null 2>&1 || true
    printf '{"taskId":"%s","status":"pending","action":"retry"}\n' "$tid"
    ;;

  resume)
    # Resume a rate-limited/failed task using copilot --continue in the same worktree
    tid="${1:-}"
    [ -z "$tid" ] && json_error "missing task id"
    tfile="$task_dir/$tid.json"
    [ -f "$tfile" ] || json_error "task '$tid' not found"

    if command -v jq &>/dev/null; then
      wt=$(jq -r '.worktree // ""' "$tfile")
      csid=$(jq -r '.copilotSessionId // ""' "$tfile")
    else
      wt=$(grep -o '"worktree": *"[^"]*"' "$tfile" | sed 's/"worktree": *"//;s/"$//')
      csid=""
    fi

    [ -z "$wt" ] || [ ! -d "$wt" ] && json_error "worktree not found — use retry instead of resume"

    # Mark as running again
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if command -v jq &>/dev/null; then
      jq --arg t "$now" '.status = "running" | .startedAt = $t | .completedAt = null' \
        "$tfile" > "$tfile.tmp" && mv "$tfile.tmp" "$tfile"
    fi

    # Return the resume command for the agent to execute
    if [ -n "$csid" ]; then
      printf '{"taskId":"%s","action":"resume","worktree":"%s","resumeCmd":"copilot --resume %s --allow-all"}\n' \
        "$tid" "$wt" "$csid"
    else
      printf '{"taskId":"%s","action":"resume","worktree":"%s","resumeCmd":"copilot --continue --allow-all"}\n' \
        "$tid" "$wt"
    fi
    ;;

  *)
    json_error "unknown action: $action. Use: check|complete|log|running"
    ;;
esac
