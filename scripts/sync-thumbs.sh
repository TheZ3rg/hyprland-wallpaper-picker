#!/usr/bin/env bash
#
# Usage: sync-thumbs.sh <wallpaperDirs> <cacheDir> <w> <h> <thumbQuality> \
#   <imageExts> [previewDir] [previewWidth] [previewHeight] [previewQuality] \
#   [videoExts] [posterSeek] [workers]
#
# <wallpaperDirs> is a newline-separated list of directories. Each directory
# is scanned non-recursively. Missing directories are reported, and the
# remaining directories are still scanned.
#
# Generates or reuses cached thumbnails and focused previews, and prints one
# tab-separated manifest row per wallpaper:
#
#     <sourcePath>\t<thumbPath>\t<thumbWidth>\t<thumbHeight>\t<previewPath>\t<kind>
#
# <kind> is image, gif or video. Video posters need ffmpeg.
# <previewPath> is empty only if preview generation failed.
# ImageMagick 7 is required. Thumbnails are keyed by the source path,
# generation options and cache version, and are regenerated when the source is
# newer. Files that cannot be converted are skipped with a diagnostic.
#
# Files are processed in parallel. `workers` is clamped to a sensible default
# when it is 0 or missing.

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
POSTER_SEEK="${12:-1}"
WORKERS="${13:-0}"

# Thumbnails always use a centered cover crop. Kept in the cache key so
# thumbnails generated before preserve mode was removed still match.
MODE="cover"
EXT="jpg"

preview_enabled=0
if [ -n "$PREVIEW_DIR" ] \
    && [[ "$PREVIEW_W" =~ ^[1-9][0-9]*$ ]] \
    && [[ "$PREVIEW_H" =~ ^[1-9][0-9]*$ ]]; then
    preview_enabled=1
fi

