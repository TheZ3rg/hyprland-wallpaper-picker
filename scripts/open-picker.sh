#!/usr/bin/env bash
#
# Toggle the wallpaper picker:
#   - if it is already running, ask it to close (via IPC)
#   - otherwise make sure the awww daemon is up and launch a Quickshell instance
#
# This is what the SUPER + W keybind calls.

set -uo pipefail

# Project root (parent of scripts/), so `qs -p` finds shell.qml no matter
# where this script is called from.
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# awww-daemon normally autostarts with the session (see hyprland.lua); this is
# just a safety net for the first run, or if the daemon ever dies.
# `setsid` detaches it from this script; poll briefly so the first apply does
# not race the daemon's socket.
if command -v awww-daemon >/dev/null 2>&1 && ! pgrep -x awww-daemon >/dev/null 2>&1; then
    setsid awww-daemon >/dev/null 2>&1 &
    for _ in $(seq 1 50); do
        pgrep -x awww-daemon >/dev/null 2>&1 && break
        sleep 0.05
    done
fi

# Toggle: if an instance is already running for this project, its IPC target
# (`wallpaperPicker`, see WallpaperPicker.qml) handles `close` and we are done.
if command -v qs >/dev/null 2>&1 && qs ipc -p "$DIR" call wallpaperPicker close >/dev/null 2>&1; then
    exit 0
fi

# No running instance (or IPC unavailable): launch one. `exec` replaces this
# shell with `qs`, so there is no wrapper process left behind.
exec qs -p "$DIR"
