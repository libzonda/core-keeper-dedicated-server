#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Start Go daemon in background
"$DIR/corekeeper-manager" &
DAEMON_PID=$!

# Start Flutter Desktop app
"$DIR/CoreKeeperManager" "$@"

# Cleanup background daemon when app closes
kill "$DAEMON_PID" 2>/dev/null || true