if ! [[ "$POSTER_SEEK" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "sync-thumbs.sh: invalid poster seek: $POSTER_SEEK" >&2
    exit 2
fi

if ! [[ "$WORKERS" =~ ^[0-9]+$ ]]; then
    echo "sync-thumbs.sh: invalid worker count: $WORKERS" >&2
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

if [ "$WORKERS" -eq 0 ]; then
    WORKERS="$(nproc 2>/dev/null || echo 4)"
    [ "$WORKERS" -gt 8 ] && WORKERS=8
fi
# A typo should not spawn an unbounded number of ImageMagick processes.
[ "$WORKERS" -gt 32 ] && WORKERS=32

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

# The picker kills this process when it closes mid-scan, so the EXIT trap
# cannot remove its temp directory. Clear those leftovers before starting.
rm -rf -- "$CACHE"/.sync-thumbs.*
if [ -n "$PREVIEW_DIR" ]; then
    rm -rf -- "$PREVIEW_DIR"/.preview.* "$PREVIEW_DIR"/.video-preview.*
fi

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

WORK="$(mktemp -d "$CACHE/.sync-thumbs.XXXXXX")" || {
    echo "sync-thumbs.sh: cannot create a temporary directory in $CACHE" >&2
    exit 1
}
trap 'rm -rf -- "$WORK"' EXIT

list="$WORK/files"
sorted="$WORK/sorted"
rows="$WORK/rows"
failures="$WORK/failures"
mkdir -p -- "$rows"
: > "$failures"

list_files() {
    : > "$list"
    for dir in "${VALID_ROOTS[@]}"; do
        # -H follows a source folder that is a symlink; -xtype also accepts a
        # symlinked wallpaper while ignoring broken links inside the folder.
        if ! find -H "$dir" -maxdepth 1 -xtype f \( "${find_args[@]}" \) \
                -print0 >> "$list"; then
            echo "sync-thumbs.sh: failed to scan $dir" >&2
            return 1
        fi
    done
}

warn() {
    printf '%s\n' "$*" >&2
}

# fail <index> <message>
fail() {
    printf '%s\n' "$2" >&2
    printf 'x\n' >> "$failures"
    : > "$rows/$1.failed"
}

# process_file <path> <index>
#
# Generates the thumbnail and preview for one file and writes the manifest row
# to $rows/<index>. Runs in a background subshell, so it must not touch shell
# variables used by the caller.
process_file() {
    local f="$1" i="$2"
    local ext is_video=0 is_gif=0 kind key key_src out final_tmp
    local thumb_src tw th preview_path poster_frame

    ext="$(lower_ext "$f")"
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
    final_tmp="$WORK/final-$key.$EXT"
    thumb_src="$f"
    tw="$W"
    th="$H"

    if [ ! -f "$out" ] || [ "$f" -nt "$out" ]; then
        rm -f -- "$final_tmp"

        if [ "$is_video" -eq 1 ]; then
            if [ "$HAS_FFMPEG" -ne 1 ]; then
                fail "$i" "sync-thumbs.sh: ffmpeg is required for video wallpapers: $f"
                return 1
            fi
            thumb_src="$WORK/poster-$key.png"
            if ! video_poster "$f" "$thumb_src" "$POSTER_SEEK"; then
                fail "$i" "sync-thumbs.sh: failed to extract a video frame: $f"
                return 1
            fi
        fi

        # Render to a temporary file first so an interrupted convert never
        # leaves a truncated thumbnail in the cache.
        if ! magick "$thumb_src[0]" -auto-orient -resize "${W}x${H}^" \
            -gravity center -extent "${W}x${H}" -quality "$THUMB_QUALITY" \
            "$final_tmp"; then
            fail "$i" "sync-thumbs.sh: failed to generate thumbnail: $f"
            return 1
        fi

        if [ ! -s "$final_tmp" ]; then
            fail "$i" "sync-thumbs.sh: empty thumbnail generated for: $f"
            return 1
        fi

        if ! mv -f -- "$final_tmp" "$out"; then
            fail "$i" "sync-thumbs.sh: failed to store thumbnail for: $f"
            return 1
        fi
    fi

    if [ ! -f "$out" ]; then
        fail "$i" "sync-thumbs.sh: thumbnail is missing: $out"
        return 1
    fi

    # A regenerated video thumbnail is already the poster frame at
    # POSTER_SEEK; reuse it for a still preview instead of decoding twice.
    poster_frame=""
    [ "$is_video" -eq 1 ] && [ "$thumb_src" != "$f" ] && poster_frame="$thumb_src"

    preview_path=""
    if [ "$preview_enabled" -eq 1 ]; then
        if [ "$is_video" -eq 1 ]; then
            if ! preview_path="$(bash "$SCRIPT_DIR/preview-thumb.sh" \
                "$f" "$PREVIEW_DIR" "$PREVIEW_W" "$PREVIEW_H" \
                "$PREVIEW_QUALITY" "$POSTER_SEEK" "$poster_frame")"; then
                preview_path=""
                warn "sync-thumbs.sh: failed to cache preview: $f"
            fi
        elif ! preview_path="$(bash "$SCRIPT_DIR/preview-thumb.sh" \
            "$f" "$PREVIEW_DIR" "$PREVIEW_W" "$PREVIEW_H" \
            "$PREVIEW_QUALITY")"; then
            preview_path=""
            warn "sync-thumbs.sh: failed to cache preview: $f"
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$f" "$out" "$tw" "$th" "$preview_path" "$kind" > "$rows/$i"
}

SKIP_PRUNE=0
[ "$MISSING_DIRS" -gt 0 ] && SKIP_PRUNE=1
SCAN_FAILED=0

if ! list_files; then
    SCAN_FAILED=1
    SKIP_PRUNE=1
fi

if ! sort -z "$list" > "$sorted"; then
    echo "sync-thumbs.sh: failed to sort the file list" >&2
    exit 1
fi

FILES=()
while IFS= read -r -d '' f; do
    FILES+=("$f")
done < "$sorted"

running=0
for i in "${!FILES[@]}"; do
    process_file "${FILES[$i]}" "$i" &
    running=$((running + 1))
    if [ "$running" -ge "$WORKERS" ]; then
        wait -n
        running=$((running - 1))
    fi
done
wait

failed="$(wc -l < "$failures" 2>/dev/null || echo 0)"

# Print the manifest in the sorted order, regardless of worker completion.
# Remember what this scan produced so the cleanup below can remove the rest.
declare -A used_thumbs=()
declare -A used_previews=()
for i in "${!FILES[@]}"; do
    row="$rows/$i"
    if [ -f "$row" ]; then
        row_text="$(< "$row")"
        printf '%s\n' "$row_text"
        thumb_path="$(printf '%s' "$row_text" | cut -f2)"
        preview_path="$(printf '%s' "$row_text" | cut -f5)"
        [ -n "$thumb_path" ] && used_thumbs["${thumb_path##*/}"]=1
        [ -n "$preview_path" ] && used_previews["${preview_path##*/}"]=1
    elif [ -f "$row.failed" ]; then
        continue
    else
        echo "sync-thumbs.sh: no result for: ${FILES[$i]}" >&2
        failed=$((failed + 1))
    fi
done

# Delete cached files this scan did not produce. Only names matching our key
# shape are ours to remove, so a custom cache directory cannot lose unrelated
# files. Skip pruning when a directory is missing or a scan failed, so a
# temporarily unavailable source cannot wipe its cache.
prune_dir() {
    local -n used="$2"
    local dir="$1" cached name
    while IFS= read -r -d '' cached; do
        name="${cached##*/}"
        [[ "$name" =~ ^[0-9a-f]{32}\.jpg$ ]] || continue
        [ -n "${used["$name"]:-}" ] || rm -f -- "$cached"
    done < <(find "$dir" -maxdepth 1 -type f -print0 2>/dev/null)
}

if [ "$SKIP_PRUNE" -eq 0 ]; then
    prune_previews="$preview_enabled"
    preview_real="$(realpath -m -- "$PREVIEW_DIR")"
    cache_real="$(realpath -m -- "$CACHE")"
    if [ "$preview_enabled" -eq 1 ] && [ "$preview_real" = "$cache_real" ]; then
        # Previews and thumbnails share a directory, so prune them together.
        for name in "${!used_previews[@]}"; do
            used_thumbs["$name"]=1
        done
        prune_previews=0
    fi
    prune_dir "$CACHE" used_thumbs
    [ "$prune_previews" -eq 1 ] && prune_dir "$PREVIEW_DIR" used_previews
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
