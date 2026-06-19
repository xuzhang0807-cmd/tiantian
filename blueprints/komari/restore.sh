#!/usr/bin/env bash
set -euo pipefail
DATA_DIR="${DATA_DIR:-/home/komari/data}"
BACKUP_DIR="${1:?Usage: restore.sh <backup-dir>}"
mkdir -p "$DATA_DIR"
tar -C "$DATA_DIR" -xzf "$BACKUP_DIR/komari-data.tar.gz"
