#!/usr/bin/env bash
# Health check for the lab web server.
# Checks disk, memory, the Docker container, and the web page.
# Exit code 0 = healthy, 1 = at least one check failed.
set -uo pipefail

LOG_FILE="/var/log/lab-health.log"
DISK_LIMIT=80        # fail if the root disk is 80% full or more
MEM_MIN_PERCENT=10   # fail if less than 10% of memory is available
CONTAINER="web"
URL="http://localhost/"

failures=0

log()  { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }
pass() { log "PASS  $1"; }
fail() { log "FAIL  $1"; failures=$((failures + 1)); }

log "=== Health check started on $(hostname) ==="

# 1. Disk usage on the root filesystem
disk_used=$(df --output=pcent / | tail -1 | tr -dc '0-9')
if [ "$disk_used" -lt "$DISK_LIMIT" ]; then
  pass "Disk: ${disk_used}% used (limit ${DISK_LIMIT}%)"
else
  fail "Disk: ${disk_used}% used (limit ${DISK_LIMIT}%)"
fi

# 2. Available memory
mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
mem_percent=$(( mem_avail * 100 / mem_total ))
if [ "$mem_percent" -ge "$MEM_MIN_PERCENT" ]; then
  pass "Memory: ${mem_percent}% available (minimum ${MEM_MIN_PERCENT}%)"
else
  fail "Memory: ${mem_percent}% available (minimum ${MEM_MIN_PERCENT}%)"
fi

# 3. Docker container is running and its healthcheck says healthy
if ! command -v docker >/dev/null 2>&1; then
  fail "Docker is not installed"
else
  state=$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$CONTAINER" 2>/dev/null)
  if [ "$state" = "running healthy" ]; then
    pass "Container '$CONTAINER': running and healthy"
  else
    fail "Container '$CONTAINER': ${state:-not found}"
  fi
fi

# 4. The web page answers with HTTP 200
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL")
if [ "$code" = "200" ]; then
  pass "Web page: HTTP $code"
else
  fail "Web page: HTTP $code (expected 200)"
fi

if [ "$failures" -eq 0 ]; then
  log "RESULT: healthy"
  exit 0
else
  log "RESULT: $failures check(s) failed"
  exit 1
fi