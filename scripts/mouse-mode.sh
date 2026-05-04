#!/usr/bin/env bash
# scripts/mouse-mode.sh
#
# Toggle BasiliskII's mouse-input mode on the Pi without re-running the
# Ansible playbook. Useful for switching between physical-mouse and
# PiKVM-mouse setups that prefer different B2 input handling.
#
# Usage:
#     ./mouse-mode.sh grab        # init_grab=true  (relative-mouse capture)
#     ./mouse-mode.sh absolute    # init_grab=false (absolute X coords)
#     ./mouse-mode.sh             # report current state
#
# The change takes effect on the next kiosk start. The script will offer
# to restart the kiosk for you so you can see the result immediately.
#
# When to use 'grab':
#   - A physical USB mouse plugged into the Pi.
#   - Best kiosk experience (cursor cannot escape the Mac screen).
#
# When to use 'absolute':
#   - Driving the Mac via PiKVM (which sends absolute HID coords).
#   - Other absolute-positioning input devices (graphics tablets, etc).
#   - Some VNC scenarios.

SCRIPT_NAME="mouse-mode"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

PREFS_PATH="/home/${CHIMEBOX_USER}/.config/BasiliskII/prefs"

current_mode() {
    chimebox_ssh "sudo grep -E '^init_grab ' '${PREFS_PATH}'" 2>/dev/null
}

set_mode() {
    local target="$1"
    local value
    case "${target}" in
        grab|relative)     value="true"  ;;
        absolute|abs|free) value="false" ;;
        *) fail "unknown mode '${target}'. Try: grab, absolute" ;;
    esac

    log_info "Setting init_grab=${value} in ${PREFS_PATH}..."
    chimebox_ssh "sudo sed -i 's|^init_grab .*|init_grab ${value}|' '${PREFS_PATH}'"

    # Verify
    actual=$(current_mode)
    log_ok "Now: ${actual}"

    # Offer to restart the kiosk
    printf "Restart kiosk now to apply? [y/N] "
    read -r yn
    if [[ "${yn}" =~ ^[Yy] ]]; then
        log_info "Stopping kiosk..."
        chimebox_ssh "sudo systemctl stop getty@tty1.service"
        # Use loginctl instead of pkill -- safer + sandbox-friendly
        chimebox_ssh "sudo loginctl terminate-user ${CHIMEBOX_USER} 2>/dev/null || true; sleep 2"
        log_info "Starting kiosk..."
        chimebox_ssh "sudo systemctl reset-failed getty@tty1.service; sudo systemctl start getty@tty1.service"
        log_ok "Kiosk restarted with new mouse mode."
    else
        log_info "Skipped restart. Change takes effect on next kiosk start."
    fi
}

chimebox_check_reachable

if [[ $# -eq 0 ]]; then
    log_info "Current mouse mode:"
    current_mode | sed 's/^/  /'
    echo
    echo "Change with: $0 grab   (default; physical mouse / kiosk use)"
    echo "         or: $0 absolute   (PiKVM, VNC, tablet, etc.)"
    exit 0
fi

set_mode "$1"
