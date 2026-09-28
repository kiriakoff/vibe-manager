# syntax=docker/dockerfile:1

# ---------- Stage 1: Build Flutter web frontend ----------
FROM ghcr.io/cirruslabs/flutter:3.32.5 AS frontend-builder

WORKDIR /src
COPY frontend/ ./frontend/
RUN cd frontend \
    && flutter pub get \
    && flutter build web --release

# ---------- Stage 2: Build Rust backend ----------
# Pinned to bookworm so the binary's glibc matches the bookworm runtime image.
FROM rust:1-slim-bookworm AS backend-builder

WORKDIR /build

# Cache dependencies: build once with stub sources
COPY backend/Cargo.toml backend/Cargo.lock* ./backend/
RUN mkdir -p backend/src/bin \
    && echo "fn main() {}" > backend/src/main.rs \
    && echo "" > backend/src/lib.rs \
    && echo "fn main() {}" > backend/src/bin/create-user.rs \
    && cargo build --release --manifest-path backend/Cargo.toml

# Build the real sources
COPY backend ./backend
RUN touch backend/src/main.rs backend/src/lib.rs backend/src/bin/create-user.rs \
    && cargo build --release --manifest-path backend/Cargo.toml

# ---------- Stage 3: Runtime ----------
FROM debian:bookworm-slim
# Keep in sync with the Rust builder stage (bookworm = glibc 2.36).

# - chromium: headless screenshots for app previews
# - docker-ce-cli + docker-compose-plugin: manage app containers
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    fonts-liberation \
    ca-certificates \
    curl \
    gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=backend-builder /build/backend/target/release/vibe-manager /app/vibe-manager
COPY --from=backend-builder /build/backend/target/release/create-user /app/create-user
COPY --from=frontend-builder /src/frontend/build/web /app/static

RUN mkdir -p /data/auth /data/previews /data/compose \
    && touch /data/auth/users.txt

ENV PORT=8000 \
    DATA_ROOT=/data \
    FILEBROWSER_ROOT=/filebrowser \
    FILEBROWSER_HOST=/data/filebrowser/files \
    STATIC_DIR=/app/static \
    RUST_LOG=info,vibe_manager=debug

EXPOSE 8000

CMD ["/app/vibe-manager"]
