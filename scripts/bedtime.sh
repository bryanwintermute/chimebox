#!/usr/bin/env bash
# scripts/bedtime.sh
#
# Gracefully wind down the chimebox kiosk for bedtime.
#
# Phase 1: arm a "bedtime sentinel" file at /run/chimebox-bedtime, then
#          send SIGTERM to BasiliskII. The signal is forwarded by the
#          emulator to the guest as a "user requested shutdown", which
#          triggers Mac OS 8.1's standard shutdown-confirmation dialog.
#
#          The sentinel is what tells the supervisor loop in start.sh
#          NOT to respawn BasiliskII when it exits. Without it, a kid
#          who clicks "Shut Down" during the warning period would just
#          watch the Mac auto-restart -- defeating the whole point.
#
# Phase 2: poll for early shutdown for up to warn-minutes (default 5).
#          If BasiliskII stays absent for >5s the kid clicked Shut Down
#          (the supervisor would otherwise have respawned within 1-2s)
#          -- we short-circuit straight to phase 3.
#          0 minutes = skip the poll entirely.
#
# Phase 3: stop getty@tty1.service + pkill -u chimebox to tear down
#          the X stack. Remove the sentinel so wake-up.sh starts cleanly.
#          Pi stays up; screen blanks.
#
# To restart in the morning: scripts/wake-up.sh
#
# Usage:
#   ./bedtime.sh              # default 5-minute warning
#   ./bedtime.sh 10           # 10-minute warning
#   ./bedtime.sh 0            # immediate (still graceful via SIGTERM)
#
# Why not poweroff the Pi entirely? Two reasons: (1) the chimebox user
# can't run systemctl poweroff without a sudoers entry we haven't added
# yet, and (2) leaving the Pi up means morning wake-up is one SSH command
# away rather than requiring a power-button press. The Pi sips ~3W idle.

SCRIPT_NAME="bedtime"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

WARN_MINUTES="${1:-5}"

if ! [[ "${WARN_MINUTES}" =~ ^[0-9]+$ ]]; then
    fail "Usage: $0 [warn-minutes]   (got: ${WARN_MINUTES})"
fi

WARN_SECONDS=$(( WARN_MINUTES * 60 ))

chimebox_check_reachable

# A single SSH session does the whole bedtime cycle: arm sentinel,
# SIGTERM, poll, stop kiosk. One sudo prompt total. If the user Ctrl-C's
# the local script, the SSH session is terminated and the sentinel may
# be left armed -- wake-up.sh always clears it before starting.
log_info "Starting bedtime cycle on ${CHIMEBOX_SSH_HOST}..."
log_info "Mac OS 8.1 shutdown dialog will appear on the chimebox screen."
if (( WARN_MINUTES > 0 )); then
    log_info "Waiting up to ${WARN_MINUTES} minute(s); will short-circuit if the kid chooses Shut Down."
fi

chimebox_ssh_interactive "
set -uo pipefail

# Phase 1: arm sentinel, send SIGTERM
sudo touch /run/chimebox-bedtime
sudo chmod 644 /run/chimebox-bedtime
# pgrep -x matches the program NAME (comm), not the full command line
# (-f). Using -f here would match this very script's bash because the
# string 'BasiliskII' appears in the script body.
bpid=\$(pgrep -x BasiliskII | head -1 || true)
if [ -n \"\${bpid}\" ]; then
    sudo kill -TERM \"\${bpid}\"
    echo \"bedtime: SIGTERM sent to BasiliskII pid \${bpid}; sentinel armed.\"
else
    echo 'bedtime: no BasiliskII process; sentinel armed anyway.'
fi

# Phase 2: poll for early shutdown.
# 'absent_since' tracks how long BasiliskII has been gone. The supervisor
# loop's natural respawn gap is 1-2 seconds; >5s of absence reliably
# means the sentinel has caused it to idle (kid chose Shut Down).
WARN_SECONDS=${WARN_SECONDS}
if [ \"\${WARN_SECONDS}\" -gt 0 ]; then
    end=\$(( \$(date +%s) + WARN_SECONDS ))
    absent_since=0
    last_minute_log=\$(date +%s)
    while [ \"\$(date +%s)\" -lt \"\${end}\" ]; do
        now=\$(date +%s)
        # pgrep -x (NOT -f) -- see comment above.
        if pgrep -x BasiliskII >/dev/null; then
            absent_since=0
        else
            [ \"\${absent_since}\" -eq 0 ] && absent_since=\${now}
            if [ \$(( now - absent_since )) -ge 5 ]; then
                echo 'bedtime: BasiliskII absent >5s -- kid chose Shut Down. Proceeding.'
                break
            fi
        fi
        if [ \$(( now - last_minute_log )) -ge 60 ]; then
            remaining=\$(( end - now ))
            mins=\$(( (remaining + 59) / 60 ))
            echo \"bedtime: \${mins} minute(s) remaining...\"
            last_minute_log=\${now}
        fi
        sleep 5
    done
fi

# Phase 3: stop the kiosk, clear the sentinel.
echo 'bedtime: stopping kiosk (X teardown; screen will blank)...'
sudo systemctl stop getty@tty1.service || true
sudo pkill -u ${CHIMEBOX_USER} || true
sleep 1
sudo rm -f /run/chimebox-bedtime
echo 'bedtime: sentinel cleared, kiosk stopped.'
"

log_ok "Goodnight. Run ./wake-up.sh to start the kiosk in the morning."
