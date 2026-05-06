# role: basiliskii

Installs Basilisk II, the classic Mac (68k) emulator that runs the
chimebox kiosk.

Strategy:
1. Try `apt install basilisk2`. The package is in Debian Trixie and Bookworm
   contrib repos for arm64 (same version 0.9.20240402+dfsg-1+b1).
2. If that fails (e.g., contrib not enabled or the package was pulled
   from a future release), fall back to building from source against
   the macemu submodule.

For chimebox v1 we expect path 1 to work on Pi OS Trixie Lite. The
build-from-source fallback is documented in tasks/build-from-source.yml
but disabled by default.

The `basilisk2` apt package is what we install on Raspberry Pi OS
Bookworm/Trixie aarch64; validated end-to-end on a real Pi 5.
