#!/usr/bin/env bash
# Patch the server's OS packages and log the result.
# It does NOT reboot on its own. It reports whether a reboot is needed,
# so a person can schedule it (change control).
set -uo pipefail

LOG_FILE="/var/log/lab-patch.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root: sudo bash $0"
  exit 1
fi

log "=== Patch run started on $(hostname) ==="

# dnf check-update exit codes: 0 = no updates, 100 = updates available, other = error
updates=$(dnf -q check-update 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  log "No updates available. Nothing to do."
  exit 0
elif [ "$rc" -ne 100 ]; then
  log "ERROR: dnf check-update failed (exit $rc)"
  exit 1
fi

count=$(echo "$updates" | grep -c '[[:alnum:]]')
log "About $count package update(s) available. Installing..."

if dnf -y update >>"$LOG_FILE" 2>&1; then
  log "Updates installed successfully."
else
  log "ERROR: dnf update failed. See $LOG_FILE for details."
  exit 1
fi

# needs-restarting -r exit codes: 0 = no reboot needed, 1 = reboot needed
dnf needs-restarting -r >/dev/null 2>&1
nr=$?
case "$nr" in
  0) log "No reboot needed." ;;
  1) log "REBOOT NEEDED (for example, a new kernel). Schedule one; the container restarts on boot." ;;
  *) log "Could not determine whether a reboot is needed (exit $nr)." ;;
esac

log "=== Patch run finished ==="