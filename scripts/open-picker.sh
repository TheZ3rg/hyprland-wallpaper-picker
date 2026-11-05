#!/usr/bin/env bash
#
# Usage: open-picker.sh
#
# Toggles the picker: closes a running instance through its IPC handler, or
# starts a new Quickshell process with the awww daemon ensured.

set -uo pipefail

# Resolve the project root from this script's location so `qs -p` works from
# any working directory.
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# The daemon normally autostarts with the session. Start it here as a safety
# net, and poll so the first apply does not race its socket.
if command -v awww-daemon >/dev/null 2>&1 && ! pgrep -x awww-daemon >/dev/null 2>&1; then
    setsid awww-daemon >/dev/null 2>&1 &
    for _ in $(seq 1 50); do
        pgrep -x awww-daemon >/dev/null 2>&1 && break
        sleep 0.05
    done
fi

# A running instance answers IPC with its `close` handler.
if command -v qs >/dev/null 2>&1 && qs ipc -p "$DIR" call wallpaperPicker close >/dev/null 2>&1; then
    exit 0
fi

# No instance answered: replace this shell so no wrapper process remains.
exec qs -p "$DIR"
