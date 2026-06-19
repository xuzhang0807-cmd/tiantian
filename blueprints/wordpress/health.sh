#!/usr/bin/env bash
set -euo pipefail
WEB_PORT="${WEB_PORT:-8085}"
code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 15 "http://127.0.0.1:${WEB_PORT}/" || true)"
echo "wordpress local -> ${code}"
[ "$code" = "200" ]
