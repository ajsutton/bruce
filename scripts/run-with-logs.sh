#!/usr/bin/env bash
# Build the macOS app, launch it suspended, attach a PID-filtered log
# stream, then resume it. Logs are written to .agent-tmp/app-logs.txt.
#
# Usage:
#   scripts/run-with-logs.sh [predicate] [launch-args...]
#
# Interactive mode runs until Ctrl-C, then stops the app and log stream.
# Non-interactive mode leaves both processes running and prints cleanup commands.

set -euo pipefail

USER_PREDICATE="${1:-subsystem == \"net.symphonious.bruce\"}"
shift || true
LOG_DIR=".agent-tmp"
LOG_FILE="$LOG_DIR/app-logs.txt"
APP_PATH=".build/Build/Products/Debug/Bruce.app"
APP_BINARY="$APP_PATH/Contents/MacOS/Bruce"
APP_BINARY="$(pwd)/$APP_BINARY"

mkdir -p "$LOG_DIR"

LAUNCH_LOCK="$LOG_DIR/run-mac-with-logs.lock"
if ! mkdir "$LAUNCH_LOCK" 2>/dev/null; then
    echo "Another worktree launch is in progress ($LAUNCH_LOCK)." >&2
    exit 1
fi
trap 'rmdir "$LAUNCH_LOCK"' EXIT

check_existing_worktree() {
    # Match this worktree only; the installed application may remain running.
    while read -r candidate_pid; do
        if lsof -a -p "$candidate_pid" -d txt -Fn 2>/dev/null | grep -Fxq "n$APP_BINARY"; then
            echo "This worktree's Bruce is already running (PID: $candidate_pid)."
            echo "Use that instance or stop that PID before capturing a new launch."
            exit 1
        fi
    done < <(pgrep -x Bruce || true)
}
check_existing_worktree

echo "Building macOS app..."
just build-mac-for-running
check_existing_worktree

# Stop a wrapper before it execs Bruce so the PID-filtered log stream is
# subscribed before the app emits its first log. exec preserves the PID.
echo "Launching app (suspended)..."
rm -f "$LOG_FILE"
sh -c 'kill -STOP $$; exec "$@"' _ "$APP_BINARY" "$@" </dev/null >/dev/null 2>&1 &
APP_PID=$!

on_error() {
    kill -CONT "$APP_PID" 2>/dev/null || true
    kill "$APP_PID" 2>/dev/null || true
    if [ -n "${LOG_PID:-}" ]; then
        kill "$LOG_PID" 2>/dev/null || true
    fi
}
trap on_error ERR

APP_STOPPED=0
for _ in $(seq 1 40); do
    if ps -o state= -p "$APP_PID" 2>/dev/null | grep -q '^T'; then
        APP_STOPPED=1
        break
    fi
    sleep 0.05
done
if [ "$APP_STOPPED" -ne 1 ]; then
    echo "Bruce did not suspend before the log stream was started." >&2
    false
fi

PREDICATE="processIdentifier == $APP_PID AND ($USER_PREDICATE)"
echo "Starting log stream (predicate: $PREDICATE)..."
/usr/bin/log stream \
    --predicate "$PREDICATE" \
    --level debug \
    --style compact \
    >"$LOG_FILE" 2>&1 &
LOG_PID=$!

sleep 0.5
if ! kill -0 "$LOG_PID" 2>/dev/null; then
    echo "The unified log stream failed to start." >&2
    wait "$LOG_PID"
fi
kill -CONT "$APP_PID"
trap - ERR
rmdir "$LAUNCH_LOCK"
trap - EXIT

echo "App running (PID: $APP_PID). Logs streaming to $LOG_FILE"
echo "Log stream PID: $LOG_PID"

if [ -t 0 ]; then
    cleanup() {
        echo ""
        echo "Shutting down..."
        kill "$LOG_PID" 2>/dev/null || true
        kill "$APP_PID" 2>/dev/null || true
        echo "Logs saved to $LOG_FILE"
    }
    trap cleanup EXIT
    trap 'exit 0' INT
    echo "Press Ctrl-C to stop."
    wait "$LOG_PID" 2>/dev/null || true
else
    disown "$APP_PID" 2>/dev/null || true
    disown "$LOG_PID" 2>/dev/null || true
    echo "Non-interactive mode — app and log stream will keep running."
    echo "To stop later:"
    echo "  kill $APP_PID"
    echo "  kill $LOG_PID"
fi
