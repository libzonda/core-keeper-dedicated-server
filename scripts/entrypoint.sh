#!/usr/bin/env bash
set -e

echo "=========================================================="
echo "    Core Keeper Dedicated Server & Web Manager Container   "
echo "=========================================================="

GAME_PATH="${GAME_PATH:-/server/game}"
DATA_PATH="${DATA_PATH:-/server/data}"
WEB_DIR="${WEB_DIR:-/server/web}"
WEB_PORT="${WEB_PORT:-8080}"
NETWORK_MODE="${NETWORK_MODE:-sdr}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
AUTO_START="${AUTO_START:-true}"

export GAME_PATH DATA_PATH WEB_DIR WEB_PORT NETWORK_MODE AUTO_UPDATE AUTO_START

# Ensure system directories and permissions
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

mkdir -p "$GAME_PATH" "$DATA_PATH" "$DATA_PATH/worlds"
mkdir -p "$GAME_PATH/CoreKeeperServer_Data/StreamingAssets/Mods"
mkdir -p /home/steam/.steam/sdk64

# Fix permissions for mounted volumes
if [ "$(id -u)" = "0" ]; then
    chown -R steam:steam "$DATA_PATH" "$GAME_PATH" /home/steam 2>/dev/null || true
fi

# Ensure Steamworks SDK appid and steamclient.so are linked
echo "1963720" > "$GAME_PATH/steam_appid.txt"
if [ -f "$GAME_PATH/linux64/steamclient.so" ]; then
    ln -sf "$GAME_PATH/linux64/steamclient.so" /home/steam/.steam/sdk64/steamclient.so
    ln -sf "$GAME_PATH/linux64/steamclient.so" "$GAME_PATH/steamclient.so"
fi

# Start Xvfb virtual frame buffer
echo "[Entrypoint] Initializing virtual display (Xvfb :99)..."
rm -f /tmp/.X99-lock
Xvfb :99 -screen 0 640x480x16 -nolisten tcp &
XVFB_PID=$!
export DISPLAY=:99

cleanup() {
    echo "[Entrypoint] Stopping container services..."
    if [ -n "$MANAGER_PID" ]; then
        kill -TERM "$MANAGER_PID" 2>/dev/null || true
        wait "$MANAGER_PID" 2>/dev/null || true
    fi
    if [ -n "$XVFB_PID" ]; then
        kill "$XVFB_PID" 2>/dev/null || true
    fi
    echo "[Entrypoint] Shutdown complete."
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "[Entrypoint] Launching Core Keeper Web Manager daemon on port $WEB_PORT..."
echo "[Entrypoint] Default Network Mode: $NETWORK_MODE (Steam SDR)"
echo "[Entrypoint] Web Panel: http://0.0.0.0:$WEB_PORT"

# Run manager as steam user if running as root
if [ "$(id -u)" = "0" ]; then
    runuser -u steam -m -- env HOME=/home/steam USER=steam DISPLAY=:99 /usr/local/bin/corekeeper-manager \
        --server-dir="$GAME_PATH" \
        --data-dir="$DATA_PATH" \
        --web-dir="$WEB_DIR" \
        --port="$WEB_PORT" &
    MANAGER_PID=$!
else
    env HOME=/home/steam USER=steam DISPLAY=:99 /usr/local/bin/corekeeper-manager \
        --server-dir="$GAME_PATH" \
        --data-dir="$DATA_PATH" \
        --web-dir="$WEB_DIR" \
        --port="$WEB_PORT" &
    MANAGER_PID=$!
fi

wait "$MANAGER_PID"
