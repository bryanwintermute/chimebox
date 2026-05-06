#!/usr/bin/env bash
# scripts/config.example.sh
#
# Copy to scripts/config.sh and edit for your environment.
# config.sh is gitignored; it should never be committed.

# Hostname or IP of the Pi. If you've set up an SSH config alias
# (recommended), use the alias here. Otherwise use the hostname or IP.
CHIMEBOX_SSH_HOST="chimebox-dev.local"

# Admin user on the Pi (created by Pi Imager during first-boot setup).
# Has sudo and SSH access. NOT the kiosk user.
CHIMEBOX_ADMIN_USER="admin"

# Kiosk user on the Pi (created by the Ansible kiosk-user role).
# Runs the X session and emulator. No SSH access, no sudo.
CHIMEBOX_USER="chimebox"

# Where the chimebox runtime files live on the Pi.
# Must match group_vars/all.yml's chimebox_runtime_dir.
CHIMEBOX_RUNTIME_DIR="/home/${CHIMEBOX_USER}/chimebox"

# Local directory containing the prepared ROM and disk images.
# Default: ../disks/ relative to scripts/
# Override only if you keep them elsewhere.
CHIMEBOX_LOCAL_DISKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/disks"

# SSH options applied to all connections. Don't usually need to change.
CHIMEBOX_SSH_OPTS=(-o ConnectTimeout=10)
