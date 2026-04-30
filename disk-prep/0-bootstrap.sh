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
    # uv installer writes a PATH-setup script at ~/.local/bin/env; source it
    # so this same shell can find uv without requiring the user to restart.
    if [[ -f "$HOME/.local/bin/env" ]]; then
        # shellcheck disable=SC1091
        source "$HOME/.local/bin/env"
    fi
    if ! command -v uv >/dev/null 2>&1; then
        # Fall back: try the well-known install path directly.
        if [[ -x "$HOME/.local/bin/uv" ]]; then
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi
    if ! command -v uv >/dev/null 2>&1; then
        fail "uv installed but not on PATH. Open a new shell and re-run."
    fi
fi
log "uv present ($(uv --version))"

# 5. node + npm (Infinite Mac uses npm scripts as the entry points).
#    If Homebrew is present and node isn't, offer to brew-install it.
ensure_node() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        return 0
    fi
    if command -v brew >/dev/null 2>&1; then
        log "node/npm not found but Homebrew is. Installing node via brew..."
        brew install node
        # brew on Apple Silicon installs to /opt/homebrew/bin; ensure it's on PATH
        if [[ -d /opt/homebrew/bin ]] && [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
            export PATH="/opt/homebrew/bin:$PATH"
        fi
    else
        fail "node/npm not found and Homebrew is not installed.
Install Node.js via your preferred method (Homebrew: 'brew install node',
or see https://nodejs.org), then re-run this script."
    fi
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        fail "node/npm still not on PATH after install. Open a new shell and re-run."
    fi
}
ensure_node
log "node present ($(node --version))"
log "npm present ($(npm --version))"

# 7. Run Infinite Mac's build prerequisites manually rather than via their
#    build-tools.sh: their script aborts (set -e) at the xcodebuild step if
#    only Command Line Tools (not full Xcode) are installed, which prevents
#    the subsequent dmg2img build from happening. We reimplement the same
#    steps with a Homebrew-unar fallback for the no-Xcode case.
log "Installing Infinite Mac's Python and Node dependencies..."
(
    cd "${INFINITE_MAC_DIR}"
    npm install --silent --no-audit --no-fund
    uv sync
)

# 7a. lsar/unar -- needed to extract Macintosh Garden archives.
XADMASTER_RELEASE="${INFINITE_MAC_DIR}/XADMaster-build/Release"
need_unar_setup=true
if [[ -x "${XADMASTER_RELEASE}/lsar" ]] && [[ -x "${XADMASTER_RELEASE}/unar" ]]; then
    log "lsar/unar already in place at ${XADMASTER_RELEASE}"
    need_unar_setup=false
fi

if [[ "${need_unar_setup}" == "true" ]]; then
    has_full_xcode=true
    if ! xcodebuild -version >/dev/null 2>&1; then
        has_full_xcode=false
    fi

    if [[ "${has_full_xcode}" == "true" ]]; then
        log "Full Xcode detected -- building lsar/unar from XADMaster source..."
        (
            cd "${INFINITE_MAC_DIR}"
            git submodule update --init XADMaster UniversalDetector
            mkdir -p XADMaster-build
            xcodebuild -scheme lsar -project XADMaster/XADMaster.xcodeproj \
                -configuration Release SYMROOT="$(pwd)/XADMaster-build"
            xcodebuild -scheme unar -project XADMaster/XADMaster.xcodeproj \
                -configuration Release SYMROOT="$(pwd)/XADMaster-build"
        )
    else
        log "Full Xcode not installed (only Command Line Tools). Falling back"
        log "to Homebrew's prebuilt unar package..."
        if ! command -v brew >/dev/null 2>&1; then
            fail "Need either full Xcode (App Store) or Homebrew. Install one and re-run."
        fi
        if ! command -v unar >/dev/null 2>&1 || ! command -v lsar >/dev/null 2>&1; then
            brew install unar
            if [[ -d /opt/homebrew/bin ]] && [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
                export PATH="/opt/homebrew/bin:$PATH"
            fi
        fi
        mkdir -p "${XADMASTER_RELEASE}"
        ln -sf "$(command -v lsar)" "${XADMASTER_RELEASE}/lsar"
        ln -sf "$(command -v unar)" "${XADMASTER_RELEASE}/unar"
        log "Symlinked lsar/unar from Homebrew into ${XADMASTER_RELEASE}"
    fi
fi

# 7b. dmg2img -- used to convert .dmg disk images to .img.
DMG2IMG_DIR="${INFINITE_MAC_DIR}/dmg2img"
if [[ ! -x "${DMG2IMG_DIR}/dmg2img" ]]; then
    log "Building dmg2img..."
    if [[ ! -d "${DMG2IMG_DIR}" ]]; then
        git clone --quiet https://github.com/Lekensteyn/dmg2img.git "${DMG2IMG_DIR}"
    fi
    (cd "${DMG2IMG_DIR}" && make dmg2img)
else
    log "dmg2img already built at ${DMG2IMG_DIR}/dmg2img"
fi

log "Bootstrap complete."
log ""
log "Next steps:"
log "  1. Place your Quadra 650 ROM at: ${CHIMEBOX_ROOT}/disks/Quadra-650.rom"
log "  2. Run: ./1-build-library.sh"
