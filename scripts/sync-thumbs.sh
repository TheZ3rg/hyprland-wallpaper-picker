#!/usr/bin/env bash
#
# Usage: sync-thumbs.sh <wallpaperDir> <cacheDir> <cover|preserve> <w> <h> <ext,ext,...> [cornerRadius] [previewDir] [previewWidth] [previewHeight]
#
# Scans wallpaperDir (non-recursive), generates or reuses cached thumbnails,
# and prints one tab-separated manifest row per wallpaper:
#
#     <sourcePath>\t<thumbPath>\t<thumbWidth>\t<thumbHeight>\t<previewPath>
#
# <previewPath> is generated or reused during the scan and is empty only if
# preview generation failed.
# ImageMagick 7 is required. Thumbnails are keyed by the source path,
# generation options and cache version, and are regenerated when the source is
# newer. Files that cannot be converted are skipped with a diagnostic.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Bump this when thumbnail generation changes so old cache files are not
# reused.
CACHE_VERSION=1

DIR="${1:-}"
CACHE="${2:-}"
MODE="${3:-cover}"
W="${4:-420}"
H="${5:-640}"
EXTS="${6:-jpg,jpeg,png,webp}"
RADIUS="${7:-0}"
PREVIEW_DIR="${8:-}"
PREVIEW_W="${9:-}"
PREVIEW_H="${10:-}"

preview_enabled=0
if [ -n "$PREVIEW_DIR" ] \
    && [[ "$PREVIEW_W" =~ ^[1-9][0-9]*$ ]] \
    && [[ "$PREVIEW_H" =~ ^[1-9][0-9]*$ ]]; then
    preview_enabled=1
fi

if [ -z "$DIR" ] || [ -z "$CACHE" ]; then
    echo "sync-thumbs.sh: missing arguments" >&2
    exit 2
fi

case "$MODE" in
    cover|preserve) ;;
    *)
        echo "sync-thumbs.sh: invalid thumbnail mode: $MODE" >&2
        exit 2
        ;;
esac

if ! [[ "$W" =~ ^[1-9][0-9]*$ ]] || ! [[ "$H" =~ ^[1-9][0-9]*$ ]]; then
    echo "sync-thumbs.sh: thumbnail size must be positive: ${W}x${H}" >&2
    exit 2
fi

if ! [[ "$RADIUS" =~ ^[0-9]+$ ]]; then
    echo "sync-thumbs.sh: invalid corner radius: $RADIUS" >&2
    exit 2
fi

# A missing folder is a configuration error; an existing empty folder is not.
if [ ! -d "$DIR" ]; then
    echo "sync-thumbs.sh: wallpaper dir not found: $DIR" >&2
    exit 1
fi

command -v magick >/dev/null 2>&1 || {
    echo "sync-thumbs.sh: ImageMagick 7 (magick) is required" >&2
    exit 1
}

mkdir -p -- "$CACHE" || {
    echo "sync-thumbs.sh: cannot create cache dir: $CACHE" >&2
    exit 1
}

# Build the find expression: \( -iname "*.jpg" -o -iname "*.png" ... \).
find_args=()
first=1
IFS=',' read -ra exts <<< "$EXTS"
for e in "${exts[@]}"; do
    [ -z "$e" ] && continue
    if [ "$first" -eq 0 ]; then find_args+=( -o ); fi
    find_args+=( -iname "*.${e}" )
    first=0
done
if [ "${#find_args[@]}" -eq 0 ]; then
    echo "sync-thumbs.sh: no file extensions configured" >&2
    exit 2
fi

# Rounded corners need an alpha channel, so those thumbnails must be PNG.
if [ "$RADIUS" -gt 0 ]; then
    EXT="png"
else
    EXT="jpg"
fi

WORK="$(mktemp -d "$CACHE/.sync-thumbs.XXXXXX")" || {
    echo "sync-thumbs.sh: cannot create a temporary directory in $CACHE" >&2
    exit 1
}
trap 'rm -rf -- "$WORK"' EXIT

list="$WORK/files"
sorted="$WORK/sorted"
declare -A used_names=()

# sort -z keeps the manifest order stable, so the strip does not reshuffle
# when files are added or removed.
if ! find "$DIR" -maxdepth 1 -type f \( "${find_args[@]}" \) -print0 > "$list"; then
    echo "sync-thumbs.sh: failed to scan $DIR" >&2
    exit 1
fi
if ! sort -z "$list" > "$sorted"; then
    echo "sync-thumbs.sh: failed to sort the file list" >&2
    exit 1
fi

failed=0

