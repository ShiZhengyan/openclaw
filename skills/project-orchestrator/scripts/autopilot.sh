#!/usr/bin/env bash
# autopilot.sh — Cron-based auto-dispatch controller
# Usage: autopilot.sh <action> <project-id> [args...]
#   start <project> [interval-ms]  — Output cron job config for agent to create
#   save <project> <cron-job-id>   — Save cron job ID to project config
#   stop <project>                 — Output cron update config to disable
#   status <project>               — Show autopilot status
#
# The agent uses the cron tool to actually create/update/remove jobs.
# This script just prepares the config and manages the project-level state.

set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"

action="${1:-}"
project="${2:-}"
shift 2 2>/dev/null || true

json_error() { printf '{"error":"%s"}\n' "$1"; exit 1; }

[ -z "$action" ] && json_error "missing action"
[ -z "$project" ] && json_error "missing project id"

project_dir="$PROJECTS_DIR/$project"
pfile="$project_dir/.orchestrator/project.json"
[ -f "$pfile" ] || json_error "project '$project' not found"

case "$action" in
  start)
    interval_ms="${1:-300000}"  # Default 5 minutes

    # Check if autopilot is already active
    if command -v jq &>/dev/null; then
      existing=$(jq -r '.autopilot.cronJobId // ""' "$pfile" 2>/dev/null)
      enabled=$(jq -r '.autopilot.enabled // false' "$pfile" 2>/dev/null)
      if [ -n "$existing" ] && [ "$enabled" = "true" ]; then
        printf '{"status":"already_running","cronJobId":"%s","message":"Autopilot already active. Use stop first."}\n' "$existing"
        exit 0
      fi
    fi

    # Output the cron job config for the agent to create via cron tool
    cat <<EOJSON
{
  "cronConfig": {
    "name": "autopilot-$project",
    "description": "Auto-patrol for project $project — check workers, dispatch tasks, report status",
    "schedule": { "kind": "every", "everyMs": $interval_ms },
    "sessionTarget": "main",
    "wakeMode": "now",
    "payload": {
      "kind": "systemEvent",
      "text": "[AUTOPILOT] patrol $project"
    },
    "enabled": true
  },
  "project": "$project",
  "intervalMs": $interval_ms,
  "message": "Use cron action:add with the cronConfig above to create the autopilot job. Then run: autopilot.sh save $project <cronJobId>"
}
EOJSON
    ;;

  save)
    cron_job_id="${1:-}"
    [ -z "$cron_job_id" ] && json_error "missing cron job id"

    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if command -v jq &>/dev/null; then
      jq --arg id "$cron_job_id" --arg t "$now" \
        '.autopilot = { cronJobId: $id, enabled: true, startedAt: $t }' \
        "$pfile" > "$pfile.tmp" && mv "$pfile.tmp" "$pfile"
    fi

    printf '{"status":"saved","cronJobId":"%s","project":"%s"}\n' "$cron_job_id" "$project"
    ;;

  stop)
    if command -v jq &>/dev/null; then
      cron_job_id=$(jq -r '.autopilot.cronJobId // ""' "$pfile" 2>/dev/null)
    else
      cron_job_id=""
    fi

    [ -z "$cron_job_id" ] && json_error "no autopilot configured for this project"

    # Update project config
    if command -v jq &>/dev/null; then
      jq '.autopilot.enabled = false' "$pfile" > "$pfile.tmp" && mv "$pfile.tmp" "$pfile"
    fi

    printf '{"status":"stopped","cronJobId":"%s","message":"Use cron action:remove jobId:%s to delete the cron job"}\n' \
      "$cron_job_id" "$cron_job_id"
    ;;

  status)
    if command -v jq &>/dev/null; then
      cron_job_id=$(jq -r '.autopilot.cronJobId // ""' "$pfile" 2>/dev/null)
      enabled=$(jq -r '.autopilot.enabled // false' "$pfile" 2>/dev/null)
      started_at=$(jq -r '.autopilot.startedAt // ""' "$pfile" 2>/dev/null)
    else
      cron_job_id=""
      enabled="false"
      started_at=""
    fi

    if [ -z "$cron_job_id" ]; then
      printf '{"project":"%s","autopilot":"not_configured"}\n' "$project"
    else
      printf '{"project":"%s","autopilot":{"cronJobId":"%s","enabled":%s,"startedAt":"%s"}}\n' \
        "$project" "$cron_job_id" "$enabled" "$started_at"
    fi
    ;;

  *)
    json_error "unknown action: $action. Use: start|save|stop|status"
    ;;
esac
