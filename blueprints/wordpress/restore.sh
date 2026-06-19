#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="${PROJECT_DIR:-/home/docker/wordpress}"
BACKUP_DIR="${1:?Usage: restore.sh <backup-dir>}"
mkdir -p "$PROJECT_DIR/data"
cd "$PROJECT_DIR"
[ -f "$BACKUP_DIR/docker-compose.yml" ] && cp -a "$BACKUP_DIR/docker-compose.yml" ./docker-compose.yml
[ -f "$BACKUP_DIR/env" ] && cp -a "$BACKUP_DIR/env" ./.env
[ -f "$BACKUP_DIR/wp-data.tar.gz" ] && tar -C data -xzf "$BACKUP_DIR/wp-data.tar.gz"
