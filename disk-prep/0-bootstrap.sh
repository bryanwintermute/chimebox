#!/usr/bin/env bash
# 0-bootstrap.sh
#
# Bootstrap the disk-prep environment on macOS:
# - verify we're on macOS
# - verify Xcode CLT is present
# - install uv if missing
# - initialize Infinite Mac's submodules (XADMaster, UniversalDetector, etc.)
# - run Infinite Mac's build-tools.sh (builds lsar/unar, fetches dmg2img)
#
# Idempotent: re-running is safe and skips already-done work.

set -euo pipefail

CHIMEBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFINITE_MAC_DIR="${CHIMEBOX_ROOT}/third_party/infinite-mac"

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bootstrap]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[bootstrap]\033[0m %s\n' "$*" >&2; exit 1; }

# 1. macOS check
if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "disk-prep is macOS-only for v1. See LICENSING.md and disk-prep/README.md."
fi
log "macOS detected ($(sw_vers -productVersion))"

# 2. Xcode Command Line Tools
if ! xcode-select -p >/dev/null 2>&1; then
    fail "Xcode Command Line Tools not installed. Run: xcode-select --install"
fi
log "Xcode Command Line Tools present"

# 3. Submodule initialized?
if [[ ! -f "${INFINITE_MAC_DIR}/package.json" ]]; then
    fail "third_party/infinite-mac/ is empty. Run: git submodule update --init third_party/infinite-mac"
fi
log "Infinite Mac submodule present at ${INFINITE_MAC_DIR}"

# 4. uv
if ! command -v uv >/dev/null 2>&1; then
    log "uv not found, installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # shellcheck disable=SC1091
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    if ! command -v uv >/dev/null 2>&1; then
        fail "uv installed but not on PATH. Open a new shell and re-run."
    fi
fi
log "uv present ($(uv --version))"

# 5. npm (Infinite Mac uses npm scripts as the entry points)
if ! command -v npm >/dev/null 2>&1; then
    fail "npm not found. Install Node.js (e.g. via 'brew install node') and re-run."
fi
log "npm present ($(npm --version))"

# 6. Initialize Infinite Mac's *recursive* submodules.
#    The disk-prep pipeline needs XADMaster + UniversalDetector to build
#    the lsar/unar tools. The emulator submodules (macemu, minivmac, etc.)
#    are only needed if rebuilding emulator cores -- we skip those here
#    by initializing only the ones build-tools.sh actually uses.
log "Initializing Infinite Mac's tooling submodules..."
(
    cd "${INFINITE_MAC_DIR}"
    git submodule update --init XADMaster UniversalDetector
)

# 7. Run Infinite Mac's build-tools.sh, which builds lsar/unar and fetches dmg2img.
log "Running Infinite Mac's build-tools.sh..."
(
    cd "${INFINITE_MAC_DIR}"
    npm install --silent --no-audit --no-fund
    npm run build-tools
)

log "Bootstrap complete."
log ""
log "Next steps:"
log "  1. Place your Quadra 650 ROM at: ${CHIMEBOX_ROOT}/disks/Quadra-650.rom"
log "  2. Run: ./1-build-library.sh"
