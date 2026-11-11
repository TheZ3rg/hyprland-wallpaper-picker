#!/usr/bin/env bash
#
# Shared mpvpaper process management. Source this file; do not execute it.
#
# awww and mpvpaper both draw the desktop, so only one may run at a time. The
# picker replaces any mpvpaper of the current user when it applies a wallpaper,
# including one started outside the picker.

live_uid() {
    printf '%s\n' "${UID:-$(id -u)}"
}

# PIDs of every mpvpaper process of this user, one per line.
live_pids() {
    pgrep -u "$(live_uid)" -x mpvpaper 2>/dev/null || true
}

# Stop mpvpaper and wait for it to exit. SIGKILL is a last resort after the
# graceful signal had a chance to stop the video.
stop_live() {
    local pids i
    pids="$(live_pids)"
    [ -z "$pids" ] && return 0

    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true

    for i in $(seq 1 40); do
        pids="$(live_pids)"
        [ -z "$pids" ] && return 0
        sleep 0.05
    done

    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
    return 0
}
