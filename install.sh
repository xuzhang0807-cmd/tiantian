#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/opt/tiantian"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 执行安装。"
    exit 1
  fi
}

check_resources() {
  local avail_mb mem_mb
  avail_mb=$(df -Pm /opt /root 2>/dev/null | awk 'NR>1 {if(min==0 || $4<min) min=$4} END{print min+0}')
  mem_mb=$(free -m | awk '/Mem:/ {print $7+0}')
  [ "$avail_mb" -ge 512 ] || { echo "磁盘空间不足: ${avail_mb}MB 可用，至少需要 512MB"; exit 1; }
  [ "$mem_mb" -ge 128 ] || echo "WARN: 可用内存偏低: ${mem_mb}MB"
}

install_files() {
  mkdir -p "$ROOT/bin" "$ROOT/templates/home-web" "$ROOT/state" "$ROOT/backups" "$ROOT/logs" "$ROOT/cache"
  cp -f "$SRC_DIR/bin/kp" "$ROOT/bin/kp"
  cp -f "$SRC_DIR/tiantian.sh" "$ROOT/tiantian.sh"
  cp -f "$SRC_DIR/templates/home-web/"* "$ROOT/templates/home-web/"
  chmod +x "$ROOT/bin/kp" "$ROOT/tiantian.sh"
  ln -sf "$ROOT/bin/kp" /usr/local/bin/kp
  ln -sf "$ROOT/tiantian.sh" /usr/local/bin/tt
}

verify() {
  bash -n "$ROOT/bin/kp"
  bash -n "$ROOT/tiantian.sh"
  echo "状态: 安装器完成"
  echo "检测: tt/kp 语法通过"
  echo "备份: 补丁安装时生成 latest/original"
}

need_root
check_resources
install_files
verify

echo
if [ -t 0 ]; then
  exec tt
else
  echo "非交互环境已跳过面板。交互使用请运行: tt"
fi
