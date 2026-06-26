#!/bin/sh
# Разворачивает SOPS-вольты aif-handoff в файлы, которые ждёт compose.
# Запускается на ДЕПЛОЕ (на сервере), где есть age-приватный ключ.
#
# Требует:
#   - sops в PATH
#   - age-приватный ключ доступен sops: либо ~/.config/sops/age/keys.txt,
#     либо переменная SOPS_AGE_KEY_FILE.
#
# Делает:
#   env/aif.env    (SOPS, в git) → env/aif.env.decrypted    (plain, gitignored)
#   env/docker.env (SOPS, в git) → .env                     (plain, gitignored)
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AIF_VAULT="env/aif.env"
DOCKER_VAULT="env/docker.env"
[ -f "$AIF_VAULT" ]    || { echo "Нет вольта $AIF_VAULT" >&2; exit 1; }
[ -f "$DOCKER_VAULT" ] || { echo "Нет вольта $DOCKER_VAULT" >&2; exit 1; }

umask 077

# aif.env.decrypted читает docker-демон (root) и передаёт в контейнер. 0644 —
# чтобы не плодить разночтения с UID внутри образа; сервер доверенный.
sops -d "$AIF_VAULT"    > env/aif.env.decrypted
chmod 0644 env/aif.env.decrypted

# .env читает только compose-CLI (через docker-cli) — оставляем 0600.
sops -d "$DOCKER_VAULT" > .env
chmod 0600 .env

echo "OK: env/aif.env.decrypted + .env"
