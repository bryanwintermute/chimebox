#!/usr/bin/env bash
# 1-build-library.sh
#
# Run Infinite Mac's `import-library` script in full (non-placeholder) mode.
# This pulls and processes the Macintosh Garden software library manifests
# and produces the data needed for `import-disks` to populate Infinite HD.
#
# This step is mostly a network/CPU job and produces intermediate caches in
# ~/.infinite-mac-cache and inside the Infinite Mac checkout.

set -euo pipefail

CHIMEBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFINITE_MAC_DIR="${CHIMEBOX_ROOT}/third_party/infinite-mac"

log()  { printf '\033[1;34m[1-build-library]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[1-build-library]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ ! -f "${INFINITE_MAC_DIR}/package.json" ]]; then
    fail "Infinite Mac submodule not initialized. Run ./0-bootstrap.sh first."
fi

log "Building Macintosh Garden library manifests (full mode)..."
log "(This downloads metadata from Macintosh Garden and may take several minutes.)"

(
    cd "${INFINITE_MAC_DIR}"
    npm run import-library
)

log "Library build complete."
log "Next: ./2-build-disks.sh"
