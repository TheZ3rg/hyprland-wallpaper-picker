#!/usr/bin/env bash
#
# Usage: sync-thumbs.sh <wallpaperDirs> <cacheDir> <w> <h> <thumbQuality> \
#   <imageExts> [previewDir] [previewWidth] [previewHeight] [previewQuality] \
#   [videoExts] [animatedPreviews] [animWidth] [animHeight] \
#   [animDurationMs] [animFps] [animQuality] [posterSeek]
#
# <wallpaperDirs> is a newline-separated list of directories. Each directory
# is scanned non-recursively. Missing directories are reported, and the
# remaining directories are still scanned.
#
# Generates or reuses cached thumbnails and focused previews, and prints one
# tab-separated manifest row per wallpaper:
#
#     <sourcePath>\t<thumbPath>\t<thumbWidth>\t<thumbHeight>\t<previewPath>\t<kind>\t<animated>
#
# <kind> is image, gif or video. <animated> is 1 when <previewPath> is an
# animated WebP clip. Video posters and animated previews need ffmpeg.
# <previewPath> is empty only if preview generation failed.
# ImageMagick 7 is required. Thumbnails are keyed by the source path,
# generation options and cache version, and are regenerated when the source is
# newer. Files that cannot be converted are skipped with a diagnostic.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/video-lib.sh"

# Bump this when image thumbnail generation changes so old cache files are
# not reused. Video thumbnails add the poster seek to their key instead.
CACHE_VERSION=1

DIRS="${1:-}"
CACHE="${2:-}"
W="${3:-420}"
H="${4:-640}"
THUMB_QUALITY="${5:-85}"
EXTS="${6:-jpg,jpeg,png,webp}"
PREVIEW_DIR="${7:-}"
PREVIEW_W="${8:-}"
PREVIEW_H="${9:-}"
PREVIEW_QUALITY="${10:-88}"
VIDEO_EXTS="${11:-}"
ANIMATED_PREVIEWS="${12:-0}"
ANIM_W="${13:-}"
ANIM_H="${14:-}"
ANIM_DURATION_MS="${15:-}"
ANIM_FPS="${16:-}"
ANIM_QUALITY="${17:-}"
POSTER_SEEK="${18:-1}"

# Thumbnails always use a centered cover crop. Kept in the cache key so
# thumbnails generated before preserve mode was removed still match.
MODE="cover"

preview_enabled=0
if [ -n "$PREVIEW_DIR" ] \
    && [[ "$PREVIEW_W" =~ ^[1-9][0-9]*$ ]] \
    && [[ "$PREVIEW_H" =~ ^[1-9][0-9]*$ ]]; then
    preview_enabled=1
fi

animated_enabled=$preview_enabled
if [ "$ANIMATED_PREVIEWS" = "1" ]; then
    if ! [[ "$ANIM_W" =~ ^[1-9][0-9]*$ ]] \
        || ! [[ "$ANIM_H" =~ ^[1-9][0-9]*$ ]] \
        || ! [[ "$ANIM_DURATION_MS" =~ ^[1-9][0-9]*$ ]] \
        || ! [[ "$ANIM_FPS" =~ ^[1-9][0-9]*$ ]] \
        || ! [[ "$ANIM_QUALITY" =~ ^[1-9][0-9]?$|^100$ ]]; then
        echo "sync-thumbs.sh: invalid animated preview settings" >&2
        exit 2
    fi
else
    animated_enabled=0
fi

