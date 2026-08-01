#!/bin/bash
set -euo pipefail

# Конфігурація
REPO_URL="https://github.com/artcc/freelingo.git"
CLONE_DIR="/tmp/freelingo-build"
UK_JSON_PATH="$(pwd)/tmp/uk.json"
IMAGE_TAG="ttl.sh/freelingo-frontend-uk-max-multiarch:1w"

echo "==> Очищення попередніх збірок..."
rm -rf "$CLONE_DIR"

echo "==> Клонування офіційного репозиторію FreeLingo..."
git clone "$REPO_URL" "$CLONE_DIR"

echo "==> Ін'єкція українського файлу перекладу..."
if [ ! -f "$UK_JSON_PATH" ]; then
    echo "Помилка: Файл $UK_JSON_PATH не знайдено!"
    exit 1
fi
cp "$UK_JSON_PATH" "$CLONE_DIR/messages/uk.json"

echo "==> Оновлення конфігів локалізації..."
# Додаємо 'uk' у список SUPPORTED_LOCALES
sed -i "/'ru',/a \ \ 'uk'," "$CLONE_DIR/frontend/src/lib/locales.ts"

# Додаємо 'uk' у клієнтський скрипт детекції мови браузера в layout.tsx
sed -i "s/'ru'/'ru','uk'/g" "$CLONE_DIR/frontend/src/app/layout.tsx"

echo "==> Збірка та пуш мультиархітектурного образу ($IMAGE_TAG)..."
cd "$CLONE_DIR"

# Ініціалізуємо buildx, якщо він ще не створений
docker buildx create --use || true

# Запускаємо мультиарх-збірку (amd64 для домашніх нод, arm64 для Oracle Cloud)
docker buildx build \
  -f frontend/Dockerfile \
  --platform linux/amd64,linux/arm64 \
  -t "$IMAGE_TAG" \
  --push .

echo ""
echo "=========================================================="
echo "✅ Збірка завершена!"
echo "Тепер вам потрібно:"
echo "1. Вставити цей тег у ваш values.yaml для freelingo-frontend:"
echo "   $IMAGE_TAG"
echo "2. Видалити жорстку прив'язку nodeSelector (kubernetes.io/arch: amd64) з конфігу!"
echo "=========================================================="
