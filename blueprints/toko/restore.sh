#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/home/docker/toko}"
BACKUP_DIR="${1:?Usage: restore.sh <backup-dir>}"

[ -d "$BACKUP_DIR" ] || { echo "Backup dir not found: $BACKUP_DIR" >&2; exit 1; }
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

[ -f "$BACKUP_DIR/docker-compose.yml" ] && cp -a "$BACKUP_DIR/docker-compose.yml" ./docker-compose.yml
[ -f "$BACKUP_DIR/env.root" ] && cp -a "$BACKUP_DIR/env.root" ./.env
mkdir -p backend-v2 storefront uploads redis-data
[ -f "$BACKUP_DIR/env.backend-v2" ] && cp -a "$BACKUP_DIR/env.backend-v2" backend-v2/.env
[ -f "$BACKUP_DIR/env.storefront" ] && cp -a "$BACKUP_DIR/env.storefront" storefront/.env
[ -f "$BACKUP_DIR/uploads.tar.gz" ] && tar -C uploads -xzf "$BACKUP_DIR/uploads.tar.gz"
[ -f "$BACKUP_DIR/redis-data.tar.gz" ] && tar -C redis-data -xzf "$BACKUP_DIR/redis-data.tar.gz"

if [ -f "$BACKUP_DIR/postgres.sql" ]; then
  docker compose up -d shop-postgres
  docker compose exec -T shop-postgres sh -lc 'psql -U "${POSTGRES_USER:-shop}" "${POSTGRES_DB:-shop}"' < "$BACKUP_DIR/postgres.sql"
fi
