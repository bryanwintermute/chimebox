#!/usr/bin/env bash
# scripts/factory-bless.sh
#
# Capture the current System.dsk on the Pi as the factory baseline.
# The factory baseline is what scripts/factory-reset.sh rolls the
# kiosk back to when even the daily/weekly/manual snapshots have
# captured corruption.
#
# Bless after curation milestones (e.g., kid-shortlist setup is
# complete and the desktop is the way you want it long-term) so
# factory-reset is a meaningful "reset to the version I shipped"
# rollback. Re-blessing replaces the prior factory baseline with
# the current System.dsk -- the prior baseline is unrecoverable.
#
# Usage:
#   ./factory-bless.sh

SCRIPT_NAME="factory-bless"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

chimebox_check_reachable

log_warn "This will OVERWRITE the factory baseline with current System.dsk."
log_warn "The kiosk will be briefly stopped to capture a clean copy."
log_warn "Re-blessing makes the previous factory baseline unrecoverable."
read -r -p "Type 'bless' to confirm: " confirm
if [[ "$confirm" != "bless" ]]; then
    log_info "Aborted."
    exit 0
fi

log_info "Stopping kiosk and blessing factory baseline..."
chimebox_ssh_interactive "
    set -euo pipefail
    sudo systemctl stop getty@tty1.service || true
    sudo pkill -u ${CHIMEBOX_USER} || true
    sleep 1
    sudo /usr/local/sbin/chimebox-snapshot factory
    sudo systemctl start getty@tty1.service
"
log_ok "Factory bless complete. Kiosk has been restarted."
log_info "Use scripts/factory-reset.sh to roll back to this baseline."
