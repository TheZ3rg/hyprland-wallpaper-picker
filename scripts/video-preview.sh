#!/usr/bin/env bash
#
# Usage:
#   video-preview.sh still <source> <cacheDir> <width> <height> <seekSeconds>
#   video-preview.sh animated <source> <cacheDir> <width> <height> \
#       <durationMs> <fps> <quality> [startSeconds]
#
# Generates or reuses a focused preview for a video or animated GIF and prints
# its cached path. "still" produces a JPEG crop from one frame; "animated"
# produces a muted looping WebP clip. Both crops are centred and cover
# width x height, like the strip thumbnails.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/video-lib.sh"

MODE="${1:-}"
SRC="${2:-}"
CACHE="${3:-}"
W="${4:-}"
H="${5:-}"

if [ -z "$MODE" ] || [ -z "$SRC" ] || [ -z "$CACHE" ]; then
    echo "video-preview.sh: missing arguments" >&2
    exit 2
fi

if [ ! -f "$SRC" ]; then
    echo "video-preview.sh: not a file: $SRC" >&2
    exit 1
fi

if ! [[ "$W" =~ ^[1-9][0-9]*$ ]] || ! [[ "$H" =~ ^[1-9][0-9]*$ ]]; then
    echo "video-preview.sh: invalid size: ${W}x${H}" >&2
    exit 2
fi

command -v ffmpeg >/dev/null 2>&1 || {
    echo "video-preview.sh: ffmpeg is required" >&2
    exit 1
}

mkdir -p -- "$CACHE" || {
    echo "video-preview.sh: cannot create cache dir: $CACHE" >&2
    exit 1
}

WORK="$(mktemp -d "$CACHE/.video-preview.XXXXXX")" || {
    echo "video-preview.sh: cannot create a temporary directory in $CACHE" >&2
    exit 1
}
trap 'rm -rf -- "$WORK"' EXIT

if [ "$MODE" = "still" ]; then
    SEEK="${6:-0}"
    key="$(printf '%s' "v${VIDEO_PREVIEW_VERSION}|still|$SRC|${W}x${H}|s$SEEK" \
        | md5sum | cut -d' ' -f1)"
    out="$CACHE/$key.jpg"

    if [ ! -f "$out" ] || [ "$SRC" -nt "$out" ]; then
        frame="$WORK/frame.png"
        if ! video_poster "$SRC" "$frame" "$SEEK"; then
            echo "video-preview.sh: failed to extract a frame: $SRC" >&2
            exit 1
        fi

        tmp="$WORK/preview.jpg"
        if ! nice -n 10 magick "$frame[0]" -auto-orient -resize "${W}x${H}^" \
            -gravity center -extent "${W}x${H}" -quality 88 "$tmp"; then
            echo "video-preview.sh: failed to generate preview: $SRC" >&2
            exit 1
        fi
        if [ ! -s "$tmp" ] || ! mv -f -- "$tmp" "$out"; then
            echo "video-preview.sh: failed to store preview: $out" >&2
            exit 1
        fi
    fi
elif [ "$MODE" = "animated" ]; then
    DURATION_MS="${6:-}"
    FPS="${7:-}"
    QUALITY="${8:-}"
    START="${9:-0}"

    if ! [[ "$DURATION_MS" =~ ^[1-9][0-9]*$ ]] \
        || ! [[ "$FPS" =~ ^[1-9][0-9]*$ ]] \
        || ! [[ "$QUALITY" =~ ^[0-9]+$ ]]; then
        echo "video-preview.sh: invalid animation settings" >&2
        exit 2
    fi

    seconds="$(printf '%s.%03d' $((DURATION_MS / 1000)) $((DURATION_MS % 1000)))"
    key="$(printf '%s' "v${VIDEO_PREVIEW_VERSION}|animated|$SRC|${W}x${H}|d${DURATION_MS}|fps${FPS}|q${QUALITY}|s${START}" \
        | md5sum | cut -d' ' -f1)"
    out="$CACHE/$key.webp"

    if [ ! -f "$out" ] || [ "$SRC" -nt "$out" ]; then
        tmp="$WORK/preview.webp"
        FILTER="fps=${FPS},scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H}"

        # Fast seeking into a very short clip can land past the end; retry
        # from the beginning before giving up.
        if ! nice -n 10 ffmpeg -nostdin -hide_banner -loglevel error \
                -ss "$START" -i "$SRC" -t "$seconds" -an \
                -vf "$FILTER" -c:v libwebp_anim -loop 0 \
                -q:v "$QUALITY" "$tmp" -y >/dev/null 2>&1 \
                || [ ! -s "$tmp" ]; then
            rm -f -- "$tmp"
            if [ "$START" != "0" ] \
                && nice -n 10 ffmpeg -nostdin -hide_banner -loglevel error \
                    -i "$SRC" -t "$seconds" -an \
                    -vf "$FILTER" -c:v libwebp_anim -loop 0 \
                    -q:v "$QUALITY" "$tmp" -y >/dev/null 2>&1 \
                && [ -s "$tmp" ]; then
                :
            else
                echo "video-preview.sh: failed to generate preview: $SRC" >&2
                exit 1
            fi
        fi

        if [ ! -s "$tmp" ] || ! mv -f -- "$tmp" "$out"; then
            echo "video-preview.sh: failed to store preview: $out" >&2
            exit 1
        fi
    fi
else
    echo "video-preview.sh: unknown mode: $MODE" >&2
    exit 2
fi

if [ ! -s "$out" ]; then
    echo "video-preview.sh: preview is missing: $out" >&2
    exit 1
fi

printf '%s\n' "$out"
