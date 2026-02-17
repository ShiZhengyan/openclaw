#!/usr/bin/env bash
# dashboard.sh — Terminal dashboard with live refresh
# Usage: dashboard.sh [project] [interval-seconds]
#   No project: show all projects
#   interval: refresh interval in seconds (default: 5)

set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

project="${1:-}"
interval="${2:-5}"

render() {
  clear
  local now
  now=$(date "+%Y-%m-%d %H:%M:%S")

  printf '\033[1;38;5;208m🦞 Project Orchestrator Dashboard\033[0m\n'
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  echo ""

  if [ -n "$project" ]; then
    render_project "$project"
  else
    local found=false
    if [ -d "$PROJECTS_DIR" ]; then
      for pdir in "$PROJECTS_DIR"/*/; do
        [ -f "$pdir.orchestrator/project.json" ] || continue
        found=true
        render_project "$(basename "$pdir")"
        echo ""
      done
    fi
    $found || echo "  No projects found."
  fi

  echo ""
  printf '\033[2mLast updated: %s | Refresh: %ds | Ctrl+C to exit\033[0m\n' "$now" "$interval"
}

render_project() {
  local id="$1"
  local pdir="$PROJECTS_DIR/$id"
  local tdir="$pdir/.orchestrator/tasks"
  local pfile="$pdir/.orchestrator/project.json"

  [ -f "$pfile" ] || return

  local name="$id"
  command -v jq &>/dev/null && name=$(jq -r '.name // .id' "$pfile")

  local total=0 done_c=0 running_c=0 pending_c=0 failed_c=0 ratelimit_c=0
  for f in "$tdir"/task-*.json; do
    [ -f "$f" ] || continue
    total=$((total + 1))
    if grep -q '"status": *"done"' "$f"; then done_c=$((done_c + 1))
    elif grep -q '"status": *"running"' "$f"; then running_c=$((running_c + 1))
    elif grep -q '"status": *"pending"' "$f"; then pending_c=$((pending_c + 1))
    elif grep -q '"status": *"failed"' "$f"; then failed_c=$((failed_c + 1))
    elif grep -q '"status": *"rate_limited"' "$f"; then ratelimit_c=$((ratelimit_c + 1))
    fi
  done

  # Project header
  printf '\033[1m📦 %s\033[0m' "$name"

  # Autopilot status
  if command -v jq &>/dev/null; then
    local ap_enabled=$(jq -r '.autopilot.enabled // false' "$pfile" 2>/dev/null)
    if [ "$ap_enabled" = "true" ]; then
      printf '  \033[32m🤖 Autopilot ON\033[0m'
    fi
  fi
  echo ""

  if [ "$total" -eq 0 ]; then
    echo "  No tasks."
    return
  fi

  # Progress bar
  local pct=$((done_c * 100 / total))
  local bar_width=20
  local filled=$((pct * bar_width / 100))
  local empty=$((bar_width - filled))
  printf '  '
  printf '\033[32m'
  for ((i=0; i<filled; i++)); do printf '█'; done
  printf '\033[0m\033[2m'
  for ((i=0; i<empty; i++)); do printf '░'; done
  printf '\033[0m'
  printf ' %d%%  (%d/%d done' "$pct" "$done_c" "$total"
  [ "$running_c" -gt 0 ] && printf ', %d running' "$running_c"
  [ "$pending_c" -gt 0 ] && printf ', %d pending' "$pending_c"
  [ "$failed_c" -gt 0 ] && printf ', %d failed' "$failed_c"
  [ "$ratelimit_c" -gt 0 ] && printf ', %d rate-limited' "$ratelimit_c"
  printf ')\n'

  # Running workers
  if [ "$running_c" -gt 0 ]; then
    echo ""
    printf '  \033[1m🔧 Active Workers:\033[0m\n'
    printf '  ┌──────────┬────────────────────────────┬─────────┐\n'
    printf '  │ \033[1mTask\033[0m     │ \033[1mTitle\033[0m                      │ \033[1mRuntime\033[0m │\n'
    printf '  ├──────────┼────────────────────────────┼─────────┤\n'
    for f in "$tdir"/task-*.json; do
      [ -f "$f" ] || continue
      grep -q '"status": *"running"' "$f" || continue
      local tid=$(basename "$f" .json)
      local title=""
      local started=""
      if command -v jq &>/dev/null; then
        title=$(jq -r '.title' "$f" | head -c 26)
        started=$(jq -r '.startedAt // ""' "$f")
      else
        title=$(grep -o '"title": *"[^"]*"' "$f" | head -1 | sed 's/"title": *"//;s/"$//' | head -c 26)
      fi
      # Calculate runtime
      local runtime="?"
      if [ -n "$started" ] && [ "$started" != "null" ]; then
        local start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" "+%s" 2>/dev/null || date -d "$started" "+%s" 2>/dev/null || echo "0")
        local now_epoch=$(date "+%s")
        if [ "$start_epoch" -gt 0 ]; then
          local diff=$((now_epoch - start_epoch))
          runtime="$((diff / 60))m $((diff % 60))s"
        fi
      fi
      printf '  │ %-8s │ %-26s │ %7s │\n' "$tid" "$title" "$runtime"
    done
    printf '  └──────────┴────────────────────────────┴─────────┘\n'
  fi

  # Recent completions (last 5)
  local recent_done=0
  for f in "$tdir"/task-*.json; do
    [ -f "$f" ] || continue
    grep -q '"status": *"done"' "$f" && recent_done=$((recent_done + 1))
  done
  if [ "$recent_done" -gt 0 ]; then
    echo ""
    printf '  \033[1m📊 Completed:\033[0m\n'
    for f in $(ls -t "$tdir"/task-*.json 2>/dev/null | head -5); do
      [ -f "$f" ] || continue
      grep -q '"status": *"done"' "$f" || continue
      local tid=$(basename "$f" .json)
      local title=""
      if command -v jq &>/dev/null; then
        title=$(jq -r '.title' "$f" | head -c 40)
      else
        title=$(grep -o '"title": *"[^"]*"' "$f" | head -1 | sed 's/"title": *"//;s/"$//' | head -c 40)
      fi
      printf '  \033[32m✅\033[0m %s: %s\n' "$tid" "$title"
    done
  fi

  # Failed tasks
  if [ "$failed_c" -gt 0 ]; then
    echo ""
    printf '  \033[1m⚠️  Failed:\033[0m\n'
    for f in "$tdir"/task-*.json; do
      [ -f "$f" ] || continue
      grep -q '"status": *"failed"' "$f" || continue
      local tid=$(basename "$f" .json)
      local title=""
      if command -v jq &>/dev/null; then
        title=$(jq -r '.title' "$f" | head -c 40)
      fi
      printf '  \033[31m❌\033[0m %s: %s\n' "$tid" "$title"
    done
  fi
}

# Main loop
trap 'printf "\n\033[0mDashboard stopped.\n"; exit 0' INT
while true; do
  render
  sleep "$interval"
done
