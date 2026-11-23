#!/usr/bin/env bash
#
# Usage: preview-thumb.sh <source> <cacheDir> <width> <height> [quality] \
#   [seekSeconds] [preExtractedFrame]
#
# Generates or reuses the wider, higher-resolution crop shown in the center
# card and prints the cached preview path on success. The crop is centred and
# covers width x height, like the strip thumbnails, but comes from the original
# image and uses the requested aspect and size. Quality defaults to 88.
#
# Without seekSeconds the source is a still image. With it the source is a
# video and the frame is extracted with ffmpeg; a poster frame already
# extracted for the video thumbnail can be passed as preExtractedFrame to avoid
# decoding the video twice.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/video-lib.sh"

# Bump these when the preview output changes so cached previews are rebuilt.
PREVIEW_VERSION=1
VIDEO_PREVIEW_VERSION=1

SRC="${1:-}"
CACHE="${2:-}"
W="${3:-}"
H="${4:-}"
QUALITY="${5:-88}"
SEEK="${6:-}"
FRAME="${7:-}"

if [ -z "$SRC" ] || [ -z "$CACHE" ]; then
    echo "preview-thumb.sh: missing arguments" >&2
    exit 2
fi

if [ ! -f "$SRC" ]; then
    echo "preview-thumb.sh: not a file: $SRC" >&2
    exit 1
fi

if ! [[ "$W" =~ ^[1-9][0-9]*$ ]] || ! [[ "$H" =~ ^[1-9][0-9]*$ ]]; then
    echo "preview-thumb.sh: invalid size: ${W}x${H}" >&2
    exit 2
fi

if ! [[ "$QUALITY" =~ ^[1-9][0-9]?$|^100$ ]]; then
    echo "preview-thumb.sh: invalid quality: $QUALITY" >&2
    exit 2
fi

if [ -n "$SEEK" ] && ! [[ "$SEEK" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "preview-thumb.sh: invalid seek: $SEEK" >&2
    exit 2
fi

command -v magick >/dev/null 2>&1 || {
    echo "preview-thumb.sh: ImageMagick 7 (magick) is required" >&2
    exit 1
}

mkdir -p -- "$CACHE" || {
    echo "preview-thumb.sh: cannot create cache dir: $CACHE" >&2
    exit 1
}

WORK="$(mktemp -d "$CACHE/.preview.XXXXXX")" || {
    echo "preview-thumb.sh: cannot create a temporary directory in $CACHE" >&2
    exit 1
}
trap 'rm -rf -- "$WORK"' EXIT

if [ -n "$SEEK" ]; then
    key="$(printf '%s' "v${VIDEO_PREVIEW_VERSION}|still|$SRC|${W}x${H}|s$SEEK|q$QUALITY" \
        | md5sum | cut -d' ' -f1)"
else
    key="$(printf '%s' "v${PREVIEW_VERSION}|$SRC|cover|${W}x${H}|q$QUALITY|preview" \
        | md5sum | cut -d' ' -f1)"
fi
out="$CACHE/$key.jpg"

if [ ! -f "$out" ] || [ "$SRC" -nt "$out" ]; then
    input="$SRC"
    if [ -n "$SEEK" ]; then
        if [ -z "$FRAME" ] || [ ! -s "$FRAME" ]; then
            FRAME="$WORK/frame.png"
            if ! video_poster "$SRC" "$FRAME" "$SEEK"; then
                echo "preview-thumb.sh: failed to extract a frame: $SRC" >&2
                exit 1
            fi
        fi
        input="$FRAME"
    fi

    tmp="$WORK/preview.jpg"

    # Render to a temporary file so an interrupted convert never leaves a
    # truncated preview in the cache.
    if ! nice -n 10 magick "$input[0]" -auto-orient -resize "${W}x${H}^" \
        -gravity center -extent "${W}x${H}" -quality "$QUALITY" "$tmp"; then
        echo "preview-thumb.sh: failed to generate preview: $SRC" >&2
        exit 1
    fi

    if [ ! -s "$tmp" ]; then
        echo "preview-thumb.sh: empty preview generated: $SRC" >&2
        exit 1
    fi

    if ! mv -f -- "$tmp" "$out"; then
        echo "preview-thumb.sh: failed to store preview: $out" >&2
        exit 1
    fi
fi

if [ ! -s "$out" ]; then
    echo "preview-thumb.sh: preview is missing: $out" >&2
    exit 1
fi

printf '%s\n' "$out"
