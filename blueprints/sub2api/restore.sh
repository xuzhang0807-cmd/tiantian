#!/usr/bin/env bash
set -euo pipefail
echo "Restore requires filled .env and docker volumes. Import postgres.sql and app-data.tar.gz after reviewing target host paths." >&2
