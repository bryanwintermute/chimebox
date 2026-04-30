#!/usr/bin/env bash
# scripts/kid-reset.sh
#
# Restore System.dsk on the Pi from a chosen snapshot.
# Wraps /usr/local/sbin/chimebox-reset (installed by the persistence
# Ansible role).
#
# Usage:
#   ./kid-reset.sh                # interactive: list snapshots, ask which one
#   ./kid-reset.sh latest         # restore from the most recent snapshot
#   ./kid-reset.sh <snapshot-filename>

SCRIPT_NAME="kid-reset"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

chimebox_check_reachable

# Mode 1: argument given -> pass through to chimebox-reset
if [[ $# -ge 1 ]]; then
    log_info "Restoring System.dsk from: $1"
    log_warn "Stopping the kiosk first to avoid corrupting an in-use image..."
    chimebox_ssh_interactive "
        set -euo pipefail
        sudo systemctl stop getty@tty1.service || true
        sudo pkill -u ${CHIMEBOX_USER} || true
        sleep 1
        sudo /usr/local/sbin/chimebox-reset $(printf '%q' "$1")
        sudo systemctl start getty@tty1.service
    "
    log_ok "Reset complete. Kiosk has been restarted."
    exit 0
fi

# Mode 2: interactive
log_info "Available snapshots on ${CHIMEBOX_SSH_HOST}:"
chimebox_ssh_interactive "sudo /usr/local/sbin/chimebox-reset list"
echo
read -r -p "Snapshot filename to restore (or 'latest', or blank to abort): " choice
if [[ -z "${choice}" ]]; then
    log_info "Aborted."
    exit 0
fi

log_warn "Stopping the kiosk first..."
chimebox_ssh_interactive "
    set -euo pipefail
    sudo systemctl stop getty@tty1.service || true
    sudo pkill -u ${CHIMEBOX_USER} || true
    sleep 1
    sudo /usr/local/sbin/chimebox-reset $(printf '%q' "${choice}")
    sudo systemctl start getty@tty1.service
"
log_ok "Reset complete. Kiosk has been restarted."
