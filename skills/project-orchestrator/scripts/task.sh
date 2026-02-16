#!/usr/bin/env bash
# task.sh — CRUD operations for project tasks
# Usage: task.sh <action> <project-id> [args...]
#   add <project> <title> [prompt] [priority]  — Add a new task
#   list <project> [status-filter]             — List tasks (optional: pending|running|done|failed)
#   get <project> <task-id>                    — Get task details
#   update <project> <task-id> <key> <value>   — Update a task field
#   delete <project> <task-id>                 — Delete a task
#   next <project>                             — Get next pending task (by priority)
#   batch-add <project>                        — Add multiple tasks from stdin (JSON array)
#
# All output is JSON.

set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"

action="${1:-}"
project="${2:-}"
shift 2 2>/dev/null || true

json_error() { printf '{"error":"%s"}\n' "$1"; exit 1; }

[ -z "$action" ] && json_error "missing action"
[ -z "$project" ] && [ "$action" != "help" ] && json_error "missing project id"

task_dir="$PROJECTS_DIR/$project/.orchestrator/tasks"
[ -d "$task_dir" ] || [ "$action" = "help" ] || json_error "project '$project' not found"

# Generate next task ID (auto-increment)
next_task_id() {
  local max=0
  for f in "$task_dir"/task-*.json; do
    [ -f "$f" ] || continue
    num=$(basename "$f" .json | sed 's/task-//')
    num=$((10#$num))  # force decimal
    [ "$num" -gt "$max" ] && max=$num
  done
  printf "task-%03d" $((max + 1))
}

case "$action" in
  add)
    title="${1:-}"; prompt="${2:-}"; priority="${3:-5}"
    [ -z "$title" ] && json_error "missing task title"
    [ -z "$prompt" ] && prompt="$title"
    id=$(next_task_id)
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat > "$task_dir/$id.json" <<EOJSON
{
  "id": "$id",
  "title": "$title",
  "prompt": $(printf '%s' "$prompt" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),
  "status": "pending",
  "priority": $priority,
  "dependencies": [],
  "worktree": null,
  "branch": "task/$id",
  "sessionId": null,
  "result": null,
  "startedAt": null,
  "completedAt": null,
  "attempts": 0,
  "maxAttempts": 3
}
EOJSON
    cat "$task_dir/$id.json"
    ;;

  list)
    filter="${1:-}"
    printf '['
    first=true
    for f in "$task_dir"/task-*.json; do
      [ -f "$f" ] || continue
      if [ -n "$filter" ]; then
        grep -q "\"status\": *\"$filter\"" "$f" || continue
      fi
      $first || printf ','
      first=false
      cat "$f"
    done
    printf ']\n'
    ;;

  get)
    tid="${1:-}"
    [ -z "$tid" ] && json_error "missing task id"
    tfile="$task_dir/$tid.json"
    [ -f "$tfile" ] || json_error "task '$tid' not found in project '$project'"
    cat "$tfile"
    ;;

  update)
    tid="${1:-}"; key="${2:-}"; value="${3:-}"
    [ -z "$tid" ] || [ -z "$key" ] && json_error "usage: update <project> <task-id> <key> <value>"
    tfile="$task_dir/$tid.json"
    [ -f "$tfile" ] || json_error "task '$tid' not found"
    tmp=$(mktemp)
    if command -v jq &>/dev/null; then
      jq --arg k "$key" --arg v "$value" '.[$k] = ($v | try tonumber // .)' "$tfile" > "$tmp"
    else
      sed "s/\"$key\": *\"[^\"]*\"/\"$key\": \"$value\"/" "$tfile" > "$tmp"
    fi
    mv "$tmp" "$tfile"
    cat "$tfile"
    ;;

  delete)
    tid="${1:-}"
    [ -z "$tid" ] && json_error "missing task id"
    tfile="$task_dir/$tid.json"
    [ -f "$tfile" ] || json_error "task '$tid' not found"
    rm "$tfile"
    printf '{"deleted":"%s"}\n' "$tid"
    ;;

  next)
    # Find the highest-priority pending task (lowest priority number = highest priority)
    best=""
    best_pri=999999
    for f in "$task_dir"/task-*.json; do
      [ -f "$f" ] || continue
      grep -q '"status": *"pending"' "$f" || continue
      # Check dependencies are all done
      if command -v jq &>/dev/null; then
        deps=$(jq -r '.dependencies[]?' "$f" 2>/dev/null)
        all_done=true
        for dep in $deps; do
          dep_file="$task_dir/$dep.json"
          if [ -f "$dep_file" ] && ! grep -q '"status": *"done"' "$dep_file"; then
            all_done=false
            break
          fi
        done
        $all_done || continue
        pri=$(jq -r '.priority // 5' "$f")
      else
        pri=$(grep -o '"priority": *[0-9]*' "$f" | grep -o '[0-9]*' || echo 5)
      fi
      if [ "$pri" -lt "$best_pri" ]; then
        best_pri=$pri
        best="$f"
      fi
    done
    if [ -z "$best" ]; then
      printf '{"next":null,"message":"no pending tasks"}\n'
    else
      cat "$best"
    fi
    ;;

  batch-add)
    # Read JSON array from stdin: [{"title":"...", "prompt":"...", "priority":N}, ...]
    if ! command -v jq &>/dev/null; then
      json_error "jq is required for batch-add"
    fi
    input=$(cat)
    count=$(echo "$input" | jq 'length')
    printf '['
    first=true
    for i in $(seq 0 $((count - 1))); do
      title=$(echo "$input" | jq -r ".[$i].title")
      prompt=$(echo "$input" | jq -r ".[$i].prompt // .[$i].title")
      priority=$(echo "$input" | jq -r ".[$i].priority // 5")
      deps=$(echo "$input" | jq -c ".[$i].dependencies // []")
      id=$(next_task_id)
      now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      cat > "$task_dir/$id.json" <<EOJSON
{
  "id": "$id",
  "title": $(printf '%s' "$title" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),
  "prompt": $(printf '%s' "$prompt" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),
  "status": "pending",
  "priority": $priority,
  "dependencies": $deps,
  "worktree": null,
  "branch": "task/$id",
  "sessionId": null,
  "result": null,
  "startedAt": null,
  "completedAt": null,
  "attempts": 0,
  "maxAttempts": 3
}
EOJSON
      $first || printf ','
      first=false
      cat "$task_dir/$id.json"
    done
    printf ']\n'
    ;;

  *)
    json_error "unknown action: $action. Use: add|list|get|update|delete|next|batch-add"
    ;;
esac
