#!/usr/bin/env bash
#
# Usage: apply.sh <image> [awww img options...]
#
# Ensures the awww daemon is running, then forwards the image and options to
# `awww img`. The daemon owns the active image; nothing is persisted here.

set -euo pipefail

IMG="${1:?usage: apply.sh <image> [awww options...]}"
shift

[ -f "$IMG" ] || {
    echo "apply.sh: not a file: $IMG" >&2
    exit 1
}

command -v awww >/dev/null 2>&1 || {
    echo "apply.sh: awww not found" >&2
    exit 1
}

# The daemon normally autostarts with the session. Detach it with setsid so it
# survives this script, and poll because `awww img` fails until its socket is
# ready.
if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    setsid awww-daemon >/dev/null 2>&1 &
    for _ in $(seq 1 50); do
        pgrep -x awww-daemon >/dev/null 2>&1 && break
        sleep 0.05
    done
fi

awww img "$IMG" "$@"
