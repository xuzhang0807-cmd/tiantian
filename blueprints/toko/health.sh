#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:-toko.kazerush.xyz}"
STOREFRONT_PORT="${STOREFRONT_PORT:-3000}"
BACKEND_PORT="${BACKEND_PORT:-3001}"
CHECK_EXTERNAL="${CHECK_EXTERNAL:-true}"

check_url() {
  local label="$1" url="$2" expected="${3:-200}"
  local code
  code="$(curl -k -s -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 15 "$url" || true)"
  printf '%-28s %s -> %s\n' "$label" "$url" "$code"
  [ "$code" = "$expected" ]
}

check_url "storefront local" "http://127.0.0.1:${STOREFRONT_PORT}/shop"
check_url "backend local" "http://127.0.0.1:${BACKEND_PORT}/health"

if [ "$CHECK_EXTERNAL" = "true" ] && [ -n "$DOMAIN" ]; then
  check_url "storefront https" "https://${DOMAIN}/shop"
  check_url "backend https" "https://${DOMAIN}/shop-api/health"
fi
