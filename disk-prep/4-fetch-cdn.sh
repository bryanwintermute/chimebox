#!/usr/bin/env bash
# 4-fetch-cdn.sh
#
# Fast-path disk-prep: fetch System.dsk + InfiniteHD.dsk from the
# Infinite Mac CDN instead of running the full upstream pipeline.
#
# Output goes to ../disks/, ready for ../scripts/push-disks.sh.
#
# Trade-offs vs. the full pipeline (disk-prep/prep.sh):
#   - MUCH faster (~10-15 min vs ~1.5-2 hours)
#   - No GUI emulator interaction required
#   - No need to install Mini vMac / BasiliskII as Mac apps
#   - You get exactly what infinitemac.org serves; no opportunity to
#     customize the disk image at build time
#
# If you want to customize the disk (e.g., inject a kid-shortlist
# folder onto the desktop at build time), use the full pipeline.
# Otherwise this is the recommended path.

set -euo pipefail

CHIMEBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${CHIMEBOX_ROOT}/disk-prep"
DISKS_DIR="${CHIMEBOX_ROOT}/disks"

log()  { printf '\033[1;34m[4-fetch-cdn]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[4-fetch-cdn]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[4-fetch-cdn]\033[0m %s\n' "$*" >&2; exit 1; }

# Sanity: python3 available
command -v python3 >/dev/null 2>&1 || fail "python3 not found on PATH"

mkdir -p "${DISKS_DIR}"

log "Fetching System (Mac OS 8.1 HD) and InfiniteHD from infinitemac.org ..."
log "(chunks cached at ~/.chimebox-cache/chunks/, safe to delete)"
log ""

python3 "${SCRIPT_DIR}/fetch-from-cdn.py" \
    --output-dir "${DISKS_DIR}" \
    --output-name "Mac OS 8.1 HD=System" \
    --output-name "Infinite HD=InfiniteHD" \
    "Mac OS 8.1 HD" \
    "Infinite HD"

log ""
log "Done. Outputs:"
ls -lh "${DISKS_DIR}" | sed 's/^/  /'
log ""
log "Next steps:"
log "  1. Verify your Quadra-650.rom is at ${DISKS_DIR}/Quadra-650.rom"
log "     (use third_party/infinite-mac/src/Data/Quadra-650.rom if needed)"
log "  2. Push to the Pi: ../scripts/push-disks.sh"
