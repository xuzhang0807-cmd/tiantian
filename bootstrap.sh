#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${TT_REPO:-xuzhang0807-cmd/tiantian}"
BRANCH="${TT_BRANCH:-main}"
WORKDIR="${TT_WORKDIR:-/tmp/tiantian-install}"
TARBALL_URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 执行安装。"
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "缺少命令: $1"; exit 1; }
}

check_resources() {
  local avail_mb mem_mb
  avail_mb=$(df -Pm /tmp /opt /root 2>/dev/null | awk 'NR>1 {if(min==0 || $4<min) min=$4} END{print min+0}')
  mem_mb=$(free -m | awk '/Mem:/ {print $7+0}')
  [ "$avail_mb" -ge 512 ] || { echo "磁盘空间不足: ${avail_mb}MB 可用，至少需要 512MB"; exit 1; }
  [ "$mem_mb" -ge 128 ] || echo "WARN: 可用内存偏低: ${mem_mb}MB"
}

main() {
  need_root
  need_cmd curl
  need_cmd tar
  check_resources

  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"

  echo "状态: 正在拉取 TT 项目"
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 --branch "$BRANCH" "https://github.com/${REPO}.git" "$WORKDIR" >/dev/null 2>&1
  else
    curl -fsSL --connect-timeout 10 --max-time 120 "${TARBALL_URL}?t=$(date +%s)" -o "$WORKDIR/tiantian.tar.gz"
    tar -xzf "$WORKDIR/tiantian.tar.gz" -C "$WORKDIR" --strip-components=1
  fi

  echo "状态: 正在启动安装器"
  cd "$WORKDIR"
  bash install.sh
}

main "$@"