while IFS= read -r -d '' f; do
    # Include the generation options in the key so changed settings do not
    # reuse stale thumbnails.
    key="$(printf '%s' "v${CACHE_VERSION}|$f|$MODE|${W}x${H}|r${RADIUS}" | md5sum)"
    key="${key%% *}"
    out="$CACHE/$key.$EXT"
    tmp="$WORK/thumb.png"
    final_tmp="$WORK/final.$EXT"
    generated=0

    if [ ! -f "$out" ] || [ "$f" -nt "$out" ]; then
        rm -f -- "$tmp" "$final_tmp"

        # Render to a temporary file first so an interrupted convert never
        # leaves a truncated thumbnail in the cache.
        if [ "$MODE" = "preserve" ]; then
            # ">" prevents upscaling small images.
            if ! magick "$f[0]" -auto-orient -thumbnail "${W}x${H}>" "$tmp"; then
                echo "sync-thumbs.sh: failed to generate thumbnail: $f" >&2
                failed=$((failed + 1))
                continue
            fi
        else
            if ! magick "$f[0]" -auto-orient -resize "${W}x${H}^" \
                -gravity center -extent "${W}x${H}" "$tmp"; then
                echo "sync-thumbs.sh: failed to generate thumbnail: $f" >&2
                failed=$((failed + 1))
                continue
            fi
        fi

        if [ ! -s "$tmp" ]; then
            echo "sync-thumbs.sh: empty thumbnail generated for: $f" >&2
            failed=$((failed + 1))
            continue
        fi

        # Dimensions are needed before masking and are the final thumbnail's
        # real size in preserve mode. Cover mode always produces W x H.
        if [ "$MODE" = "preserve" ]; then
            dims="$(magick identify -format '%w %h' "$tmp[0]")" || {
                echo "sync-thumbs.sh: cannot read thumbnail size for: $f" >&2
                failed=$((failed + 1))
                continue
            }
            read -r tw th <<< "$dims"
            if ! [[ "$tw" =~ ^[1-9][0-9]*$ ]] || ! [[ "$th" =~ ^[1-9][0-9]*$ ]]; then
                echo "sync-thumbs.sh: invalid thumbnail size for: $f" >&2
                failed=$((failed + 1))
                continue
            fi
        else
            tw="$W"
            th="$H"
        fi

        if [ "$RADIUS" -gt 0 ]; then
            # Bake the rounded corners into the alpha channel; QML then needs
            # no runtime mask.
            if ! magick "$tmp" \
                \( -size "${tw}x${th}" xc:none -fill white \
                   -draw "roundrectangle 0,0 $((tw - 1)),$((th - 1)) ${RADIUS},${RADIUS}" \) \
                -alpha off -compose CopyOpacity -composite "$final_tmp"; then
                echo "sync-thumbs.sh: failed to round thumbnail corners: $f" >&2
                failed=$((failed + 1))
                continue
            fi
        else
            if ! magick "$tmp" -quality 85 "$final_tmp"; then
                echo "sync-thumbs.sh: failed to write thumbnail: $f" >&2
                failed=$((failed + 1))
                continue
            fi
        fi

        if ! mv -f -- "$final_tmp" "$out"; then
            echo "sync-thumbs.sh: failed to store thumbnail for: $f" >&2
            failed=$((failed + 1))
            continue
        fi
        generated=1
    fi

    if [ ! -f "$out" ]; then
        echo "sync-thumbs.sh: thumbnail is missing: $out" >&2
        failed=$((failed + 1))
        continue
    fi

    if [ "$generated" -eq 0 ]; then
        if [ "$MODE" = "preserve" ]; then
            dims="$(magick identify -format '%w %h' "$out[0]")" || {
                echo "sync-thumbs.sh: cannot read thumbnail size for: $f" >&2
                failed=$((failed + 1))
                continue
            }
            read -r tw th <<< "$dims"
            if ! [[ "$tw" =~ ^[1-9][0-9]*$ ]] || ! [[ "$th" =~ ^[1-9][0-9]*$ ]]; then
                echo "sync-thumbs.sh: invalid thumbnail size for: $f" >&2
                failed=$((failed + 1))
                continue
            fi
        else
            tw="$W"
            th="$H"
        fi
    fi

    preview_path=""
    if [ "$preview_enabled" -eq 1 ]; then
        if ! preview_path="$(bash "$SCRIPT_DIR/preview-thumb.sh" \
            "$f" "$PREVIEW_DIR" "$PREVIEW_W" "$PREVIEW_H")"; then
            preview_path=""
            echo "sync-thumbs.sh: failed to cache preview: $f" >&2
        fi
    fi

    used_names["$key.$EXT"]=1
    printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$out" "$tw" "$th" "$preview_path"
done < "$sorted"

# Prune cache entries this scan did not produce. A failed scan returns before
# this point, so a temporarily unavailable folder cannot wipe the cache.
while IFS= read -r -d '' cached; do
    name="${cached##*/}"
    if [ -z "${used_names["$name"]:-}" ]; then
        rm -f -- "$cached"
    fi
done < <(find "$CACHE" -maxdepth 1 -type f -print0 2>/dev/null)

if [ "$failed" -gt 0 ]; then
    printf 'sync-thumbs.sh: %d file(s) could not be processed\n' "$failed" >&2
    exit 1
fi
