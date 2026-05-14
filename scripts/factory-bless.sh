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
# Polite shutdown semantics: this script asks Mac OS to shut down
# cleanly (via SIGTERM to BasiliskII, which forwards to the guest
# as "user requested shutdown") and waits for the emulator to exit
# before capturing System.dsk. That way the blessed image has the
# HFS "Volume Unmounted cleanly" flag set, so factory-reset boots
# don't show "Mac OS was not shut down properly."
#
# The Mac will display its standard "Shut Down? / Restart / Cancel"
# confirmation dialog on the kiosk screen. The operator must click
# 'Shut Down' for the bless to proceed. We wait up to 5 minutes;
# if the operator doesn't click in time we abort cleanly (the
# kiosk recovers without a dirty bless).
#
# Usage:
#   ./factory-bless.sh

SCRIPT_NAME="factory-bless"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

chimebox_check_reachable

log_warn "This will OVERWRITE the factory baseline with current System.dsk."
log_warn "Mac OS will be politely shut down first (its shutdown dialog will"
log_warn "appear on the kiosk screen -- click 'Shut Down' to proceed)."
log_warn "Re-blessing makes the previous factory baseline unrecoverable."
read -r -p "Type 'bless' to confirm: " confirm
if [[ "$confirm" != "bless" ]]; then
    log_info "Aborted."
    exit 0
fi

log_info "Asking Mac OS to shut down on ${CHIMEBOX_SSH_HOST}..."
log_info "Click 'Shut Down' on the Mac screen when the dialog appears."

# Single SSH session: arm sentinel, SIGTERM, wait for clean exit,
# capture, clear sentinel, restart kiosk. One sudo prompt total.
# Reuses the /run/chimebox-bedtime sentinel pattern from bedtime.sh
# so the supervisor loop in start.sh doesn't respawn BasiliskII
# between the Mac OS shutdown and our snapshot capture.
chimebox_ssh_interactive "
set -uo pipefail

# Phase 1: arm sentinel, SIGTERM BasiliskII
sudo touch /run/chimebox-bedtime
sudo chmod 644 /run/chimebox-bedtime
# pgrep -x matches program NAME (comm), not full cmdline. Using -f
# here would match this script's bash because 'BasiliskII' appears
# in the script body.
bpid=\$(pgrep -x BasiliskII | head -1 || true)
if [ -n \"\${bpid}\" ]; then
    sudo kill -TERM \"\${bpid}\"
    echo \"factory-bless: SIGTERM sent to BasiliskII pid \${bpid}\"
    echo 'factory-bless: click Shut Down on the Mac screen now.'
else
    echo 'factory-bless: BasiliskII not running; proceeding to capture.'
fi

# Phase 2: poll for clean BasiliskII exit. The supervisor loop's
# natural respawn gap is 1-2s; >5s absent reliably means Mac OS
# shut down cleanly and the supervisor is idling on the sentinel.
end=\$(( \$(date +%s) + 300 ))
absent_since=0
last_minute_log=\$(date +%s)
while [ \"\$(date +%s)\" -lt \"\${end}\" ]; do
    now=\$(date +%s)
    if pgrep -x BasiliskII >/dev/null; then
        absent_since=0
    else
        [ \"\${absent_since}\" -eq 0 ] && absent_since=\${now}
        if [ \$(( now - absent_since )) -ge 5 ]; then
            echo 'factory-bless: BasiliskII absent >5s -- Mac shut down cleanly.'
            break
        fi
    fi
    if [ \$(( now - last_minute_log )) -ge 60 ]; then
        remaining=\$(( end - now ))
        mins=\$(( (remaining + 59) / 60 ))
        echo \"factory-bless: waiting for shutdown (\${mins} minute(s) before giving up)...\"
        last_minute_log=\${now}
    fi
    sleep 2
done

# Did Mac OS actually exit cleanly?
if pgrep -x BasiliskII >/dev/null; then
    echo 'factory-bless: ERROR: BasiliskII still running after 5 minutes.'
    echo 'factory-bless: refusing to capture a dirty System.dsk. Clearing sentinel so the kiosk recovers.'
    sudo rm -f /run/chimebox-bedtime
    exit 1
fi

# Phase 3: capture. System.dsk is now in a clean-unmount state.
echo 'factory-bless: capturing System.dsk -> factory.dsk...'
sudo /usr/local/sbin/chimebox-snapshot factory

# Phase 4: clear sentinel -> supervisor loop respawns BasiliskII
# automatically within 1-2s. No need to bounce getty.
sudo rm -f /run/chimebox-bedtime
echo 'factory-bless: sentinel cleared; kiosk supervisor will respawn the Mac.'
"
log_ok "Factory bless complete. Kiosk has been restarted."
log_info "Use scripts/factory-reset.sh to roll back to this baseline."
