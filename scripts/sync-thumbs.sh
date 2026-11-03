#!/usr/bin/env bash
#
# Scan a wallpaper folder, generate/cache thumbnails, and print a manifest to
# stdout, one line per wallpaper:
#
#     <sourcePath>\t<thumbPath>\t<thumbWidth>\t<thumbHeight>
#
# Usage:
#   sync-thumbs.sh <wallpaperDir> <cacheDir> <cover|preserve> <w> <h> <ext,ext,...> [cornerRadius]
#
# Arguments:
#   $1  wallpaperDir  folder to scan (non-recursive)
#   $2  cacheDir      thumbnail cache; created if missing
#   $3  mode          cover = crop to w x h, preserve = keep aspect ratio
#   $4  width         thumbnail box width
#   $5  height        thumbnail box height
#   $6  extensions    comma-separated, lowercase, no dots (e.g. "jpg,png")
#   $7  cornerRadius  optional, px baked into the thumbnail (0 = square)
#
# Thumbnails are keyed by the MD5 of the source path and regenerated when the
# source is newer. When cornerRadius > 0 the corners are rounded and baked into
# a PNG (so no runtime masking is needed). The cache is safe to delete.

set -uo pipefail

DIR="${1:-}"
CACHE="${2:-}"
MODE="${3:-cover}"
W="${4:-420}"
H="${5:-640}"
EXTS="${6:-jpg,jpeg,png,webp}"
RADIUS="${7:-0}"

if [ -z "$DIR" ] || [ -z "$CACHE" ]; then
    echo "sync-thumbs.sh: missing arguments" >&2
    exit 2
fi
# A missing folder is not an error: print an empty manifest so the picker
# shows an empty strip instead of failing to start.
if [ ! -d "$DIR" ]; then
    echo "sync-thumbs.sh: wallpaper dir not found: $DIR" >&2
    exit 0
fi

mkdir -p "$CACHE" 2>/dev/null || true

# Build the find expression: \( -iname "*.jpg" -o -iname "*.png" ... \).
# Only the first extension gets no leading -o.
find_args=()
first=1
IFS=',' read -ra exts <<< "$EXTS"
for e in "${exts[@]}"; do
    [ -z "$e" ] && continue
    if [ "$first" -eq 0 ]; then find_args+=( -o ); fi
    find_args+=( -iname "*.${e}" )
    first=0
done
# Fall back to JPEG if the caller passed an empty extension list.
if [ "${#find_args[@]}" -eq 0 ]; then
    find_args+=( -iname "*.jpg" )
fi

# ImageMagick is optional: without it we still print the source image and let
# QML decode it (slower, but functional). Thumbnails are an optimisation.
have_magick=0
command -v magick >/dev/null 2>&1 && have_magick=1

# Rounded corners need alpha, so those thumbnails must be PNG; everything else
# is JPEG (smaller files, faster to decode).
if [ "$RADIUS" -gt 0 ] 2>/dev/null; then
    EXT="png"
else
    EXT="jpg"
fi

# Remember every cache file produced by this scan. Anything not listed here is
# an orphan (deleted/renamed wallpaper, or old generation options) and gets
# pruned at the end.
used_list="$(mktemp)"
: > "$used_list"

# `sort -z` keeps the manifest order stable between scans, so the strip does
# not reshuffle when files are added or removed.
find "$DIR" -maxdepth 1 -type f \( "${find_args[@]}" \) -print0 2>/dev/null |
    sort -z |
    while IFS= read -r -d '' f; do
        # Cache key includes the generation options so changing mode/size/radius
        # regenerates the thumbnails instead of reusing stale ones.
        key="$(printf '%s' "$f|$MODE|${W}x${H}|r${RADIUS}" | md5sum | cut -d' ' -f1)"
        out="$CACHE/$key.$EXT"
        printf '%s\n' "$key.$EXT" >> "$used_list"
        tmp=""

        # Regenerate when the thumbnail is missing or older than the source.
        if [ "$have_magick" -eq 1 ] && { [ ! -f "$out" ] || [ "$f" -nt "$out" ]; }; then
            # Render to a temporary PNG first, so a failed or interrupted
            # convert never leaves a truncated file in the cache.
            tmp="$(mktemp --suffix=.png)"
            if [ "$MODE" = "preserve" ]; then
                # Shrink to fit, keep the aspect ratio (">" = never upscale).
                magick "$f[0]" -thumbnail "${W}x${H}>" "$tmp" >/dev/null 2>&1 || true
            else
                # Fill the box, then crop the overflow from the centre.
                magick "$f[0]" -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" "$tmp" >/dev/null 2>&1 || true
            fi

            # Only publish if magick actually wrote something. On failure the
            # `shown` fallback below points at the original file instead.
            if [ -s "$tmp" ]; then
                if [ "$RADIUS" -gt 0 ] 2>/dev/null; then
                    # Bake a rounded-rectangle mask into the alpha channel, so
                    # the QML side needs no runtime masking.
                    rw="$(magick identify -format '%w' "$tmp[0]" 2>/dev/null || echo "$W")"
                    rh="$(magick identify -format '%h' "$tmp[0]" 2>/dev/null || echo "$H")"
                    magick "$tmp" \
                        \( -size "${rw}x${rh}" xc:none -fill white \
                           -draw "roundrectangle 0,0 $((rw - 1)),$((rh - 1)) ${RADIUS},${RADIUS}" \) \
                        -alpha off -compose CopyOpacity -composite "$out" >/dev/null 2>&1 || cp -f "$tmp" "$out"
                else
                    magick "$tmp" -quality 85 "$out" >/dev/null 2>&1 || cp -f "$tmp" "$out"
                fi
            fi
            rm -f "$tmp"
        fi

        # Use the cached thumbnail when it exists; otherwise fall back to the
        # original image so a wallpaper never disappears from the strip.
        shown="$out"
        [ -f "$shown" ] || shown="$f"

        # Read the real dimensions of the shown file. The picker uses them to
        # preserve each wallpaper's aspect ratio; fall back to the requested
        # box size if identify fails.
        dims=""
        if [ "$have_magick" -eq 1 ]; then
            dims="$(magick identify -format '%w %h' "$shown[0]" 2>/dev/null || true)"
        fi
        # shellcheck disable=SC2086
        set -- $dims
        printf '%s\t%s\t%s\t%s\n' "$f" "$shown" "${1:-$W}" "${2:-$H}"
    done

# Prune cache entries this scan did not produce: removed/renamed wallpapers and
# thumbnails made with old generation options. Only when the source dir exists,
# so a temporarily unavailable folder does not wipe the cache.
if [ -d "$DIR" ]; then
    while IFS= read -r cached; do
        [ -n "$cached" ] || continue
        # Not in this scan's used list -> orphan from an old scan.
        if ! grep -qxF -- "$(basename -- "$cached")" "$used_list"; then
            rm -f -- "$cached"
        fi
    done < <(find "$CACHE" -maxdepth 1 -type f -print 2>/dev/null)
fi
# Temporary bookkeeping file, no longer needed.
rm -f "$used_list"
