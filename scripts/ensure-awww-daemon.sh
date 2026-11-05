#!/usr/bin/env bash
#
# Usage: ensure-awww-daemon.sh
#
# Ensures awww-daemon is running and is answering on its socket. awww can fail
# until the daemon has created that socket, so checking for the process alone
# is not enough. Exits non-zero with a diagnostic when the daemon cannot be
# reached.

set -euo pipefail

command -v awww >/dev/null 2>&1 || {
    echo "awww not found" >&2
    exit 1
}

# Fast path: the daemon is already running and responsive.
if awww query >/dev/null 2>&1; then
    exit 0
fi

# Start the daemon only when this user does not have one. Another user's
# daemon cannot serve our Wayland socket.
if ! pgrep -u "$UID" -x awww-daemon >/dev/null 2>&1; then
    command -v awww-daemon >/dev/null 2>&1 || {
        echo "awww-daemon not found" >&2
        exit 1
    }
    setsid awww-daemon >/dev/null 2>&1 &
fi

# The process may exist before its socket is ready. Poll the socket through
# awww itself instead of checking the process again.
for _ in $(seq 1 100); do
    if awww query >/dev/null 2>&1; then
        exit 0
    fi
    sleep 0.05
done

echo "awww-daemon did not become ready" >&2
exit 1
