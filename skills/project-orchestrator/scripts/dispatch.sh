#!/usr/bin/env bash
# dispatch.sh — Ralph Loop dispatch engine
# Reads pending tasks for a project and spawns Copilot CLI workers in parallel.
#
# Usage: dispatch.sh <project-id> [max-workers]
#   Dispatches up to max-workers pending tasks (default: from project config or 10).
#   Each task gets its own git worktree and Copilot CLI instance.
#
# Output: JSON array of dispatched tasks with session info.
# Designed to be called by the OpenClaw agent via bash-tools.

set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

project="${1:-}"
max_override="${2:-}"

[ -z "$project" ] && { printf '{"error":"missing project id"}\n'; exit 1; }

project_dir="$PROJECTS_DIR/$project"
[ -d "$project_dir/.orchestrator" ] || { printf '{"error":"project not found"}\n'; exit 1; }

# Read max workers from config or override
if [ -n "$max_override" ]; then
  max_workers="$max_override"
elif command -v jq &>/dev/null; then
  max_workers=$(jq -r '.config.maxWorkers // 10' "$project_dir/.orchestrator/project.json")
else
  max_workers=10
fi

# Read model from config
if command -v jq &>/dev/null; then
  model=$(jq -r '.config.model // "claude-sonnet-4"' "$project_dir/.orchestrator/project.json")
  permissions=$(jq -r '.config.defaultPermissions // "--allow-all-tools"' "$project_dir/.orchestrator/project.json")
else
  model="claude-sonnet-4"
  permissions="--allow-all-tools"
fi

# Count currently running tasks
running=0
task_dir="$project_dir/.orchestrator/tasks"
for f in "$task_dir"/task-*.json; do
  [ -f "$f" ] || continue
  grep -q '"status": *"running"' "$f" && running=$((running + 1))
done

available=$((max_workers - running))
[ "$available" -le 0 ] && { printf '{"dispatched":[],"message":"max workers (%d) reached, %d running"}\n' "$max_workers" "$running"; exit 0; }

# Collect pending tasks sorted by priority
pending_tasks=()
while IFS= read -r line; do
  pending_tasks+=("$line")
done < <(
  for f in "$task_dir"/task-*.json; do
    [ -f "$f" ] || continue
    grep -q '"status": *"pending"' "$f" || continue
    # Check dependencies
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
    echo "$pri $f"
  done | sort -n | head -n "$available"
)

# Read PROGRESS.md and AGENTS.md for context injection
progress_context=""
[ -f "$project_dir/.orchestrator/PROGRESS.md" ] && progress_context=$(cat "$project_dir/.orchestrator/PROGRESS.md")
agents_context=""
[ -f "$project_dir/.orchestrator/AGENTS.md" ] && agents_context=$(cat "$project_dir/.orchestrator/AGENTS.md")

dispatched='[]'
count=0

for entry in "${pending_tasks[@]}"; do
  task_file=$(echo "$entry" | cut -d' ' -f2-)
  [ -f "$task_file" ] || continue

  task_id=$(basename "$task_file" .json)

  if command -v jq &>/dev/null; then
    title=$(jq -r '.title' "$task_file")
    prompt=$(jq -r '.prompt' "$task_file")
    attempts=$(jq -r '.attempts // 0' "$task_file")
  else
    title=$(grep -o '"title": *"[^"]*"' "$task_file" | head -1 | sed 's/"title": *"//' | sed 's/"$//')
    prompt=$(grep -o '"prompt": *"[^"]*"' "$task_file" | head -1 | sed 's/"prompt": *"//' | sed 's/"$//')
    attempts=0
  fi

  # Setup worktree
  wt_result=$("$SCRIPT_DIR/worktree.sh" setup "$project" "$task_id" 2>&1)
  wt_path=$(echo "$wt_result" | grep -o '"worktree":"[^"]*"' | head -1 | sed 's/"worktree":"//;s/"$//')

  if [ -z "$wt_path" ]; then
    echo "Warning: failed to create worktree for $task_id" >&2
    continue
  fi

  # Build the full prompt with context
  full_prompt="You are working on project '$project', task '$task_id': $title

## Task
$prompt

## Project Context
$([ -n "$agents_context" ] && echo "$agents_context" || echo "No AGENTS.md yet.")

## Previous Learnings
$([ -n "$progress_context" ] && echo "$progress_context" || echo "No learnings yet.")

## Rules
- Work ONLY in the current directory (worktree).
- Commit your changes with descriptive messages prefixed with 'task($task_id): '.
- If you encounter errors, fix them. If stuck after 3 attempts, commit what you have and exit.
- When completely finished, run: openclaw system event --text \"Done: $task_id - $title\" --mode now"

  # Update task status to running
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if command -v jq &>/dev/null; then
    jq --arg s "running" --arg w "$wt_path" --arg t "$now" --argjson a "$((attempts + 1))" \
      '.status = $s | .worktree = $w | .startedAt = $t | .attempts = $a' \
      "$task_file" > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"
  else
    sed -i.bak \
      -e "s/\"status\": *\"pending\"/\"status\": \"running\"/" \
      -e "s|\"worktree\": *null|\"worktree\": \"$wt_path\"|" \
      -e "s/\"startedAt\": *null/\"startedAt\": \"$now\"/" \
      "$task_file"
    rm -f "$task_file.bak"
  fi

  # Save the prompt to a file for copilot to read
  prompt_file="$project_dir/.orchestrator/logs/$task_id.prompt.md"
  echo "$full_prompt" > "$prompt_file"

  # Log file for output
  log_file="$project_dir/.orchestrator/logs/$task_id.log"

  # Output the dispatch command for the OpenClaw agent to execute
  # The agent should run this via bash-tools with background:true and pty:true
  copilot_cmd="copilot -p \"$(echo "$full_prompt" | head -5 | tr '\n' ' ')\" --model $model $permissions"

  count=$((count + 1))
  printf '{"taskId":"%s","title":"%s","worktree":"%s","promptFile":"%s","logFile":"%s","copilotCmd":"%s","attempt":%d}\n' \
    "$task_id" "$title" "$wt_path" "$prompt_file" "$log_file" \
    "copilot -p @$prompt_file --model $model $permissions" \
    "$((attempts + 1))"
done

printf '{"dispatched":%d,"maxWorkers":%d,"running":%d}\n' "$count" "$max_workers" "$((running + count))"
