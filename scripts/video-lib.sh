#!/usr/bin/env bash
#
# Shared video helpers. Source this file; do not execute it.

# Bump this when the preview output changes so cached clips are not reused.
VIDEO_PREVIEW_VERSION=1

# Lower-cased extension of a path, without the dot.
lower_ext() {
    local ext="${1##*.}"
    printf '%s' "${ext,,}"
}

# ext_in_list <extension> <comma,separated,list>
ext_in_list() {
    local ext="$1" list="$2" item
    [ -n "$ext" ] || return 1
    IFS=',' read -ra _ext_items <<< "$list"
    for item in "${_ext_items[@]}"; do
        [ -n "$item" ] || continue
        [ "${item,,}" = "$ext" ] && return 0
    done
    return 1
}

# video_poster <source> <output> <seekSeconds>
#
# Extracts one frame to <output>. Fast seeking may fail near the end of a very
# short video, so it retries from the first frame.
video_poster() {
    local src="$1" out="$2" seek="$3"

    rm -f -- "$out"
    if ffmpeg -nostdin -hide_banner -loglevel error \
            -ss "$seek" -i "$src" -frames:v 1 -an -f image2 "$out" -y \
            >/dev/null 2>&1 && [ -s "$out" ]; then
        return 0
    fi

    rm -f -- "$out"
    if [ "$seek" != "0" ] \
            && ffmpeg -nostdin -hide_banner -loglevel error \
                -i "$src" -frames:v 1 -an -f image2 "$out" -y \
                >/dev/null 2>&1 && [ -s "$out" ]; then
        return 0
    fi

    rm -f -- "$out"
    return 1
}
