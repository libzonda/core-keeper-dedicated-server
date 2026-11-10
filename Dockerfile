# syntax=docker/dockerfile:1

ARG APP_VERSION=v0.2.0

# -------------------------------------------------------------
# Stage 1: Build Flutter Web Frontend
# -------------------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:stable AS web-builder
ARG APP_VERSION
WORKDIR /app/web
COPY web/pubspec.yaml ./
RUN flutter pub get
COPY web/ ./
RUN flutter build web --release --no-wasm-dry-run --dart-define=APP_VERSION=${APP_VERSION} && \
    sed -i '/sourceMappingURL=.*\.map/d' build/web/*.js 2>/dev/null || true

# -------------------------------------------------------------
# Stage 2: Build Go Server Manager Daemon
# -------------------------------------------------------------
FROM golang:alpine AS go-builder
ARG APP_VERSION
WORKDIR /app/server
RUN apk add --no-cache git
COPY server/go.mod server/go.sum* ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w -X main.Version=${APP_VERSION}" -o corekeeper-manager .

# -------------------------------------------------------------
# Stage 3: Production Runtime
# -------------------------------------------------------------
FROM ubuntu:22.04

LABEL maintainer="Core Keeper Dedicated Server Community"
LABEL description="Official Core Keeper Dedicated Server container with Steam SDR, Direct Connect, and modern Flutter Web management dashboard."

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Container internal paths
ENV GAME_PATH=/server/game
ENV DATA_PATH=/server/data
ENV WEB_DIR=/server/web
ENV WEB_PORT=8080

# Server default arguments (Official default is Steam SDR)
ENV NETWORK_MODE=sdr
ENV SERVER_NAME="Core Keeper Server"
ENV WORLD_INDEX=0
ENV WORLD_NAME="libzonda's Dedicated Server"
ENV WORLD_SEED=0
ENV WORLD_MODE=0
ENV MAX_PLAYERS=10
ENV PORT=27015
ENV BIND_IP=0.0.0.0
ENV AUTO_START=true
ENV AUTO_UPDATE=true

# Install base dependencies, SteamCMD, and Xvfb for Unity headless support
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    echo steam steam/question select "I AGREE" | debconf-set-selections && \
    echo steam steam/license note '' | debconf-set-selections && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        locales \
        xvfb \
        libxi6 \
        libglu1-mesa \
        libpulse0 \
        libasound2 \
        lib32gcc-s1 \
        steamcmd \
        procps \
        tar \
        gzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Setup symlink for steamcmd
RUN ln -sf /usr/games/steamcmd /usr/bin/steamcmd

# Create steam user and directories
RUN useradd -m -s /bin/bash steam && \
    mkdir -p /server/game /server/data /server/web && \
    chown -R steam:steam /server /home/steam

# Pre-bootstrap steamcmd so first launch does not download client files
RUN su - steam -c "steamcmd +quit" || true

# Copy compiled Flutter Web artifacts
COPY --from=web-builder /app/web/build/web /server/web

# Copy compiled Go Manager binary
COPY --from=go-builder /app/server/corekeeper-manager /usr/local/bin/corekeeper-manager

# Copy entrypoint script
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/corekeeper-manager

WORKDIR /server

# Expose Web Management Port and Direct Connect UDP Game Ports
EXPOSE 8080/tcp
EXPOSE 27015/udp
EXPOSE 27016/udp

# Healthcheck checking Web Manager API
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/api/status || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

