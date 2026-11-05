#!/usr/bin/env bash
#
# Usage: open-picker.sh
#
# Toggles the picker: closes a running instance through its IPC handler, or
# starts a new Quickshell process after ensuring the awww daemon is available.

set -uo pipefail

# Resolve the project root from this script's location so `qs -p` works from
# any working directory.
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# A running instance answers IPC with its `close` handler. `qs ipc call`
# returns success even when the target is missing, so verify the target first.
if command -v qs >/dev/null 2>&1 \
    && qs ipc -p "$DIR" show 2>/dev/null | grep -qx "target wallpaperPicker"; then
    qs ipc -p "$DIR" call wallpaperPicker close >/dev/null 2>&1 && exit 0
fi

# Launching needs a working daemon. If it cannot be started, still open the
# picker so the UI can report the error.
if command -v awww >/dev/null 2>&1; then
    bash "$DIR/scripts/ensure-awww-daemon.sh" || true
fi

# No instance answered: replace this shell so no wrapper process remains.
# --no-duplicate closes the gap between the IPC check and this launch.
exec qs -n -p "$DIR"
