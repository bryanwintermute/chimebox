#!/usr/bin/env bash
# scripts/service-mode.sh
#
# Pause the chimebox kiosk and drop into an admin shell on the Pi.
# When the shell exits, the kiosk is resumed automatically.
#
# Useful for: apt updates, debugging, inspecting logs, replacing files,
# etc., without yanking power or pulling the SD card.

SCRIPT_NAME="service-mode"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

chimebox_check_reachable

log_info "Pausing the chimebox kiosk on ${CHIMEBOX_SSH_HOST}..."
chimebox_ssh_interactive "
    set -euo pipefail
    sudo systemctl stop getty@tty1.service || true
    sudo pkill -u ${CHIMEBOX_USER} || true
    sleep 1
"
log_ok "Kiosk paused."

log_info "Opening admin shell. Type 'exit' or press Ctrl-D when done."
log_info "The kiosk will resume automatically when you exit."
echo

# Use 'set +e' for the interactive shell -- we want service mode to ALWAYS
# resume the kiosk even if the shell exits non-zero.
set +e
chimebox_ssh_interactive
ssh_rc=$?
set -e

echo
log_info "Resuming the chimebox kiosk..."
chimebox_ssh "sudo systemctl start getty@tty1.service"
log_ok "Kiosk resumed."

if [[ ${ssh_rc} -ne 0 ]]; then
    log_warn "(Admin shell exited with code ${ssh_rc}.)"
fi
