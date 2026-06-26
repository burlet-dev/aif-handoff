#!/bin/bash
# Одноразовая миграция на сервере: переименование папки ~/aif/repo → ~/aif/aif-handoff
# + перенос docker volumes repo_* → aif-handoff_* (чтобы не потерять gh/claude/codex логины).
#
# Запускать на сервере один раз, после того как новый compose с `name: aif-handoff`
# уже задеплоен (но до того как первый запуск под новым именем создаст пустые тома).
#
# После миграции CI и Justfile уже указывают на ~/aif/aif-handoff — никаких ручных правок не нужно.
set -e

OLD_DIR="$HOME/aif/repo"
NEW_DIR="$HOME/aif/aif-handoff"
OLD_PROJECT="repo"
NEW_PROJECT="aif-handoff"
VOLUMES=("claude-auth" "codex-auth" "db-data")

echo "==> Останавливаем старый стек (project=$OLD_PROJECT)"
if [ -d "$OLD_DIR" ]; then
    cd "$OLD_DIR"
    docker compose -f docker-compose.yml -f compose.production.yml down || true
fi

echo "==> Переименовываем папку $OLD_DIR → $NEW_DIR"
if [ -d "$NEW_DIR" ] && [ ! -d "$OLD_DIR" ]; then
    echo "   уже переименовано — пропускаю"
elif [ -d "$OLD_DIR" ]; then
    mv "$OLD_DIR" "$NEW_DIR"
fi

echo "==> Мигрируем docker volumes ${OLD_PROJECT}_* → ${NEW_PROJECT}_*"
for vol in "${VOLUMES[@]}"; do
    OLD_VOL="${OLD_PROJECT}_${vol}"
    NEW_VOL="${NEW_PROJECT}_${vol}"

    if ! docker volume inspect "$OLD_VOL" >/dev/null 2>&1; then
        echo "   $OLD_VOL не существует — пропускаю"
        continue
    fi
    if docker volume inspect "$NEW_VOL" >/dev/null 2>&1; then
        echo "   $NEW_VOL уже существует — пропускаю (ручная проверка нужна, если данные важны)"
        continue
    fi

    echo "   $OLD_VOL → $NEW_VOL"
    docker volume create "$NEW_VOL" >/dev/null
    # Копируем содержимое через временный контейнер alpine.
    docker run --rm \
        -v "$OLD_VOL":/from \
        -v "$NEW_VOL":/to \
        alpine sh -c "cd /from && cp -av . /to/ >/dev/null"
done

echo "==> Поднимаем новый стек (project=$NEW_PROJECT)"
cd "$NEW_DIR"
./scripts/sops-decrypt.sh
docker compose -f docker-compose.yml -f compose.production.yml pull
docker compose -f docker-compose.yml -f compose.production.yml up -d --remove-orphans

echo ""
echo "==> Готово. Проверь:"
echo "   docker compose -f docker-compose.yml -f compose.production.yml ps"
echo ""
echo "После проверки можно удалить старые volumes:"
for vol in "${VOLUMES[@]}"; do
    echo "   docker volume rm ${OLD_PROJECT}_${vol}"
done
