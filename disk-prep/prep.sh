#!/usr/bin/env bash
# prep.sh
#
# Top-level disk-prep convenience wrapper: runs steps 0-3 in sequence.
#
# For development, run the numbered scripts individually instead.
# Each is idempotent and re-runnable.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

./0-bootstrap.sh
./1-build-library.sh
./2-build-disks.sh
./3-collect.sh

echo
echo "==============================================="
echo "  disk-prep complete."
echo "  Outputs are in ../disks/"
echo "==============================================="
