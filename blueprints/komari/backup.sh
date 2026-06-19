#!/usr/bin/env bash
set -euo pipefail
DATA_DIR="${DATA_DIR:-/home/komari/data}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/tt-backups/komari}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${BACKUP_ROOT}/${STAMP}"
mkdir -p "$OUT"
tar -C "$DATA_DIR" -czf "$OUT/komari-data.tar.gz" .
echo "$OUT"
