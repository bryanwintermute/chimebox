#!/usr/bin/env bash
# scripts/push-disks.sh
#
# Rsync the prepared ROM and disk images from ../disks/ to the chimebox
# runtime directory on the Pi.
#
# The kiosk user (chimebox) does not accept SSH, so we rsync to a staging
# dir owned by the admin user, then SSH+sudo to install into the kiosk
# user's home with correct ownership. You'll be prompted for the admin
# user's sudo password once.
#
# Idempotent: re-running uploads only changed bytes (rsync delta-xfer).

SCRIPT_NAME="push-disks"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

# Required local files
readonly REQUIRED_FILES=(
    "Quadra-650.rom"
    "System.dsk"
)

# Optional files (InfiniteHD.dsk is the curated library; you can run a
# perfectly functional kiosk without it for a basic case).
readonly OPTIONAL_FILES=(
    "InfiniteHD.dsk"
)

# Validate locally before doing anything network-y
log_info "Checking local disks/ dir: ${CHIMEBOX_LOCAL_DISKS_DIR}"
missing=0
files_to_push=()
for f in "${REQUIRED_FILES[@]}"; do
    p="${CHIMEBOX_LOCAL_DISKS_DIR}/${f}"
    if [[ ! -f "${p}" ]]; then
        log_err "  missing: ${p}"
        missing=$((missing + 1))
    else
        size=$(wc -c < "${p}")
        log_info "  ok: ${f} (${size} bytes)"
        files_to_push+=("${f}")
    fi
done
for f in "${OPTIONAL_FILES[@]}"; do
    p="${CHIMEBOX_LOCAL_DISKS_DIR}/${f}"
    if [[ -f "${p}" ]]; then
        size=$(wc -c < "${p}")
        log_info "  ok (optional): ${f} (${size} bytes)"
        files_to_push+=("${f}")
    else
        log_info "  skip (optional, not present): ${f}"
    fi
done

if [[ ${missing} -gt 0 ]]; then
    fail "${missing} required file(s) missing. Run disk-prep/prep.sh first
  (and place the ROM at ${CHIMEBOX_LOCAL_DISKS_DIR}/Quadra-650.rom)."
fi

# Connectivity check
log_info "Checking SSH to ${CHIMEBOX_SSH_HOST}..."
chimebox_check_reachable
log_ok "SSH reachable"

# Stage to /tmp on the Pi (owned by admin user; cleaned up at end).
STAGING_DIR="/tmp/chimebox-staging-$$"
log_info "Staging to ${STAGING_DIR} on Pi..."
chimebox_ssh "mkdir -p '${STAGING_DIR}'"

# Trap to clean up staging on any exit
trap 'chimebox_ssh "rm -rf ${STAGING_DIR}" 2>/dev/null || true' EXIT

# Rsync each file. -P shows progress, --inplace avoids huge temp files.
log_info "Uploading disks (delta-xfer; only changed bytes are sent)..."
for f in "${files_to_push[@]}"; do
    chimebox_rsync -avP --inplace \
        "${CHIMEBOX_LOCAL_DISKS_DIR}/${f}" \
        "${CHIMEBOX_ADMIN_USER}@${CHIMEBOX_SSH_HOST}:${STAGING_DIR}/${f}"
done

# Install: move into runtime dir, fix ownership, fix perms.
# sudo prompt happens once (here) and persists for the rest of the SSH session.
log_info "Installing into ${CHIMEBOX_RUNTIME_DIR} on Pi (sudo password prompt incoming)..."
chimebox_ssh_interactive "
    set -euo pipefail
    sudo install -d -o ${CHIMEBOX_USER} -g ${CHIMEBOX_USER} -m 0750 '${CHIMEBOX_RUNTIME_DIR}'
    for f in ${files_to_push[*]}; do
        sudo install -o ${CHIMEBOX_USER} -g ${CHIMEBOX_USER} -m 0640 \
            '${STAGING_DIR}'/\$f '${CHIMEBOX_RUNTIME_DIR}'/\$f
    done
    # InfiniteHD.dsk (if present) is read-only at runtime; mark it explicitly.
    if [[ -f '${CHIMEBOX_RUNTIME_DIR}/InfiniteHD.dsk' ]]; then
        sudo chmod 0440 '${CHIMEBOX_RUNTIME_DIR}/InfiniteHD.dsk'
    fi
    echo 'Installed:'
    sudo ls -lh '${CHIMEBOX_RUNTIME_DIR}'
"

log_ok "Disks installed. Reboot the Pi (or restart the kiosk) to load them."
