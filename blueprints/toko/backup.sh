#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/home/docker/toko}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/tt-backups/toko}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${BACKUP_ROOT}/${STAMP}"

mkdir -p "$OUT"
cd "$PROJECT_DIR"

cp -a docker-compose.yml "$OUT/" 2>/dev/null || true
cp -a .env "$OUT/env.root" 2>/dev/null || true
cp -a backend-v2/.env "$OUT/env.backend-v2" 2>/dev/null || true
cp -a storefront/.env "$OUT/env.storefront" 2>/dev/null || true

if docker compose ps shop-postgres >/dev/null 2>&1; then
  docker compose exec -T shop-postgres sh -lc 'pg_dump -U "${POSTGRES_USER:-shop}" "${POSTGRES_DB:-shop}"' > "$OUT/postgres.sql"
fi

[ -d uploads ] && tar -C uploads -czf "$OUT/uploads.tar.gz" .
[ -d redis-data ] && tar -C redis-data -czf "$OUT/redis-data.tar.gz" .

printf '%s\n' "$OUT"
