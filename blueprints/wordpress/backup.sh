#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="${PROJECT_DIR:-/home/docker/wordpress}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/tt-backups/wordpress}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${BACKUP_ROOT}/${STAMP}"
mkdir -p "$OUT"
cd "$PROJECT_DIR"
cp -a docker-compose.yml "$OUT/" 2>/dev/null || true
cp -a .env "$OUT/env" 2>/dev/null || true
if docker compose ps db >/dev/null 2>&1; then
  docker compose exec -T db sh -lc 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' > "$OUT/mariadb.sql"
fi
[ -d data ] && tar -C data -czf "$OUT/wp-data.tar.gz" .
echo "$OUT"
