#!/usr/bin/env bash
# 3-collect.sh
#
# Gather chimebox-relevant outputs from the Infinite Mac build into ../disks/:
#   - System.dsk      <- reassembled from chunks (post-customization Mac OS 8.1)
#   - InfiniteHD.dsk  <- reassembled from chunks (curated library)
#
# Both disks are reassembled from the chunked manifests Infinite Mac produces
# (rather than copied from Images/), because the build pipeline applies
# in-place customization (welcome stickies, library injection) and only the
# customized chunked output is preserved past the build.
#
# Verifies the user-supplied Quadra-650.rom is in place too.

set -euo pipefail

CHIMEBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFINITE_MAC_DIR="${CHIMEBOX_ROOT}/third_party/infinite-mac"
DISKS_DIR="${CHIMEBOX_ROOT}/disks"

DATA_DIR="${INFINITE_MAC_DIR}/src/Data"
CHUNKS_DIR="${INFINITE_MAC_DIR}/Images/build"

log()  { printf '\033[1;34m[3-collect]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[3-collect]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[3-collect]\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p "${DISKS_DIR}"

if [[ ! -d "${CHUNKS_DIR}" ]]; then
    fail "Chunks dir not found: ${CHUNKS_DIR}
2-build-disks.sh must have completed successfully before running 3-collect.sh."
fi

reassemble() {
    local manifest_name="$1"
    local output_name="$2"

    local manifest="${DATA_DIR}/${manifest_name}"
    local output="${DISKS_DIR}/${output_name}"

    if [[ ! -f "${manifest}" ]]; then
        fail "Manifest not found: ${manifest}
2-build-disks.sh did not produce this manifest. Check its output for errors."
    fi

    log "Reassembling ${output_name} from ${manifest_name}..."
    python3 "${CHIMEBOX_ROOT}/disk-prep/reassemble_chunked.py" \
        --manifest "${manifest}" \
        --chunks-dir "${CHUNKS_DIR}" \
        --output "${output}"
    log "  $(ls -lh "${output}" | awk '{print $5}')  ${output}"
}

# 1. System.dsk = reassembled, customized Mac OS 8.1 HD
reassemble "Mac OS 8.1 HD.dsk.json" "System.dsk"

# 2. InfiniteHD.dsk = reassembled curated library
reassemble "Infinite HD.dsk.json" "InfiniteHD.dsk"

# 3. Verify Quadra-650.rom is in place (user-supplied).
ROM_PATH="${DISKS_DIR}/Quadra-650.rom"
ROM_EXPECTED_SIZE=1048576  # 1 MiB

if [[ ! -f "${ROM_PATH}" ]]; then
    warn ""
    warn "Quadra 650 ROM not found at: ${ROM_PATH}"
    warn "You must supply this yourself -- chimebox does not redistribute Apple ROMs."
    warn "See disk-prep/README.md > 'Obtaining the ROM' for guidance."
    warn ""
    warn "Disks were built but the chimebox cannot boot without a ROM."
else
    actual_size=$(stat -f%z "${ROM_PATH}" 2>/dev/null || stat -c%s "${ROM_PATH}")
    if [[ "${actual_size}" != "${ROM_EXPECTED_SIZE}" ]]; then
        warn "Quadra-650.rom size is ${actual_size} bytes; expected ${ROM_EXPECTED_SIZE}."
        warn "It may still work, but verify it's the correct ROM."
    else
        log "Quadra-650.rom present (${actual_size} bytes, looks correct)"
    fi
fi

log ""
log "Collection complete. Contents of disks/:"
ls -lh "${DISKS_DIR}" | sed 's/^/  /'
log ""
log "Next: push these to your Pi via ../scripts/push-disks.sh (coming soon)."
