#!/usr/bin/env bash
# scripts/_lib.sh
#
# Shared helpers for chimebox workstation-side scripts. Source this from
# any script in scripts/ -- it loads config and defines logging+SSH
# helpers.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPTS_DIR}/.." && pwd)"

# Load config: prefer config.sh, fall back to config.example.sh
if [[ -f "${SCRIPTS_DIR}/config.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPTS_DIR}/config.sh"
else
    # shellcheck disable=SC1091
    source "${SCRIPTS_DIR}/config.example.sh"
    echo "[chimebox] Note: scripts/config.sh not found, using example defaults." >&2
    echo "[chimebox] Copy config.example.sh to config.sh and edit for your env." >&2
fi

# Color logging
if [[ -t 1 ]]; then
    _C_INFO=$'\033[1;34m'
    _C_OK=$'\033[1;32m'
    _C_WARN=$'\033[1;33m'
    _C_ERR=$'\033[1;31m'
    _C_RESET=$'\033[0m'
else
    _C_INFO="" _C_OK="" _C_WARN="" _C_ERR="" _C_RESET=""
fi

log_info() { printf '%s[%s]%s %s\n' "${_C_INFO}" "${SCRIPT_NAME:-chimebox}" "${_C_RESET}" "$*"; }
log_ok()   { printf '%s[%s]%s %s\n' "${_C_OK}"   "${SCRIPT_NAME:-chimebox}" "${_C_RESET}" "$*"; }
log_warn() { printf '%s[%s]%s %s\n' "${_C_WARN}" "${SCRIPT_NAME:-chimebox}" "${_C_RESET}" "$*" >&2; }
log_err()  { printf '%s[%s]%s %s\n' "${_C_ERR}"  "${SCRIPT_NAME:-chimebox}" "${_C_RESET}" "$*" >&2; }
fail()     { log_err "$*"; exit 1; }

# Run a command on the Pi as the admin user.
chimebox_ssh() {
    ssh "${CHIMEBOX_SSH_OPTS[@]}" "${CHIMEBOX_ADMIN_USER}@${CHIMEBOX_SSH_HOST}" "$@"
}

# Interactive SSH session as the admin user.
chimebox_ssh_interactive() {
    ssh -t "${CHIMEBOX_SSH_OPTS[@]}" "${CHIMEBOX_ADMIN_USER}@${CHIMEBOX_SSH_HOST}" "$@"
}

# Verify connectivity. Call early in any script.
chimebox_check_reachable() {
    # Run via ssh directly so connect-timeout flags go to ssh, not the
    # remote command. Don't use BatchMode=yes -- it disables agent
    # forwarding, which would make an SSH-agent-managed key (e.g.
    # 1Password) appear unavailable even when it actually works for
    # subsequent calls.
    if ! ssh "${CHIMEBOX_SSH_OPTS[@]}" -o ConnectTimeout=5 \
            "${CHIMEBOX_ADMIN_USER}@${CHIMEBOX_SSH_HOST}" 'true' 2>/dev/null; then
        fail "Cannot reach ${CHIMEBOX_ADMIN_USER}@${CHIMEBOX_SSH_HOST}.
  Check that the Pi is up and your SSH key is authorized.
  Try: ssh ${CHIMEBOX_ADMIN_USER}@${CHIMEBOX_SSH_HOST}"
    fi
}

# Run rsync to the Pi as the admin user.
# Args: same as rsync; CHIMEBOX_SSH_OPTS are applied automatically.
chimebox_rsync() {
    local rsh="ssh ${CHIMEBOX_SSH_OPTS[*]}"
    rsync -e "${rsh}" "$@"
}
