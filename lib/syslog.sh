#!/bin/bash
# =============================================================================
# TianTian Ops - syslog.sh
# System log inspection and journal cleanup helper inspired by Kejilion log panel.
# =============================================================================

_syslog_journal_available() {
    command -v journalctl >/dev/null 2>&1
}

_syslog_limit() {
    local limit="${1:-100}"
    case "$limit" in *[!0-9]*|'') limit=100 ;; esac
    echo "$limit"
}

_syslog_vacuum_mode() {
    case "${1:-}" in
        7d|3d|1d) echo "--vacuum-time=$1" ;;
        500m|500M) echo "--vacuum-size=500M" ;;
        1g|1G) echo "--vacuum-size=1G" ;;
        *) return 1 ;;
    esac
}

syslog_overview() {
    print_header "系统日志概览"
    echo "主机名: $(hostname 2>/dev/null || echo '-')"
    echo "系统时间: $(date 2>/dev/null || echo '-')"
    echo ""
    echo "[ /var/log 占用 ]"
    du -sh /var/log 2>/dev/null || print_warn "无法读取 /var/log"
    echo ""
    echo "[ journal 占用 ]"
    if _syslog_journal_available; then
        journalctl --disk-usage 2>/dev/null || print_warn "无法读取 journal 占用"
    else
        print_warn "journalctl 未安装或不可用"
    fi
    echo ""
    echo "[ 常见日志文件 ]"
    for file in /var/log/syslog /var/log/messages /var/log/auth.log /var/log/secure /var/log/nginx/error.log; do
        [ -f "$file" ] && printf '%-8s %s\n' "$(du -h "$file" 2>/dev/null | awk '{print $1}')" "$file"
    done
    return 0
}

syslog_recent() {
    local limit
    limit="$(_syslog_limit "${1:-100}")"
    print_header "最近系统日志（journal ${limit} 行）"
    if _syslog_journal_available; then
        journalctl -n "$limit" --no-pager 2>/dev/null || print_warn "无法读取 journal"
    else
        print_warn "journalctl 未安装或不可用"
    fi
}

syslog_service() {
    local service="${1:-}" limit
    limit="$(_syslog_limit "${2:-100}")"
    [ -n "$service" ] || die "用法: tt syslog service <service> [limit]"
    print_header "服务日志: $service（${limit} 行）"
    if _syslog_journal_available; then
        journalctl -u "$service" -n "$limit" --no-pager 2>/dev/null || print_warn "无法读取服务日志: $service"
    else
        print_warn "journalctl 未安装或不可用"
    fi
}

syslog_auth() {
    local limit
    limit="$(_syslog_limit "${1:-50}")"
    print_header "登录与认证日志"
    echo "[ 最近登录 ]"
    last -n 10 2>/dev/null || print_warn "last 不可用"
    echo ""
    echo "[ 认证日志 ]"
    if [ -f /var/log/auth.log ]; then
        tail -n "$limit" /var/log/auth.log 2>/dev/null || true
    elif [ -f /var/log/secure ]; then
        tail -n "$limit" /var/log/secure 2>/dev/null || true
    else
        print_warn "未找到 /var/log/auth.log 或 /var/log/secure"
    fi
}

syslog_vacuum_plan() {
    local mode="${1:-7d}" option
    option="$(_syslog_vacuum_mode "$mode")" || die "用法: tt syslog vacuum-plan [7d|3d|1d|500M|1G]"
    print_header "journal 清理预案"
    echo "将执行: journalctl $option"
    echo "影响范围: 仅清理 systemd journal 旧日志，不删除 /var/log 普通日志文件。"
    echo "当前占用:"
    if _syslog_journal_available; then
        journalctl --disk-usage 2>/dev/null || true
    else
        print_warn "journalctl 未安装或不可用"
    fi
    echo "执行命令: tt syslog vacuum $mode --yes"
}

syslog_vacuum() {
    local mode="${1:-}" yes="${2:-}" option
    [ "$yes" = "--yes" ] || die "真实清理需要追加 --yes；请先运行 tt syslog vacuum-plan [7d|3d|1d|500M|1G]"
    option="$(_syslog_vacuum_mode "$mode")" || die "用法: tt syslog vacuum [7d|3d|1d|500M|1G] --yes"
    print_header "执行 journal 清理"
    syslog_vacuum_plan "$mode"
    if _syslog_journal_available; then
        journalctl --rotate 2>/dev/null || true
        journalctl "$option"
        print_success "journal 清理完成"
    else
        die "journalctl 未安装或不可用"
    fi
}

syslog_menu() {
    while true; do
        echo ""
        echo -e "  ${BOLD}系统日志管理${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC}) 日志概览"
        echo -e "  ${GREEN}2${NC}) 最近系统日志"
        echo -e "  ${GREEN}3${NC}) 指定服务日志"
        echo -e "  ${GREEN}4${NC}) 登录/认证日志"
        echo -e "  ${GREEN}5${NC}) journal 清理预案"
        echo -e "  ${GREEN}6${NC}) journal 清理 ⚠️"
        echo -e "  ${GREEN}0${NC}) 返回"
        echo ""
        read -r -p "  tt/syslog> " choice
        case "$choice" in
            1) syslog_overview ;;
            2) read -r -p "最近行数 [100]: " limit; syslog_recent "${limit:-100}" ;;
            3) read -r -p "服务名: " service; read -r -p "最近行数 [100]: " limit; syslog_service "$service" "${limit:-100}" ;;
            4) read -r -p "认证日志行数 [50]: " limit; syslog_auth "${limit:-50}" ;;
            5) read -r -p "清理模式 [7d|3d|1d|500M|1G，默认7d]: " mode; syslog_vacuum_plan "${mode:-7d}" ;;
            6)
                read -r -p "清理模式 [7d|3d|1d|500M|1G，默认7d]: " mode
                syslog_vacuum_plan "${mode:-7d}"
                read -r -p "确认清理 journal？输入 YES 继续: " confirm
                [ "$confirm" = "YES" ] && syslog_vacuum "${mode:-7d}" --yes || print_warn "已取消"
                ;;
            0|q|Q) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
