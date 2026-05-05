#!/usr/bin/env bash
# scripts/bedtime.sh
#
# Gracefully wind down the chimebox kiosk for bedtime.
#
# Phase 1: send SIGTERM to BasiliskII. The signal is forwarded by the
#          emulator to the guest as a "user requested shutdown", which
#          triggers Mac OS 8.1's standard shutdown-confirmation dialog
#          on the kiosk screen. Gives the kid a chance to save and
#          shut down on her own terms.
#
# Phase 2: sleep for warn-minutes (default 5).
#
# Phase 3: stop the kiosk entirely -- stop getty@tty1.service, kill any
#          leftover chimebox processes. X tears down; the screen goes
#          to whatever state the monitor lands on (usually black).
#
# To restart the kiosk in the morning: scripts/wake-up.sh
#
# Usage:
#   ./bedtime.sh              # default 5-minute warning
#   ./bedtime.sh 10           # 10-minute warning
#   ./bedtime.sh 0            # immediate shutdown (still graceful via SIGTERM)
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

chimebox_check_reachable

# If user Ctrl-C's during the wait, leave the kiosk running -- we already
# sent SIGTERM but the Mac OS dialog is still up; user can decide.
trap 'echo; log_warn "Interrupted. Mac OS shutdown dialog may still be showing on the kiosk; the kiosk has NOT been force-stopped."; exit 130' INT TERM

log_info "Asking Mac OS to shut down (SIGTERM -> BasiliskII)..."
log_info "Mac OS 8.1 shutdown dialog should appear on the chimebox screen."
chimebox_ssh_interactive "
    set -euo pipefail
    bpid=\$(pgrep -f BasiliskII | head -1 || true)
    if [[ -z \"\${bpid}\" ]]; then
        echo 'bedtime: no BasiliskII process running; kiosk may already be down.' >&2
        exit 0
    fi
    sudo kill -TERM \"\${bpid}\"
    echo \"bedtime: SIGTERM sent to BasiliskII pid \${bpid}\"
"

if (( WARN_MINUTES == 0 )); then
    log_info "No warning period requested; proceeding to full shutdown immediately."
else
    log_info "Waiting ${WARN_MINUTES} minute(s) so the kid can wrap up. (Ctrl-C to abort.)"
    remaining="${WARN_MINUTES}"
    while (( remaining > 0 )); do
        if (( remaining == 1 )); then
            log_info "  1 minute remaining..."
        else
            log_info "  ${remaining} minutes remaining..."
        fi
        sleep 60
        remaining=$(( remaining - 1 ))
    done
fi

log_info "Stopping the kiosk (X teardown; screen blank until wake-up.sh)..."
chimebox_ssh_interactive "
    set -euo pipefail
    sudo systemctl stop getty@tty1.service || true
    sudo pkill -u ${CHIMEBOX_USER} || true
    sleep 1
"
log_ok "Goodnight. Run ./wake-up.sh to start the kiosk in the morning."
