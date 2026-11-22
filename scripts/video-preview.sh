#!/usr/bin/env bash
#
# Usage: video-preview.sh <source> <cacheDir> <width> <height> <seekSeconds> \
#   [quality] [preExtractedFrame]
#
# Generates or reuses a focused still preview for a video and prints its cached
# path. The crop is centred and covers width x height, like the strip
# thumbnails. When a poster frame was already extracted for the thumbnail it
# can be passed as preExtractedFrame to avoid decoding the video twice.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/video-lib.sh"

SRC="${1:-}"
CACHE="${2:-}"
W="${3:-}"
H="${4:-}"
SEEK="${5:-0}"
QUALITY="${6:-88}"
FRAME="${7:-}"

if [ -z "$SRC" ] || [ -z "$CACHE" ]; then
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

if ! [[ "$QUALITY" =~ ^[1-9][0-9]?$|^100$ ]]; then
    echo "video-preview.sh: invalid quality: $QUALITY" >&2
    exit 2
fi

if ! [[ "$SEEK" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "video-preview.sh: invalid seek: $SEEK" >&2
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

key="$(printf '%s' "v${VIDEO_PREVIEW_VERSION}|still|$SRC|${W}x${H}|s$SEEK|q$QUALITY" \
    | md5sum | cut -d' ' -f1)"
out="$CACHE/$key.jpg"

if [ ! -f "$out" ] || [ "$SRC" -nt "$out" ]; then
    if [ -z "$FRAME" ] || [ ! -s "$FRAME" ]; then
        FRAME="$WORK/frame.png"
        if ! video_poster "$SRC" "$FRAME" "$SEEK"; then
            echo "video-preview.sh: failed to extract a frame: $SRC" >&2
            exit 1
        fi
    fi

    tmp="$WORK/preview.jpg"
    if ! nice -n 10 magick "$FRAME[0]" -auto-orient -resize "${W}x${H}^" \
        -gravity center -extent "${W}x${H}" -quality "$QUALITY" "$tmp"; then
        echo "video-preview.sh: failed to generate preview: $SRC" >&2
        exit 1
    fi
    if [ ! -s "$tmp" ] || ! mv -f -- "$tmp" "$out"; then
        echo "video-preview.sh: failed to store preview: $out" >&2
        exit 1
    fi
fi

if [ ! -s "$out" ]; then
    echo "video-preview.sh: preview is missing: $out" >&2
    exit 1
fi

printf '%s\n' "$out"
