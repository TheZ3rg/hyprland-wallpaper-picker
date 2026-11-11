#!/usr/bin/env bash
#
# Usage: apply.sh <image> [awww img options...]
#
# Stops mpvpaper, waits for the awww daemon, then forwards the image and
# options to `awww img`. The daemon owns the active image; nothing is
# persisted here.

set -euo pipefail

IMG="${1:?usage: apply.sh <image> [awww options...]}"
shift

[ -f "$IMG" ] || {
    echo "apply.sh: not a file: $IMG" >&2
    exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/live-lib.sh"

# A running video would keep covering the image.
stop_live

bash "$SCRIPT_DIR/ensure-awww-daemon.sh"

awww img "$IMG" "$@"
