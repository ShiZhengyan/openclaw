#!/usr/bin/env bash
# report.sh — Generate a completion report for a finished task
# Usage: report.sh <project-id> <task-id>
#
# Gathers: task metadata, git log, files changed, log tail, worktree status.
# Saves report to .orchestrator/logs/<task-id>.report.md
# Outputs the report content (for the agent to forward to the user).

set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"

project="${1:-}"
task_id="${2:-}"

json_error() { printf '{"error":"%s"}\n' "$1"; exit 1; }

[ -z "$project" ] && json_error "missing project id"
[ -z "$task_id" ] && json_error "missing task id"

project_dir="$PROJECTS_DIR/$project"
task_file="$project_dir/.orchestrator/tasks/$task_id.json"
log_file="$project_dir/.orchestrator/logs/$task_id.log"
report_file="$project_dir/.orchestrator/logs/$task_id.report.md"

[ -f "$task_file" ] || json_error "task '$task_id' not found"

# Read task metadata
if command -v jq &>/dev/null; then
  title=$(jq -r '.title' "$task_file")
  status=$(jq -r '.status' "$task_file")
  prompt=$(jq -r '.prompt' "$task_file")
  started=$(jq -r '.startedAt // "N/A"' "$task_file")
  completed=$(jq -r '.completedAt // "N/A"' "$task_file")
  attempt=$(jq -r '.attempts // 1' "$task_file")
  result=$(jq -r '.result // ""' "$task_file")
  wt=$(jq -r '.worktree // ""' "$task_file")
  branch=$(jq -r '.branch // ""' "$task_file")
else
  title=$(grep -o '"title": *"[^"]*"' "$task_file" | sed 's/"title": *"//;s/"$//')
  status=$(grep -o '"status": *"[^"]*"' "$task_file" | sed 's/"status": *"//;s/"$//')
  prompt=""
  started="N/A"
  completed="N/A"
  attempt=1
  result=""
  wt=""
  branch=""
fi

# Calculate duration
duration="N/A"
if [ "$started" != "N/A" ] && [ "$completed" != "N/A" ]; then
  if command -v python3 &>/dev/null; then
    duration=$(python3 -c "
from datetime import datetime
try:
    s = datetime.fromisoformat('$started'.replace('Z','+00:00'))
    e = datetime.fromisoformat('$completed'.replace('Z','+00:00'))
    d = e - s
    mins = int(d.total_seconds() // 60)
    secs = int(d.total_seconds() % 60)
    print(f'{mins}m {secs}s')
except: print('N/A')
" 2>/dev/null || echo "N/A")
  fi
fi

# Get git info from the task branch
commits_log=""
files_changed=""
total_additions=0
total_deletions=0
commit_count=0

base_branch=$(git -C "$project_dir" symbolic-ref --short HEAD 2>/dev/null || echo "main")

# Try worktree first, then main repo
git_dir="$project_dir"
if [ -n "$wt" ] && [ -d "$wt" ]; then
  git_dir="$wt"
fi

if [ -n "$branch" ]; then
  # Check if branch exists in repo
  if git -C "$project_dir" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    commit_count=$(git -C "$project_dir" rev-list --count "$base_branch..$branch" 2>/dev/null || echo "0")
    commits_log=$(git -C "$project_dir" --no-pager log "$base_branch..$branch" --format="- %s (%ar)" 2>/dev/null || echo "")
    files_changed=$(git -C "$project_dir" --no-pager diff --stat "$base_branch..$branch" 2>/dev/null || echo "")
  else
    # Branch already merged — find commits by task prefix in message
    commits_log=$(git -C "$project_dir" --no-pager log --all --grep="task($task_id)" --format="- %s (%ar)" 2>/dev/null || echo "")
    commit_count=$(echo "$commits_log" | grep -c "^-" 2>/dev/null || echo "0")
    # Get combined diff stat from the task commits
    if [ "$commit_count" -gt 0 ]; then
      first_sha=$(git -C "$project_dir" --no-pager log --all --grep="task($task_id)" --format="%H" --reverse 2>/dev/null | head -1)
      last_sha=$(git -C "$project_dir" --no-pager log --all --grep="task($task_id)" --format="%H" 2>/dev/null | head -1)
      if [ -n "$first_sha" ] && [ -n "$last_sha" ]; then
        files_changed=$(git -C "$project_dir" --no-pager diff --stat "${first_sha}^..${last_sha}" 2>/dev/null || echo "")
      fi
    fi
  fi
fi

# Get log tail
log_tail=""
log_total=0
if [ -f "$log_file" ]; then
  log_total=$(wc -l < "$log_file" | tr -d ' ')
  log_tail=$(tail -30 "$log_file" 2>/dev/null || echo "")
fi

# Status emoji
case "$status" in
  done) status_emoji="✅" ;;
  failed) status_emoji="❌" ;;
  rate_limited) status_emoji="⏸️" ;;
  running) status_emoji="🔄" ;;
  *) status_emoji="⏳" ;;
esac

# Build the report
cat > "$report_file" << EOMD
# Task Report: $task_id

## $status_emoji $title

| Field | Value |
|-------|-------|
| **Status** | $status |
| **Attempt** | $attempt |
| **Started** | $started |
| **Completed** | $completed |
| **Duration** | $duration |
| **Branch** | \`$branch\` |
| **Commits** | $commit_count |

## Task Description

$prompt

## Result Summary

${result:-_No result summary recorded._}

## Commits

${commits_log:-_No commits found._}

## Files Changed

\`\`\`
${files_changed:-No file diff available (branch may have been merged/deleted).}
\`\`\`

## Worker Log (last 30 lines)

\`\`\`
${log_tail:-No log file found.}
\`\`\`

---
_Report generated at $(date -u +"%Y-%m-%dT%H:%M:%SZ")_
EOMD

# Output the report
cat "$report_file"
