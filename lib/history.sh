#!/bin/bash
# =============================================================================
# TianTian Ops - history.sh
# Shell history viewer/backup/clear helper inspired by Kejilion history panel.
# =============================================================================

TT_HISTORY_BACKUP_ROOT="${TT_HISTORY_BACKUP_ROOT:-${TT_BACKUP_ROOT}/history}"

_history_candidates() {
    local user_home="${1:-$HOME}"
    printf '%s\n' \
        "${user_home}/.bash_history" \
        "${user_home}/.zsh_history" \
        "${user_home}/.ash_history" \
        "${user_home}/.local/share/fish/fish_history"
}

_history_find_files() {
    local user_home="${1:-$HOME}" file
    while IFS= read -r file; do
        [ -f "$file" ] && printf '%s\n' "$file"
    done < <(_history_candidates "$user_home")
}

_history_require_yes() {
    [ "${1:-}" = "--yes" ] || die "真实写入需要追加 --yes；请先运行 tt history backup 或 tt history list"
}

history_files() {
    print_header "Shell 历史文件"
    local found="false" file lines size
    while IFS= read -r file; do
        found="true"
        lines="$(wc -l < "$file" 2>/dev/null || echo 0)"
        size="$(du -h "$file" 2>/dev/null | awk '{print $1}' || echo '-')"
        printf '%-8s %-8s %s\n' "${lines}行" "$size" "$file"
    done < <(_history_find_files "$HOME")
    [ "$found" = "true" ] || print_warn "未找到常见 shell 历史文件"
}

history_list() {
    local limit="${1:-80}" file
    case "$limit" in *[!0-9]*|'') limit=80 ;; esac
    print_header "Shell 历史记录（最近 ${limit} 行）"
    while IFS= read -r file; do
        echo "--- $file ---"
        nl -ba "$file" 2>/dev/null | tail -n "$limit" || true
    done < <(_history_find_files "$HOME")
}

history_search() {
    local keyword="${1:-}" limit="${2:-80}" file
    [ -n "$keyword" ] || die "用法: tt history search <keyword> [limit]"
    case "$limit" in *[!0-9]*|'') limit=80 ;; esac
    print_header "Shell 历史搜索: $keyword"
    while IFS= read -r file; do
        echo "--- $file ---"
        grep -n --color=never -F "$keyword" "$file" 2>/dev/null | tail -n "$limit" || true
    done < <(_history_find_files "$HOME")
}

history_backup() {
    local ts dir file name count=0
    ts="$(date '+%Y%m%d-%H%M%S')"
    dir="${TT_HISTORY_BACKUP_ROOT}/${ts}"
    mkdir -p "$dir"
    while IFS= read -r file; do
        name="$(basename "$file")"
        cp -a "$file" "${dir}/${name}"
        count=$((count + 1))
    done < <(_history_find_files "$HOME")
    if [ "$count" -eq 0 ]; then
        print_warn "未找到可备份的 shell 历史文件"
        rmdir "$dir" 2>/dev/null || true
        return 0
    fi
    print_success "Shell 历史已备份: $dir"
    echo "$dir"
}

history_clear_plan() {
    print_header "Shell 历史清空预案"
    echo "将清空以下历史文件内容，但保留文件本身："
    history_files
    echo "安全措施: 执行前自动备份到 ${TT_HISTORY_BACKUP_ROOT}/<timestamp>。"
    echo "执行命令: tt history clear --yes"
}

history_clear() {
    local yes="${1:-}"
    _history_require_yes "$yes"
    local file count=0
    history_backup >/dev/null
    while IFS= read -r file; do
        : > "$file"
        count=$((count + 1))
    done < <(_history_find_files "$HOME")
    print_success "已清空 shell 历史文件数量: $count"
}

history_menu() {
    while true; do
        echo ""
        echo -e "  ${BOLD}命令行历史记录${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC}) 历史文件概览"
        echo -e "  ${GREEN}2${NC}) 查看最近历史"
        echo -e "  ${GREEN}3${NC}) 搜索历史"
        echo -e "  ${GREEN}4${NC}) 备份历史"
        echo -e "  ${GREEN}5${NC}) 清空预案"
        echo -e "  ${GREEN}6${NC}) 清空历史 ⚠️"
        echo -e "  ${GREEN}0${NC}) 返回"
        echo ""
        read -r -p "  tt/history> " choice
        case "$choice" in
            1) history_files ;;
            2) read -r -p "最近行数 [80]: " limit; history_list "${limit:-80}" ;;
            3) read -r -p "关键词: " keyword; read -r -p "最多结果 [80]: " limit; history_search "$keyword" "${limit:-80}" ;;
            4) history_backup ;;
            5) history_clear_plan ;;
            6)
                history_clear_plan
                read -r -p "确认清空以上 shell 历史？输入 YES 继续: " confirm
                [ "$confirm" = "YES" ] && history_clear --yes || print_warn "已取消"
                ;;
            0|q|Q) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