if ! [[ "$POSTER_SEEK" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "sync-thumbs.sh: invalid poster seek: $POSTER_SEEK" >&2
    exit 2
fi

if [ -z "$DIRS" ] || [ -z "$CACHE" ]; then
    echo "sync-thumbs.sh: missing arguments" >&2
    exit 2
fi

if ! [[ "$W" =~ ^[1-9][0-9]*$ ]] || ! [[ "$H" =~ ^[1-9][0-9]*$ ]]; then
    echo "sync-thumbs.sh: thumbnail size must be positive: ${W}x${H}" >&2
    exit 2
fi

if ! [[ "$THUMB_QUALITY" =~ ^[1-9][0-9]?$|^100$ ]]; then
    echo "sync-thumbs.sh: invalid thumbnail quality: $THUMB_QUALITY" >&2
    exit 2
fi

if ! [[ "$PREVIEW_QUALITY" =~ ^[1-9][0-9]?$|^100$ ]]; then
    echo "sync-thumbs.sh: invalid preview quality: $PREVIEW_QUALITY" >&2
    exit 2
fi

ROOTS=()
declare -A seen_roots=()
while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    [ -n "${seen_roots["$dir"]:-}" ] && continue
    seen_roots["$dir"]=1
    ROOTS+=("$dir")
done <<< "$DIRS"

if [ "${#ROOTS[@]}" -eq 0 ]; then
    echo "sync-thumbs.sh: no wallpaper directories configured" >&2
    exit 2
fi

MISSING_DIRS=0
VALID_ROOTS=()
for dir in "${ROOTS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "sync-thumbs.sh: wallpaper dir not found: $dir" >&2
        MISSING_DIRS=$((MISSING_DIRS + 1))
        continue
    fi
    VALID_ROOTS+=("$dir")
done

if [ "${#VALID_ROOTS[@]}" -eq 0 ]; then
    echo "sync-thumbs.sh: no readable wallpaper directories" >&2
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

# Build the find expression from both the still and video extension lists:
# \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.mp4" ... \).
find_args=()
declare -A seen_exts=()
for ext_list in "$EXTS" "$VIDEO_EXTS"; do
    IFS=',' read -ra exts <<< "$ext_list"
    for e in "${exts[@]}"; do
        [ -z "$e" ] && continue
        e="${e,,}"
        [ -n "${seen_exts["$e"]:-}" ] && continue
        seen_exts["$e"]=1
        if [ "${#find_args[@]}" -gt 0 ]; then find_args+=( -o ); fi
        find_args+=( -iname "*.${e}" )
    done
done
if [ "${#find_args[@]}" -eq 0 ]; then
    echo "sync-thumbs.sh: no file extensions configured" >&2
    exit 2
fi

HAS_FFMPEG=0
command -v ffmpeg >/dev/null 2>&1 && HAS_FFMPEG=1

# A build without the animation encoder would make every clip fail; fall back
# to static focused crops once instead of retrying per wallpaper.
if [ "$animated_enabled" -eq 1 ] && [ "$HAS_FFMPEG" -eq 1 ]; then
    if ! ffmpeg -hide_banner -encoders 2>/dev/null \
            | grep 'libwebp_anim' >/dev/null; then
        echo "sync-thumbs.sh: ffmpeg has no WebP animation encoder; using static previews" >&2
        animated_enabled=0
    fi
fi

EXT="jpg"

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
SKIP_PRUNE=0
[ "$MISSING_DIRS" -gt 0 ] && SKIP_PRUNE=1
SCAN_FAILED=0
: > "$list"
for dir in "${VALID_ROOTS[@]}"; do
    if ! find "$dir" -maxdepth 1 -type f \( "${find_args[@]}" \) \
            -print0 >> "$list"; then
        echo "sync-thumbs.sh: failed to scan $dir" >&2
        SCAN_FAILED=1
        SKIP_PRUNE=1
    fi
done
if ! sort -z "$list" > "$sorted"; then
    echo "sync-thumbs.sh: failed to sort the file list" >&2
    exit 1
fi

failed=0

while IFS= read -r -d '' f; do
    ext="$(lower_ext "$f")"
    is_video=0
    is_gif=0
    if [ -n "$VIDEO_EXTS" ] && ext_in_list "$ext" "$VIDEO_EXTS"; then
        is_video=1
    elif [ "$ext" = "gif" ]; then
        is_gif=1
    fi

    if [ "$is_video" -eq 1 ]; then
        kind="video"
    elif [ "$is_gif" -eq 1 ]; then
        kind="gif"
    else
        kind="image"
    fi

    # Include the generation options in the key so changed settings do not
    # reuse stale thumbnails. The poster frame is part of a video's identity.
    key_src="$f"
    [ "$is_video" -eq 1 ] && key_src="$f|seek$POSTER_SEEK"
    key="$(printf '%s' "v${CACHE_VERSION}|$key_src|$MODE|${W}x${H}|q${THUMB_QUALITY}" | md5sum)"
    key="${key%% *}"
    out="$CACHE/$key.$EXT"
    final_tmp="$WORK/final.$EXT"
    thumb_src="$f"
    tw="$W"
    th="$H"

    if [ ! -f "$out" ] || [ "$f" -nt "$out" ]; then
        rm -f -- "$final_tmp"

        if [ "$is_video" -eq 1 ]; then
            if [ "$HAS_FFMPEG" -ne 1 ]; then
                echo "sync-thumbs.sh: ffmpeg is required for video wallpapers: $f" >&2
                failed=$((failed + 1))
                continue
            fi
            thumb_src="$WORK/poster-$key.png"
            if ! video_poster "$f" "$thumb_src" "$POSTER_SEEK"; then
                echo "sync-thumbs.sh: failed to extract a video frame: $f" >&2
                failed=$((failed + 1))
                continue
            fi
        fi

        # Render to a temporary file first so an interrupted convert never
        # leaves a truncated thumbnail in the cache.
        if ! magick "$thumb_src[0]" -auto-orient -resize "${W}x${H}^" \
            -gravity center -extent "${W}x${H}" -quality "$THUMB_QUALITY" \
            "$final_tmp"; then
            echo "sync-thumbs.sh: failed to generate thumbnail: $f" >&2
            failed=$((failed + 1))
            continue
        fi

        if [ ! -s "$final_tmp" ]; then
            echo "sync-thumbs.sh: empty thumbnail generated for: $f" >&2
            failed=$((failed + 1))
            continue
        fi

        if ! mv -f -- "$final_tmp" "$out"; then
            echo "sync-thumbs.sh: failed to store thumbnail for: $f" >&2
            failed=$((failed + 1))
            continue
        fi
    fi

    if [ ! -f "$out" ]; then
        echo "sync-thumbs.sh: thumbnail is missing: $out" >&2
        failed=$((failed + 1))
        continue
    fi

    # A regenerated video thumbnail is already the poster frame at
    # POSTER_SEEK; reuse it for a still preview instead of decoding twice.
    poster_frame=""
    [ "$is_video" -eq 1 ] && [ "$thumb_src" != "$f" ] && poster_frame="$thumb_src"

    preview_path=""
    preview_animated=0
    if [ "$preview_enabled" -eq 1 ]; then
        if [ "$animated_enabled" -eq 1 ] && [ "$HAS_FFMPEG" -eq 1 ] \
                && { [ "$is_video" -eq 1 ] || [ "$is_gif" -eq 1 ]; }; then
            anim_start="$POSTER_SEEK"
            [ "$is_gif" -eq 1 ] && anim_start="0"
            if preview_path="$(bash "$SCRIPT_DIR/video-preview.sh" animated \
                "$f" "$PREVIEW_DIR" "$ANIM_W" "$ANIM_H" \
                "$ANIM_DURATION_MS" "$ANIM_FPS" "$ANIM_QUALITY" "$anim_start")" \
                    && [ -n "$preview_path" ]; then
                preview_animated=1
            else
                # Fall back to a still crop below.
                preview_path=""
            fi
        fi

        if [ -z "$preview_path" ]; then
            if [ "$is_video" -eq 1 ]; then
                if ! preview_path="$(bash "$SCRIPT_DIR/video-preview.sh" still \
                    "$f" "$PREVIEW_DIR" "$PREVIEW_W" "$PREVIEW_H" \
                    "$POSTER_SEEK" "$PREVIEW_QUALITY" "$poster_frame")"; then
                    preview_path=""
                    echo "sync-thumbs.sh: failed to cache preview: $f" >&2
                fi
            else
                if ! preview_path="$(bash "$SCRIPT_DIR/preview-thumb.sh" \
                    "$f" "$PREVIEW_DIR" "$PREVIEW_W" "$PREVIEW_H" \
                    "$PREVIEW_QUALITY")"; then
                    preview_path=""
                    echo "sync-thumbs.sh: failed to cache preview: $f" >&2
                fi
            fi
        fi
    fi

    used_names["$key.$EXT"]=1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$f" "$out" "$tw" "$th" "$preview_path" "$kind" "$preview_animated"
done < "$sorted"


# Prune cache entries this scan did not produce. Skip pruning when a directory
# is missing or a scan failed, so a temporarily unavailable source cannot wipe
# its cached thumbnails.
if [ "$SKIP_PRUNE" -eq 0 ]; then
    while IFS= read -r -d '' cached; do
        name="${cached##*/}"
        if [ -z "${used_names["$name"]:-}" ]; then
            rm -f -- "$cached"
        fi
    done < <(find "$CACHE" -maxdepth 1 -type f -print0 2>/dev/null)
fi

if [ "$MISSING_DIRS" -gt 0 ]; then
    printf 'sync-thumbs.sh: %d wallpaper dir(s) not found\n' "$MISSING_DIRS" >&2
    exit 1
fi

if [ "$SCAN_FAILED" -eq 1 ]; then
    echo "sync-thumbs.sh: one or more wallpaper dirs could not be scanned" >&2
    exit 1
fi

if [ "$failed" -gt 0 ]; then
    printf 'sync-thumbs.sh: %d file(s) could not be processed\n' "$failed" >&2
    exit 1
fi
