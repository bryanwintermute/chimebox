#!/usr/bin/env bash
# 2-build-disks.sh
#
# Run Infinite Mac's `import-disks` script in full mode.
#
# This is THE LONG STEP. It:
#   - chunks all stock system disks
#   - builds Infinite HD by injecting the Macintosh Garden library
#   - launches Mini vMac and Basilisk II (NATIVE GUI APPS) to rebuild
#     the desktop database on the produced disks
#   - chunks the produced Infinite HD disks for browser serving
#
# When Mini vMac and Basilisk II appear on screen:
#   - Wait for the boot to complete and Infinite HD to mount.
#   - Use Special > Shut Down (or equivalent) to cleanly stop the emulated Mac.
#   - The emulator window will close and the script will continue.
#   - Mini vMac speed tip: Control-S, then A for "All Out".
#
# This step is gated on you being physically present at the Mac to do those
# emulator interactions. Plan accordingly.

set -euo pipefail

CHIMEBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFINITE_MAC_DIR="${CHIMEBOX_ROOT}/third_party/infinite-mac"

log()  { printf '\033[1;34m[2-build-disks]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[2-build-disks]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[2-build-disks]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ ! -f "${INFINITE_MAC_DIR}/package.json" ]]; then
    fail "Infinite Mac submodule not initialized. Run ./0-bootstrap.sh first."
fi

log "About to run Infinite Mac's import-disks pipeline."
log "Mini vMac and Basilisk II will launch on your desktop -- you must"
log "manually shut down the emulated Macs when prompted (Special > Shut Down)."
log ""
log "Press Enter to continue, or Ctrl-C to abort."
read -r

(
    cd "${INFINITE_MAC_DIR}"
    npm run import-disks
)

log "Disk build complete."
log ""
log "Outputs of interest:"
log "  - Stock disk: ${INFINITE_MAC_DIR}/Images/Mac OS 8.1 HD.dsk"
log "  - Chunked Infinite HD: ${INFINITE_MAC_DIR}/Images/build/*.chunk"
log "  - Manifest:   ${INFINITE_MAC_DIR}/src/Data/Infinite HD.json"
log ""
log "Next: ./3-collect.sh  (gathers chimebox-relevant outputs into ../disks/)"
