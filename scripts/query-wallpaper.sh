#!/usr/bin/env bash
#
# Usage: query-wallpaper.sh
#
# Prints the active wallpaper as one tab-separated line:
#
#     video\t<path>   a video played by mpvpaper
#     image\t<path>   an image or GIF shown by awww
#
# The path is empty when nothing is displayed. awww is only queried when no
# mpvpaper is running, so a video behind a stale awww image is still reported
# as the active wallpaper.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/live-lib.sh"

pids="$(live_pids)"
if [ -n "$pids" ]; then
    pid="${pids%%$'\n'*}"
    if [ -r "/proc/$pid/cmdline" ]; then
        # mpvpaper takes the video as its last argument.
        path="$(tr '\0' '\n' < "/proc/$pid/cmdline" | tail -n1)"
        printf 'video\t%s\n' "$path"
        exit 0
    fi
fi

if ! command -v awww >/dev/null 2>&1; then
    echo "awww not found" >&2
    exit 127
fi

if ! out="$(awww query 2>&1)"; then
    printf '%s\n' "$out" >&2
    exit 1
fi

# Example: ": DP-2: 2560x1440, scale: 1, currently displaying: image: /path"
path="$(printf '%s\n' "$out" \
    | sed -n 's/.*currently displaying: *image: *//p' \
    | head -n1)"
printf 'image\t%s\n' "$path"
