#!/usr/bin/env bash
# dashboard-web.sh — Web dashboard HTTP server for mobile access
# Usage: dashboard-web.sh [--port PORT] [--open]
#   Starts a lightweight HTTP server serving the orchestrator dashboard.
#   Access from phone: http://<your-ip>:PORT
#
# Requires: node (already available in OpenClaw environment)

set -euo pipefail

PORT=8787
OPEN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --open) OPEN=true; shift ;;
    *) PORT="$1"; shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DASHBOARD_DIR="$SCRIPT_DIR/../dashboard"
STATUS_SCRIPT="$SCRIPT_DIR/status.sh"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"

[ -f "$DASHBOARD_DIR/index.html" ] || { echo "Error: dashboard/index.html not found"; exit 1; }
[ -f "$STATUS_SCRIPT" ] || { echo "Error: status.sh not found"; exit 1; }

echo "🦞 Project Orchestrator Web Dashboard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get local IP for phone access
LOCAL_IP=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' || hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

echo "  Local:  http://localhost:$PORT"
echo "  Phone:  http://$LOCAL_IP:$PORT"
echo ""
echo "  Tip: On iPhone, open the URL in Safari, then"
echo "       tap Share → Add to Home Screen for quick access."
echo ""
echo "  Press Ctrl+C to stop."
echo ""

if [ "$OPEN" = "true" ] && command -v open &>/dev/null; then
  open "http://localhost:$PORT" &
fi

# Start Node.js HTTP server
exec node -e "
const http = require('http');
const fs = require('fs');
const { execSync } = require('child_process');
const path = require('path');

const PORT = $PORT;
const DASHBOARD = '$DASHBOARD_DIR/index.html';
const STATUS = '$STATUS_SCRIPT';
const PROJECTS_DIR = '$PROJECTS_DIR';

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  
  // CORS headers for local development
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET');
  
  if (url.pathname === '/api/status') {
    try {
      const data = execSync(STATUS + ' all json', {
        env: { ...process.env, PROJECTS_DIR },
        timeout: 10000
      }).toString();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(data);
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
  } else if (url.pathname.startsWith('/api/status/')) {
    const project = url.pathname.split('/').pop();
    try {
      const data = execSync(STATUS + ' ' + project + ' json', {
        env: { ...process.env, PROJECTS_DIR },
        timeout: 10000
      }).toString();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(data);
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
  } else {
    // Serve dashboard HTML
    try {
      const html = fs.readFileSync(DASHBOARD, 'utf-8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
    } catch (e) {
      res.writeHead(500);
      res.end('Error loading dashboard');
    }
  }
}).listen(PORT, '0.0.0.0', () => {
  console.log('Dashboard server running on port ' + PORT);
});
"
