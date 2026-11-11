#!/usr/bin/env bash
#
# Usage: apply-live.sh <video> [--layer <layer>] [--mpv-options <options>]
#                              [--auto-pause] [--auto-mode <full|max>]
#
# Stops any running mpvpaper, starts the video on every output and clears
# awww so it stops rendering an old image or animated GIF behind the video.
# mpvpaper is detached from this script, so the apply finishes immediately
# while the video keeps playing.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/live-lib.sh"

VIDEO="${1:-}"
if [ -z "$VIDEO" ]; then
    echo "apply-live.sh: missing video path" >&2
    exit 2
fi
shift

LAYER="bottom"
MPV_OPTIONS=""
AUTO_PAUSE=0
AUTO_MODE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
    --layer)
        LAYER="${2:?apply-live.sh: --layer needs a value}"
        shift 2
        ;;
    --mpv-options)
        MPV_OPTIONS="${2:-}"
        shift 2
        ;;
    --auto-pause)
        AUTO_PAUSE=1
        shift
        ;;
    --auto-mode)
        AUTO_MODE="${2:?apply-live.sh: --auto-mode needs a value}"
        shift 2
        ;;
    *)
        echo "apply-live.sh: unknown option: $1" >&2
        exit 2
        ;;
    esac
done

case "$LAYER" in
    background|bottom|top|overlay) ;;
    *)
        echo "apply-live.sh: invalid layer: $LAYER" >&2
        exit 2
        ;;
esac

case "${AUTO_MODE,,}" in
    "") ;;
    full) AUTO_MODE="FULL" ;;
    max) AUTO_MODE="MAX" ;;
    *)
        echo "apply-live.sh: invalid auto-pause mode: $AUTO_MODE" >&2
        exit 2
        ;;
esac

[ -f "$VIDEO" ] || {
    echo "apply-live.sh: not a file: $VIDEO" >&2
    exit 1
}

command -v mpvpaper >/dev/null 2>&1 || {
    echo "mpvpaper not found" >&2
    exit 1
}

# Only one video at a time: replace whatever is running before starting the
# new one.
stop_live

options="no-audio loop"
if [ -n "$MPV_OPTIONS" ]; then
    options="$options $MPV_OPTIONS"
fi

ARGS=(mpvpaper -l "$LAYER" -o "$options")
[ "$AUTO_PAUSE" -eq 1 ] && ARGS+=(-p)
[ -n "$AUTO_MODE" ] && ARGS+=(-a "$AUTO_MODE")
ARGS+=(ALL "$VIDEO")

LOG_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/hyprland-wallpaper-picker"
mkdir -p -- "$LOG_DIR" 2>/dev/null || LOG_DIR="${TMPDIR:-/tmp}"
LOG="$LOG_DIR/mpvpaper.log"

# setsid keeps mpvpaper alive after this script exits. All standard streams
# are redirected so the Quickshell Process sees the script exit instead of
# waiting for the player.
setsid "${ARGS[@]}" </dev/null >"$LOG" 2>&1 &

for _ in $(seq 1 30); do
    [ -n "$(live_pids)" ] && break
    sleep 0.05
done

# Give mpv a moment to reject an unreadable or unsupported file.
sleep 0.2

if [ -z "$(live_pids)" ]; then
    detail="$(tail -n 3 "$LOG" 2>/dev/null)"
    if [ -n "$detail" ]; then
        printf 'mpvpaper failed: %s\n' "$detail" >&2
    else
        echo "mpvpaper failed to start" >&2
    fi
    exit 1
fi

# awww no longer needs to draw, and an animated GIF here would keep decoding
# behind the video. Failure is harmless, so it does not fail the apply.
if command -v awww >/dev/null 2>&1 && awww query >/dev/null 2>&1; then
    awww clear >/dev/null 2>&1 || true
fi
