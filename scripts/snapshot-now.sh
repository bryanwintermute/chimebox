#!/usr/bin/env bash
# scripts/snapshot-now.sh
#
# Trigger an immediate manual snapshot of the chimebox System.dsk on the Pi.
# Wraps /usr/local/sbin/chimebox-snapshot (installed by the persistence
# Ansible role).

SCRIPT_NAME="snapshot-now"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

chimebox_check_reachable

log_info "Taking manual snapshot on ${CHIMEBOX_SSH_HOST}..."
chimebox_ssh_interactive "sudo /usr/local/sbin/chimebox-snapshot manual"
log_ok "Snapshot complete."
