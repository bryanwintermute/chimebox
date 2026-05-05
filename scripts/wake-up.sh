#!/usr/bin/env bash
# scripts/wake-up.sh
#
# Restart the chimebox kiosk after bedtime.sh has stopped it. Inverse of
# bedtime.sh's phase 3: clears the bedtime sentinel (in case it was left
# behind by an interrupted bedtime.sh) and starts getty@tty1.service,
# which triggers the autologin -> startx -> BasiliskII chain.
#
# Usage:
#   ./wake-up.sh

SCRIPT_NAME="wake-up"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

chimebox_check_reachable

log_info "Starting the kiosk on ${CHIMEBOX_SSH_HOST}..."
log_info "(autologin -> X -> Plymouth handoff -> Mac OS 8.1 boot)"
chimebox_ssh_interactive "
    set -uo pipefail
    sudo rm -f /run/chimebox-bedtime
    sudo systemctl start getty@tty1.service
"
log_ok "Kiosk starting. Mac OS should boot to the desktop in 10-15 seconds."
