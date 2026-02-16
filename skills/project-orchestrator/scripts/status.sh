#!/usr/bin/env bash
# status.sh — Project status reporter (WhatsApp-friendly output)
# Usage: status.sh <project-id|all> [format]
#   <project-id>  — Status for a specific project
#   all           — Summary of all projects
#   format: json (default) | text (WhatsApp-friendly)
#
# Output: JSON or formatted text suitable for WhatsApp messages.

set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"

target="${1:-all}"
format="${2:-json}"

json_error() { printf '{"error":"%s"}\n' "$1"; exit 1; }

project_status() {
  local id="$1"
  local pdir="$PROJECTS_DIR/$id"
  local tdir="$pdir/.orchestrator/tasks"
  local pfile="$pdir/.orchestrator/project.json"

  [ -f "$pfile" ] || return

  local total=$(find "$tdir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  local done_c=$(find "$tdir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"done"' {} + 2>/dev/null | wc -l | tr -d ' ')
  local running_c=$(find "$tdir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"running"' {} + 2>/dev/null | wc -l | tr -d ' ')
  local pending_c=$(find "$tdir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"pending"' {} + 2>/dev/null | wc -l | tr -d ' ')
  local failed_c=$(find "$tdir" -maxdepth 1 -name '*.json' -exec grep -l '"status": *"failed"' {} + 2>/dev/null | wc -l | tr -d ' ')

  if [ "$format" = "text" ]; then
    local name="$id"
    command -v jq &>/dev/null && name=$(jq -r '.name // .id' "$pfile")

    echo "📋 *$name* ($id)"
    if [ "$total" -eq 0 ]; then
      echo "  No tasks yet."
    else
      local pct=0
      [ "$total" -gt 0 ] && pct=$((done_c * 100 / total))
      echo "  Progress: $pct% ($done_c/$total)"
      [ "$running_c" -gt 0 ] && echo "  🔄 Running: $running_c"
      [ "$pending_c" -gt 0 ] && echo "  ⏳ Pending: $pending_c"
      [ "$failed_c" -gt 0 ] && echo "  ❌ Failed: $failed_c"
      [ "$done_c" -gt 0 ] && echo "  ✅ Done: $done_c"

      # Show running task details
      if [ "$running_c" -gt 0 ]; then
        echo ""
        echo "  _Running tasks:_"
        for f in "$tdir"/task-*.json; do
          [ -f "$f" ] || continue
          grep -q '"status": *"running"' "$f" || continue
          local tid=$(basename "$f" .json)
          local title=""
          if command -v jq &>/dev/null; then
            title=$(jq -r '.title' "$f")
          else
            title=$(grep -o '"title": *"[^"]*"' "$f" | sed 's/"title": *"//;s/"$//')
          fi
          echo "  • $tid: $title"
        done
      fi

      # Show failed task details
      if [ "$failed_c" -gt 0 ]; then
        echo ""
        echo "  _Failed tasks:_"
        for f in "$tdir"/task-*.json; do
          [ -f "$f" ] || continue
          grep -q '"status": *"failed"' "$f" || continue
          local tid=$(basename "$f" .json)
          local title=""
          if command -v jq &>/dev/null; then
            title=$(jq -r '.title' "$f")
          else
            title=$(grep -o '"title": *"[^"]*"' "$f" | sed 's/"title": *"//;s/"$//')
          fi
          echo "  • $tid: $title"
        done
      fi
    fi
  else
    # JSON output
    if command -v jq &>/dev/null; then
      local name=$(jq -r '.name // .id' "$pfile")
    else
      local name="$id"
    fi
    printf '{"id":"%s","name":"%s","total":%d,"done":%d,"running":%d,"pending":%d,"failed":%d' \
      "$id" "$name" "$total" "$done_c" "$running_c" "$pending_c" "$failed_c"
    if [ "$total" -gt 0 ]; then
      local pct=$((done_c * 100 / total))
      printf ',"progress":%d' "$pct"
    fi
    printf '}'
  fi
}

if [ "$target" = "all" ]; then
  if [ "$format" = "text" ]; then
    echo "🏗️ *Project Overview*"
    echo "━━━━━━━━━━━━━━━"
    found=false
    if [ -d "$PROJECTS_DIR" ]; then
      for pdir in "$PROJECTS_DIR"/*/; do
        [ -f "$pdir.orchestrator/project.json" ] || continue
        found=true
        id=$(basename "$pdir")
        project_status "$id"
        echo ""
      done
    fi
    $found || echo "No projects found."
  else
    printf '['
    first=true
    if [ -d "$PROJECTS_DIR" ]; then
      for pdir in "$PROJECTS_DIR"/*/; do
        [ -f "$pdir.orchestrator/project.json" ] || continue
        $first || printf ','
        first=false
        id=$(basename "$pdir")
        project_status "$id"
      done
    fi
    printf ']\n'
  fi
else
  [ -d "$PROJECTS_DIR/$target/.orchestrator" ] || json_error "project '$target' not found"
  project_status "$target"
  [ "$format" = "json" ] && echo ""
fi
