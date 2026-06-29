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

# --blessed <factory.dsk>: after the normal push, install a curated/blessed
# System.dsk (the gift image) instead of the repo's stock one. Push this LAST.
BLESSED=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --blessed) BLESSED="$2"; shift 2 ;;
        *) log_err "unknown arg: $1"; exit 2 ;;
    esac
done

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

    # If we just pushed an InfiniteHD.dsk and the BasiliskII prefs file
    # doesn't already mount it, add a 'disk' line. Idempotent.
    #
    # The existence checks MUST be sudo'd: /home/${CHIMEBOX_USER} is mode
    # 0750 owned by the kiosk user and the admin user running this SSH
    # session is not in that group, so a plain [[ -f ]] returns false even
    # when the files exist -- silently skipping the injection (#15). Every
    # branch prints a diagnostic so the outcome is never silent.
    PREFS=/home/${CHIMEBOX_USER}/.config/BasiliskII/prefs
    LIB_PATH='${CHIMEBOX_RUNTIME_DIR}/InfiniteHD.dsk'
    if ! sudo test -f \"\$LIB_PATH\"; then
        echo 'InfiniteHD: no InfiniteHD.dsk in runtime dir; nothing to add to prefs.'
    elif ! sudo test -f \"\$PREFS\"; then
        echo 'InfiniteHD: WARNING prefs file not found; run Ansible provisioning first.'
    elif sudo grep -qF \"disk \$LIB_PATH\" \"\$PREFS\"; then
        echo 'InfiniteHD: already present in BasiliskII prefs (no change).'
    elif ! sudo grep -qE \"^disk ${CHIMEBOX_RUNTIME_DIR//\\//\\\\/}\\/System.dsk\" \"\$PREFS\"; then
        echo 'InfiniteHD: WARNING no System.dsk line to anchor after; NOT added.'
    else
        # System.dsk is already first; a plain append keeps it the boot disk.
    # (sed insert-after-anchor was fragile: controller-side slash-escaping
    # mangled through the nested SSH heredoc on a fresh box. grep -qF above
    # keeps this idempotent; the elif anchors that System.dsk exists first.)
        sudo tee -a \"\$PREFS\" >/dev/null <<<\"disk \$LIB_PATH\"
        echo 'InfiniteHD: added to BasiliskII prefs.'
    fi

    echo 'Installed:'
    sudo ls -lh '${CHIMEBOX_RUNTIME_DIR}'
"

log_ok "Disks installed. Reboot the Pi (or restart the kiosk) to load them."

if [[ -n "${BLESSED}" ]]; then
    [[ -f "${BLESSED}" ]] || { log_err "blessed image not found: ${BLESSED}"; exit 2; }
    log_info "Installing BLESSED System.dsk from ${BLESSED} (stops the Mac first)..."
    chimebox_ssh_interactive "sudo /usr/local/sbin/chimebox-stop-mac || true"
    chimebox_rsync -P "${BLESSED}" \
        "${CHIMEBOX_ADMIN_USER}@${CHIMEBOX_SSH_HOST}:/tmp/blessed.dsk"
    chimebox_ssh_interactive "
        sudo install -o ${CHIMEBOX_USER} -g ${CHIMEBOX_USER} -m 0640 \
            /tmp/blessed.dsk '${CHIMEBOX_RUNTIME_DIR}/System.dsk'
        sudo rm -f /tmp/blessed.dsk /run/chimebox-bedtime
    "
    log_ok "Blessed image installed as System.dsk; kiosk will respawn the curated Mac."
fi
