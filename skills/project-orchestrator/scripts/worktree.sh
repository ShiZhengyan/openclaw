#!/usr/bin/env bash
# worktree.sh — Git worktree lifecycle management for parallel task execution
# Usage: worktree.sh <action> <project-id> <task-id> [args...]
#   setup <project> <task-id>    — Create a worktree for a task
#   teardown <project> <task-id> — Merge results and remove worktree
#   status <project> <task-id>   — Check worktree status
#   cleanup <project>            — Remove all orphaned worktrees for a project
#   list <project>               — List all active worktrees for a project
#
# Worktrees are created at /tmp/worktrees/<project>/<task-id>
# Each task gets its own branch: task/<task-id>

set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"
WORKTREE_BASE="/tmp/worktrees"

action="${1:-}"
project="${2:-}"
task_id="${3:-}"
shift 3 2>/dev/null || true

json_error() { printf '{"error":"%s"}\n' "$1"; exit 1; }

[ -z "$action" ] && json_error "missing action"
[ -z "$project" ] && json_error "missing project id"

project_dir="$PROJECTS_DIR/$project"
[ -d "$project_dir/.git" ] || json_error "project '$project' is not a git repo"

wt_base="$WORKTREE_BASE/$project"

case "$action" in
  setup)
    [ -z "$task_id" ] && json_error "missing task id"
    wt_path="$wt_base/$task_id"
    branch="task/$task_id"

    # Check if worktree already exists
    if [ -d "$wt_path" ]; then
      printf '{"worktree":"%s","branch":"%s","status":"exists"}\n' "$wt_path" "$branch"
      exit 0
    fi

    mkdir -p "$wt_base"

    # Determine base branch (main or master)
    base_branch=$(git -C "$project_dir" symbolic-ref --short HEAD 2>/dev/null || echo "main")

    # Create worktree with a new branch
    if git -C "$project_dir" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      # Branch already exists — reuse it
      git -C "$project_dir" worktree add "$wt_path" "$branch" --quiet 2>/dev/null
    else
      git -C "$project_dir" worktree add -b "$branch" "$wt_path" "$base_branch" --quiet
    fi

    # Copy .orchestrator context files into the worktree (read-only reference)
    if [ -f "$project_dir/.orchestrator/PROGRESS.md" ]; then
      cp "$project_dir/.orchestrator/PROGRESS.md" "$wt_path/PROGRESS.md" 2>/dev/null || true
    fi
    if [ -f "$project_dir/.orchestrator/AGENTS.md" ]; then
      cp "$project_dir/.orchestrator/AGENTS.md" "$wt_path/AGENTS.md" 2>/dev/null || true
    fi

    printf '{"worktree":"%s","branch":"%s","baseBranch":"%s","status":"created"}\n' \
      "$wt_path" "$branch" "$base_branch"
    ;;

  teardown)
    [ -z "$task_id" ] && json_error "missing task id"
    wt_path="$wt_base/$task_id"
    branch="task/$task_id"

    [ -d "$wt_path" ] || json_error "worktree not found at $wt_path"

    # Check if there are uncommitted changes
    has_changes="false"
    if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
      has_changes="true"
      # Auto-commit any remaining changes
      git -C "$wt_path" add -A
      git -C "$wt_path" commit -m "task($task_id): auto-commit remaining changes" --quiet 2>/dev/null || true
    fi

    # Count commits ahead of base
    base_branch=$(git -C "$project_dir" symbolic-ref --short HEAD 2>/dev/null || echo "main")
    commits_ahead=$(git -C "$wt_path" rev-list --count "$base_branch..$branch" 2>/dev/null || echo "0")

    # Try to merge back into main
    merge_status="skipped"
    merge_error=""
    if [ "$commits_ahead" -gt 0 ]; then
      if git -C "$project_dir" merge "$branch" --no-edit --quiet 2>/dev/null; then
        merge_status="merged"
      else
        # Abort the failed merge
        git -C "$project_dir" merge --abort 2>/dev/null || true
        merge_status="conflict"
        merge_error="merge conflict — manual resolution needed"
      fi
    fi

    # Remove worktree
    git -C "$project_dir" worktree remove --force "$wt_path" 2>/dev/null || rm -rf "$wt_path"

    # Optionally delete the branch if merged
    if [ "$merge_status" = "merged" ]; then
      git -C "$project_dir" branch -d "$branch" --quiet 2>/dev/null || \
        git -C "$project_dir" update-ref -d "refs/heads/$branch" 2>/dev/null || true
    fi

    printf '{"worktree":"%s","branch":"%s","mergeStatus":"%s","commitsAhead":%s,"hadUncommitted":%s' \
      "$wt_path" "$branch" "$merge_status" "$commits_ahead" "$has_changes"
    [ -n "$merge_error" ] && printf ',"mergeError":"%s"' "$merge_error"
    printf '}\n'
    ;;

  status)
    [ -z "$task_id" ] && json_error "missing task id"
    wt_path="$wt_base/$task_id"
    branch="task/$task_id"

    if [ ! -d "$wt_path" ]; then
      printf '{"worktree":"%s","exists":false}\n' "$wt_path"
      exit 0
    fi

    base_branch=$(git -C "$project_dir" symbolic-ref --short HEAD 2>/dev/null || echo "main")
    commits_ahead=$(git -C "$wt_path" rev-list --count "$base_branch..$branch" 2>/dev/null || echo "0")
    has_changes="false"
    [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ] && has_changes="true"
    last_commit=$(git -C "$wt_path" log -1 --format='%s' 2>/dev/null || echo "")

    printf '{"worktree":"%s","branch":"%s","exists":true,"commitsAhead":%s,"hasUncommitted":%s,"lastCommit":"%s"}\n' \
      "$wt_path" "$branch" "$commits_ahead" "$has_changes" "$last_commit"
    ;;

  cleanup)
    # Remove all worktrees that no longer have a running task
    removed=0
    if [ -d "$wt_base" ]; then
      for wt in "$wt_base"/*/; do
        [ -d "$wt" ] || continue
        tid=$(basename "$wt")
        tfile="$project_dir/.orchestrator/tasks/$tid.json"
        # Remove if task doesn't exist or is done/failed/cancelled
        should_remove=false
        if [ ! -f "$tfile" ]; then
          should_remove=true
        elif grep -qE '"status": *"(done|failed|cancelled)"' "$tfile" 2>/dev/null; then
          should_remove=true
        fi
        if $should_remove; then
          git -C "$project_dir" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
          removed=$((removed + 1))
        fi
      done
    fi
    printf '{"project":"%s","removedWorktrees":%d}\n' "$project" "$removed"
    ;;

  list)
    printf '['
    first=true
    if [ -d "$wt_base" ]; then
      for wt in "$wt_base"/*/; do
        [ -d "$wt" ] || continue
        tid=$(basename "$wt")
        branch="task/$tid"
        $first || printf ','
        first=false
        printf '{"taskId":"%s","worktree":"%s","branch":"%s"}' "$tid" "$wt" "$branch"
      done
    fi
    printf ']\n'
    ;;

  *)
    json_error "unknown action: $action. Use: setup|teardown|status|cleanup|list"
    ;;
esac
