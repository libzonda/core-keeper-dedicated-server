# Core Keeper Dedicated Server with Web Management Dashboard

[![GitHub Repository](https://img.shields.io/badge/GitHub-libzonda%2Fcore--keeper--dedicated--server-blue?logo=github)](https://github.com/libzonda/core-keeper-dedicated-server)
[![Docker Pulls](https://img.shields.io/docker/pulls/libzonda/core-keeper-dedicated-server)](https://hub.docker.com/r/libzonda/core-keeper-dedicated-server)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/libzonda/core-keeper-dedicated-server/blob/main/LICENSE)

An all-in-one containerized **Core Keeper Dedicated Server** solution featuring a modern responsive **Web Management Dashboard**, **multi-instance management**, **Steam SDR & Direct Connect modes**, **built-in network proxy**, **in-game admin management**, **world save import/export**, and **full Mod.io / Steam Workshop mod integration**.

---

## ✨ Features

- 🖥️ **Full Visual Web Management**: Modern Apple HIG & Material 3 style dashboard with responsive layouts for desktop, tablet, and mobile browsers.
- 🏢 **Multi-Instance Management**: Run and manage multiple isolated Core Keeper server instances simultaneously from a single container.
- 🌐 **Dual Networking Modes**:
  - **Steam SDR (Steam Datagram Relay)**: Connect via official Steam relay using a Game ID — **no public IP, router port forwarding, or NAT configuration required**.
  - **Direct Connect (IP + Port)**: Low-latency direct UDP connection with customizable port allocation per instance.
- 🛡️ **Network Proxy Support**: Built-in HTTP / SOCKS5 proxy client integration (supporting Clash, Mihomo, v2ray) to ensure reliable SteamCMD updates and Mod.io downloads in restricted network environments.
- 👑 **In-Game Admin Management**: Add or remove game admins dynamically using Steam64 IDs without restarting the server.
- 💾 **World Saves Management**: Create, delete, switch, download/export, and upload/import world save files (`.json`) with ease.
- 🧩 **Integrated Mod Manager**: Search, install, update, and manage mods directly from **Steam Workshop** and **Mod.io** with one click, or upload local `.zip` mod packages.

---

## 🚀 Quick Start (Docker Compose)

Create a `docker-compose.yml` file on your host machine:

```yaml
services:
  core-keeper-server:
    image: libzonda/core-keeper-dedicated-server:latest
    # Or use GitHub Container Registry:
    # image: ghcr.io/libzonda/core-keeper-dedicated-server:latest
    container_name: core-keeper-server
    restart: unless-stopped
    ports:
      # Web Management Dashboard
      - "8080:8080"
      # Batch UDP Port Range for Multi-Instance Direct Connect
      # (If using Steam SDR mode exclusively, no UDP port forwarding is needed)
      - "27015-27065:27015-27065/udp"
    environment:
      # Web Dashboard Port (Default: 8080)
      - WEB_PORT=8080
    volumes:
      # Persistent storage (all instances, configs, saves, and shared mods)
      - ./server-data:/server/data
      # Game server binaries (auto-downloaded & maintained via SteamCMD)
      - ./server-game:/server/game
```

### Start the Server

```bash
docker compose up -d
```

### Access Web Dashboard

Open **`http://<your-server-ip>:8080`** in your browser.

> **Tip:** You do not need to configure any game instance parameters in `docker-compose.yml`. All settings (World Name, Seed, Difficulty, Max Players, Network Mode, Game Port, Admins, and Mods) are created and managed visually in the Web Dashboard.

---

## 📂 Volume Mounts

| Host Path | Container Path | Description |
|---|---|---|
| `./server-data` | `/server/data` | Stores instance metadata, world save files, admin configs, proxy settings, and installed mods. |
| `./server-game` | `/server/game` | Core Keeper Dedicated Server binaries automatically downloaded and updated by SteamCMD. |

---

## 🌐 Networking Modes

### 1. Steam SDR Mode (Recommended for Private Games)
- **Zero port forwarding needed**: Works behind NAT, CGNAT, or mobile networks.
- Simply copy the **Game ID** generated on the Web Dashboard and share it with your friends. Players join by entering the Game ID in the Core Keeper client.

### 2. Direct Connect Mode (Recommended for Public / Community Servers)
- Requires exposing container UDP ports (e.g. `27015:27015/udp`).
- Players join directly using `Your-Server-IP:Port`.

---

## 🔗 Links & Documentation

- **GitHub Repository**: [https://github.com/libzonda/core-keeper-dedicated-server](https://github.com/libzonda/core-keeper-dedicated-server)
- **Chinese Documentation (中文文档)**: [README_zh-CN.md](https://github.com/libzonda/core-keeper-dedicated-server/blob/main/README_zh-CN.md)
- **Issue Tracker**: [https://github.com/libzonda/core-keeper-dedicated-server/issues](https://github.com/libzonda/core-keeper-dedicated-server/issues)

