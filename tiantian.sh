#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/opt/tiantian"
KP="$ROOT/bin/kp"
FIRST_RUN_FLAG="$ROOT/state/tt-first-run-seen"

mkdir -p "$ROOT/state"

line() { printf '%s\n' '+----------------------------------------------------------+'; }

pause() {
  printf '\n按 Enter 返回面板...'
  read -r _ || true
}

is_patched() {
  grep -q 'TT_NGINX_PATCH_BEGIN' /usr/local/bin/k 2>/dev/null
}

has_kejilion() {
  [ -f /usr/local/bin/k ] && [ -f "$HOME/kejilion.sh" ]
}

banner() {
  clear 2>/dev/null || true
  line
  echo "|              TianTian TT 补丁管理面板                |"
  line
  echo "|  1. 补丁安装                                         |"
  echo "|  2. 补丁状态                                         |"
  echo "|  3. 备份恢复                                         |"
  echo "|  0. 退出                                             |"
  line
}

first_run_prompt() {
  [ -f "$FIRST_RUN_FLAG" ] && return 0
  printf '%s\n' "$(date +%Y%m%d-%H%M%S)" > "$FIRST_RUN_FLAG"
  has_kejilion || return 0
  is_patched && return 0

  line
  echo "检测到 kejilion 已安装，但 TT nginx 补丁尚未安装。"
  echo "是否立即安装补丁？"
  echo "输入 y/yes 立即安装；输入 n/no 进入面板。"
  line
  printf "请选择: "
  read -r ans || ans="n"
  case "${ans,,}" in
    y|yes)
      "$KP" install
      pause
      ;;
    n|no|*)
      ;;
  esac
}

menu_loop() {
  while true; do
    banner
    printf "请输入选项: "
    read -r choice || choice="0"
    case "$choice" in
      1)
        "$KP" install || true
        pause
        ;;
      2)
        "$KP" status || true
        pause
        ;;
      3)
        echo "将从最新备份恢复补丁前状态。"
        printf "确认恢复？输入 y/yes 继续: "
        read -r ans || ans="n"
        case "${ans,,}" in
          y|yes) "$KP" restore || true ;;
          *) echo "已取消恢复。" ;;
        esac
        pause
        ;;
      0|q|quit|exit)
        echo "已退出。"
        exit 0
        ;;
      *)
        echo "无效选项。"
        pause
        ;;
    esac
  done
}

case "${1:-menu}" in
  menu) first_run_prompt; menu_loop ;;
  install) "$KP" install ;;
  status) "$KP" status ;;
  restore) "$KP" restore ;;
  *) echo "usage: tt [menu|install|status|restore]"; exit 2 ;;
esac
