#!/usr/bin/env bash
#
# Apply a wallpaper through awww.
#
# Usage:
#   apply.sh <image> [awww img options...]
#
# Arguments:
#   $1    image to display (must be an existing file)
#   $2... options forwarded verbatim to `awww img` (built by AwwwBackend)
#
# awww caches the last image itself and restores it when the daemon starts, so
# there is nothing to persist here (no config file to rewrite).

set -euo pipefail

IMG="${1:?usage: apply.sh <image> [awww options...]}"
# Drop the image path so "$@" contains only awww options.
shift

# Fail early with a clear message instead of letting awww handle a bad path.
[ -f "$IMG" ] || {
    echo "apply.sh: not a file: $IMG" >&2
    exit 1
}

# Fail if awww is not installed at all.
command -v awww >/dev/null 2>&1 || {
    echo "apply.sh: awww not found" >&2
    exit 1
}

# Make sure the daemon is running (it normally autostarts with the session).
# `setsid` detaches it so it survives this script; poll briefly because
# `awww img` fails if the daemon's socket is not ready yet.
if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    setsid awww-daemon >/dev/null 2>&1 &
    for _ in $(seq 1 50); do
        pgrep -x awww-daemon >/dev/null 2>&1 && break
        sleep 0.05
    done
fi

# Hand the image to the daemon. All options were forwarded from the caller;
# the command returns as soon as the request is accepted.
awww img "$IMG" "$@"

# TODO(theming): run matugen here once it is wired up, e.g.
#     matugen image "$IMG" --mode dark --source-color-index 0
#
# TODO(animated): when animated wallpapers land, only pass static images here
# and hand gif/webm files to awww's animated path instead.
