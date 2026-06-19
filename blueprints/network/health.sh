#!/usr/bin/env bash
set -euo pipefail

systemctl is-active sing-box

check_tcp() {
  local port="$1"
  if ss -H -ltn "sport = :${port}" | grep -q .; then
    echo "tcp ${port}: listening"
  else
    echo "tcp ${port}: not listening" >&2
    exit 1
  fi
}

check_udp() {
  local port="$1"
  if ss -H -lun "sport = :${port}" | grep -q .; then
    echo "udp ${port}: listening"
  else
    echo "udp ${port}: not listening" >&2
    exit 1
  fi
}

check_tcp 443
check_tcp 8443
check_tcp 8444
check_udp 30888

docker exec nginx nginx -t 2>/dev/null || nginx -t
