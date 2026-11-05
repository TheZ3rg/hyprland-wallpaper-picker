#!/usr/bin/env bash
#
# Usage: sync-thumbs.sh <wallpaperDir> <cacheDir> <cover|preserve> <w> <h> <ext,ext,...> [cornerRadius]
#
# Scans wallpaperDir (non-recursive), generates or reuses cached thumbnails,
# and prints one tab-separated manifest row per wallpaper:
#
#     <sourcePath>\t<thumbPath>\t<thumbWidth>\t<thumbHeight>
#
# Thumbnails are keyed by the source path and generation options, and are
# regenerated when the source is newer. The cache is safe to delete.
# ImageMagick is optional; without it the original images are listed instead.

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

# A missing folder produces an empty manifest rather than an error, so the
# picker opens with an empty strip.
if [ ! -d "$DIR" ]; then
    echo "sync-thumbs.sh: wallpaper dir not found: $DIR" >&2
    exit 0
fi

mkdir -p "$CACHE" 2>/dev/null || true

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
    find_args+=( -iname "*.jpg" )
fi

have_magick=0
command -v magick >/dev/null 2>&1 && have_magick=1

# Rounded corners need an alpha channel, so those thumbnails must be PNG.
if [ "$RADIUS" -gt 0 ] 2>/dev/null; then
    EXT="png"
else
    EXT="jpg"
fi

# Every cache file produced by this scan is recorded here. Anything else in
# the cache is an orphan from a removed wallpaper or old options and is pruned
# at the end.
used_list="$(mktemp)"
: > "$used_list"

# sort -z keeps the manifest order stable, so the strip does not reshuffle
# when files are added or removed.
find "$DIR" -maxdepth 1 -type f \( "${find_args[@]}" \) -print0 2>/dev/null |
    sort -z |
    while IFS= read -r -d '' f; do
        # Include the generation options in the key so changed settings do not
        # reuse stale thumbnails.
        key="$(printf '%s' "$f|$MODE|${W}x${H}|r${RADIUS}" | md5sum | cut -d' ' -f1)"
        out="$CACHE/$key.$EXT"
        printf '%s\n' "$key.$EXT" >> "$used_list"
        tmp=""

        if [ "$have_magick" -eq 1 ] && { [ ! -f "$out" ] || [ "$f" -nt "$out" ]; }; then
            # Render to a temporary file first so an interrupted convert never
            # leaves a truncated thumbnail in the cache.
            tmp="$(mktemp --suffix=.png)"
            if [ "$MODE" = "preserve" ]; then
                # ">" prevents upscaling small images.
                magick "$f[0]" -thumbnail "${W}x${H}>" "$tmp" >/dev/null 2>&1 || true
            else
                magick "$f[0]" -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" "$tmp" >/dev/null 2>&1 || true
            fi

            if [ -s "$tmp" ]; then
                if [ "$RADIUS" -gt 0 ] 2>/dev/null; then
                    # Bake the rounded corners into the alpha channel; QML then
                    # needs no runtime mask.
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

        # Fall back to the original file so a wallpaper never disappears from
        # the strip because thumbnail generation failed.
        shown="$out"
        [ -f "$shown" ] || shown="$f"

        # Real dimensions of the shown file, used by the strip to preserve its
        # aspect ratio.
        dims=""
        if [ "$have_magick" -eq 1 ]; then
            dims="$(magick identify -format '%w %h' "$shown[0]" 2>/dev/null || true)"
        fi
        # shellcheck disable=SC2086
        set -- $dims
        printf '%s\t%s\t%s\t%s\n' "$f" "$shown" "${1:-$W}" "${2:-$H}"
    done

# Prune cache entries this scan did not produce. Skip pruning when the source
# folder is unavailable so a temporarily unmounted disk cannot wipe the cache.
if [ -d "$DIR" ]; then
    while IFS= read -r cached; do
        [ -n "$cached" ] || continue
        if ! grep -qxF -- "$(basename -- "$cached")" "$used_list"; then
            rm -f -- "$cached"
        fi
    done < <(find "$CACHE" -maxdepth 1 -type f -print 2>/dev/null)
fi
rm -f "$used_list"
