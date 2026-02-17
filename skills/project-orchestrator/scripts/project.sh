#!/usr/bin/env bash
# project.sh — CRUD operations for orchestrator projects
# Usage: project.sh <action> [args...]
#   create <id> <name> [description]   — Create a new project
#   list                                — List all projects
#   get <id>                            — Get project details
#   delete <id>                         — Delete a project
#   update <id> <key> <value>           — Update a project config field
#
# All output is JSON for reliable parsing by the OpenClaw agent.

set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"

action="${1:-}"
shift || true

json_error() { printf '{"error":"%s"}\n' "$1"; exit 1; }

case "$action" in
  create)
    id="${1:-}"; name="${2:-}"; desc="${3:-}"
    [ -z "$id" ] && json_error "missing project id"
    [ -z "$name" ] && name="$id"
    project_dir="$PROJECTS_DIR/$id"
    [ -d "$project_dir/.orchestrator" ] && json_error "project '$id' already exists"
    mkdir -p "$project_dir/.orchestrator/tasks" "$project_dir/.orchestrator/logs"
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat > "$project_dir/.orchestrator/project.json" <<EOJSON
{
  "id": "$id",
  "name": "$name",
  "description": "$desc",
  "createdAt": "$now",
  "status": "active",
  "config": {
    "maxWorkers": 10,
    "model": "claude-opus-4.6",
    "defaultPermissions": "--allow-all"
  }
}
EOJSON
    # Initialize git repo if not already one
    if [ ! -d "$project_dir/.git" ]; then
      git -C "$project_dir" init -b main --quiet
      echo ".orchestrator/logs/" > "$project_dir/.gitignore"
      git -C "$project_dir" add .gitignore
      git -C "$project_dir" commit -m "init: project $id" --quiet
    fi
    # Create PROGRESS.md template
    cat > "$project_dir/.orchestrator/PROGRESS.md" <<'EOMD'
# Progress & Learnings

## Architecture Decisions

_Accumulated architecture decisions for this project._

## Common Errors & Fixes

_Patterns of errors encountered and how they were resolved._

## Code Patterns

_Recurring code patterns and conventions established._

## Learnings

_General learnings and insights from task execution._
EOMD
    cat "$project_dir/.orchestrator/project.json"
    ;;

  list)
    printf '['
    first=true
    if [ -d "$PROJECTS_DIR" ]; then
      for pdir in "$PROJECTS_DIR"/*/; do
        pfile="$pdir.orchestrator/project.json"
        [ -f "$pfile" ] || continue
        tdir="$pdir.orchestrator/tasks"
        task_count=$(find "$tdir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
        done_count=$(find "$tdir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"done"' {} + 2>/dev/null | wc -l | tr -d ' ')
        running_count=$(find "$tdir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"running"' {} + 2>/dev/null | wc -l | tr -d ' ')
        pending_count=$(find "$tdir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"pending"' {} + 2>/dev/null | wc -l | tr -d ' ')
        failed_count=$(find "$tdir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"failed"' {} + 2>/dev/null | wc -l | tr -d ' ')
        $first || printf ','
        first=false
        # Inline stats into the project JSON
        printf '{"project":%s,"stats":{"total":%d,"done":%d,"running":%d,"pending":%d,"failed":%d}}' \
          "$(cat "$pfile")" "$task_count" "$done_count" "$running_count" "$pending_count" "$failed_count"
      done
    fi
    printf ']\n'
    ;;

  get)
    id="${1:-}"
    [ -z "$id" ] && json_error "missing project id"
    pfile="$PROJECTS_DIR/$id/.orchestrator/project.json"
    [ -f "$pfile" ] || json_error "project '$id' not found"
    task_dir="$PROJECTS_DIR/$id/.orchestrator/tasks"
    task_count=$(find "$task_dir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
    done_count=$(find "$task_dir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"done"' {} + 2>/dev/null | wc -l | tr -d ' ')
    running_count=$(find "$task_dir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"running"' {} + 2>/dev/null | wc -l | tr -d ' ')
    pending_count=$(find "$task_dir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"pending"' {} + 2>/dev/null | wc -l | tr -d ' ')
    failed_count=$(find "$task_dir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"failed"' {} + 2>/dev/null | wc -l | tr -d ' ')
    printf '{"project":%s,"stats":{"total":%d,"done":%d,"running":%d,"pending":%d,"failed":%d}}\n' \
      "$(cat "$pfile")" "$task_count" "$done_count" "$running_count" "$pending_count" "$failed_count"
    ;;

  delete)
    id="${1:-}"
    [ -z "$id" ] && json_error "missing project id"
    project_dir="$PROJECTS_DIR/$id"
    [ -d "$project_dir/.orchestrator" ] || json_error "project '$id' not found"
    # Clean up any worktrees first
    wt_base="/tmp/worktrees/$id"
    if [ -d "$wt_base" ]; then
      for wt in "$wt_base"/*/; do
        [ -d "$wt" ] && git -C "$project_dir" worktree remove --force "$wt" 2>/dev/null || true
      done
      rm -rf "$wt_base"
    fi
    rm -rf "$project_dir"
    printf '{"deleted":"%s"}\n' "$id"
    ;;

  update)
    id="${1:-}"; key="${2:-}"; value="${3:-}"
    [ -z "$id" ] || [ -z "$key" ] && json_error "usage: update <id> <key> <value>"
    pfile="$PROJECTS_DIR/$id/.orchestrator/project.json"
    [ -f "$pfile" ] || json_error "project '$id' not found"
    # Update config.<key> using a portable approach
    tmp=$(mktemp)
    if command -v jq &>/dev/null; then
      jq --arg k "$key" --arg v "$value" '.config[$k] = ($v | try tonumber // .)' "$pfile" > "$tmp"
    else
      # Fallback: simple sed for known keys
      sed "s/\"$key\": *\"[^\"]*\"/\"$key\": \"$value\"/" "$pfile" > "$tmp"
      sed "s/\"$key\": *[0-9]*/\"$key\": $value/" "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
    fi
    mv "$tmp" "$pfile"
    cat "$pfile"
    ;;

  *)
    json_error "unknown action: $action. Use: create|list|get|delete|update"
    ;;
esac
