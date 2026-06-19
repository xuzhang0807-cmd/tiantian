#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="${PROJECT_DIR:-/home/docker/sub2api}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/tt-backups/sub2api}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${BACKUP_ROOT}/${STAMP}"
mkdir -p "$OUT"
cd "$PROJECT_DIR"
cp -a docker-compose.yml .env "$OUT/" 2>/dev/null || true
if docker compose ps postgres >/dev/null 2>&1; then
  docker compose exec -T postgres sh -lc 'pg_dump -U "${POSTGRES_USER:-sub2api}" "${POSTGRES_DB:-sub2api}"' > "$OUT/postgres.sql"
fi
docker run --rm -v sub2api_sub2api_data:/data -v "$OUT":/backup alpine tar -C /data -czf /backup/app-data.tar.gz . 2>/dev/null || true
echo "$OUT"
