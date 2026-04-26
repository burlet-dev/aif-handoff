#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

AIF_DIR="/home/helm-server/aif-handoff"
DC="docker compose -f docker-compose.production.yml -f docker-compose.override.yml"

echo "==> Pulling latest changes..."
$SSH_CMD "cd ${AIF_DIR} && git pull origin main"

echo "==> Building and restarting containers..."
$SSH_CMD "cd ${AIF_DIR} && ${DC} up -d --build"

echo "==> Cleaning up old images..."
$SSH_CMD "docker image prune -f"

echo "==> Done."
