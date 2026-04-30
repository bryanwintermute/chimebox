# role: basiliskii

Installs Basilisk II, the classic Mac (68k) emulator that runs the
chimebox kiosk.

Strategy:
1. Try `apt install basilisk2`. The package is in Debian Bookworm's repos.
2. If that fails (e.g., not available for aarch64 in your apt sources),
   fall back to building from source against the macemu submodule.

For chimebox v1 we expect path 1 to work. The build-from-source fallback
is documented in tasks/build-from-source.yml but disabled by default.

# TODO: Verify `basilisk2` package availability and version on Raspberry
# Pi OS Bookworm aarch64. Validate against a real Pi.
