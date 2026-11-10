#!/usr/bin/env bash
#
# Usage: preview-thumb.sh <source> <cacheDir> <width> <height>
#
# Generates or reuses a wider, higher-resolution crop for the focused tile and
# prints the cached preview path on success. The crop is centred and covers
# width x height, like the strip thumbnails, but comes from the original image
# and uses the requested aspect and size.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/preview-lib.sh"

SRC="${1:-}"
CACHE="${2:-}"
W="${3:-}"
H="${4:-}"

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

command -v magick >/dev/null 2>&1 || {
    echo "preview-thumb.sh: ImageMagick 7 (magick) is required" >&2
    exit 1
}

mkdir -p -- "$CACHE" || {
    echo "preview-thumb.sh: cannot create cache dir: $CACHE" >&2
    exit 1
}

key="$(preview_key "$SRC" "$W" "$H")"
out="$CACHE/$key.jpg"

if [ ! -f "$out" ] || [ "$SRC" -nt "$out" ]; then
    WORK="$(mktemp -d "$CACHE/.preview.XXXXXX")" || {
        echo "preview-thumb.sh: cannot create a temporary directory in $CACHE" >&2
        exit 1
    }
    trap 'rm -rf -- "$WORK"' EXIT

    tmp="$WORK/preview.jpg"

    # Render to a temporary file so an interrupted convert never leaves a
    # truncated preview in the cache.
    if ! nice -n 10 magick "$SRC[0]" -auto-orient -resize "${W}x${H}^" \
        -gravity center -extent "${W}x${H}" -quality 88 "$tmp"; then
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
