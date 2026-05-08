#!/usr/bin/env bash
# scripts/factory-reset.sh
#
# Roll the chimebox System.dsk back to the operator-blessed factory
# baseline. Use this when even the rotating daily/weekly/manual
# snapshots have captured corruption, or when you want a clean
# "reset to as-shipped" rollback.
#
# Wraps /usr/local/sbin/chimebox-reset factory (installed by the
# persistence Ansible role) with the kiosk-stop/start dance.
#
# Usage:
#   ./factory-reset.sh

SCRIPT_NAME="factory-reset"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

chimebox_check_reachable

log_warn "This will overwrite System.dsk with the factory baseline."
log_warn "ALL state since the last factory bless will be lost --"
log_warn "including curation, drawings, saved games, anything not"
log_warn "captured in the factory image."
read -r -p "Type 'factory' to confirm: " confirm
if [[ "$confirm" != "factory" ]]; then
    log_info "Aborted."
    exit 0
fi

log_warn "Stopping the kiosk first..."
chimebox_ssh_interactive "
    set -euo pipefail
    sudo systemctl stop getty@tty1.service || true
    sudo pkill -u ${CHIMEBOX_USER} || true
    sleep 1
    sudo /usr/local/sbin/chimebox-reset factory
    sudo systemctl start getty@tty1.service
"
log_ok "Factory reset complete. Kiosk has been restarted."
