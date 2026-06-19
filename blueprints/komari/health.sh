#!/usr/bin/env bash
set -euo pipefail
DOMAIN="${DOMAIN:-komari.kazerush.xyz}"
WEB_PORT="${WEB_PORT:-8083}"
CHECK_EXTERNAL="${CHECK_EXTERNAL:-true}"
check() { local url="$1"; local code; code="$(curl -k -s -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 15 "$url" || true)"; echo "$url -> $code"; [ "$code" = "200" ]; }
check "http://127.0.0.1:${WEB_PORT}/"
[ "$CHECK_EXTERNAL" != true ] || check "https://${DOMAIN}"
