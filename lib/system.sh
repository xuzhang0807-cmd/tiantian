#!/bin/bash
# =============================================================================
# TianTian Ops - system.sh
# Safe system preference toolbox: timezone, hostname, address-family preference.
# =============================================================================

SYSTEM_BACKUP_ROOT="${TT_SYSTEM_BACKUP_ROOT:-${TT_BACKUP_ROOT}/system}"

_system_backup_dir() {
    local ts
    ts="$(date '+%Y%m%d-%H%M%S')"
    echo "${SYSTEM_BACKUP_ROOT}/${ts}"
}

_system_write_requires_yes() {
    [ "${1:-}" = "--yes" ] || die "真实写入需要追加 --yes；请先运行对应 plan 查看预案"
}

system_status() {
    print_header "系统基础设置"
    echo "主机名: $(hostname 2>/dev/null || echo unknown)"
    if has_cmd hostnamectl; then
        hostnamectl 2>/dev/null | sed -n '1,8p' || true
    fi
    echo ""
    echo "时区/时间:"
    if has_cmd timedatectl; then
        timedatectl 2>/dev/null | sed -n '1,8p' || true
    else
        date
        [ -f /etc/timezone ] && echo "timezone_file: $(cat /etc/timezone)"
    fi
    echo ""
    echo "地址族优先级:"
    system_ip_prefer_status
}

system_backup() {
    check_root
    local dir
    dir="$(_system_backup_dir)"
    mkdir -p "$dir"
    [ -f /etc/hostname ] && cp -a /etc/hostname "$dir/hostname"
    [ -f /etc/hosts ] && cp -a /etc/hosts "$dir/hosts"
    [ -f /etc/timezone ] && cp -a /etc/timezone "$dir/timezone"
    [ -L /etc/localtime ] && readlink /etc/localtime > "$dir/localtime.link" || true
    [ -f /etc/gai.conf ] && cp -a /etc/gai.conf "$dir/gai.conf"
    if has_cmd hostnamectl; then hostnamectl > "$dir/hostnamectl.txt" 2>&1 || true; fi
    if has_cmd timedatectl; then timedatectl > "$dir/timedatectl.txt" 2>&1 || true; fi
    print_success "系统设置备份完成: $dir"
    echo "$dir"
}

system_timezone_plan() {
    local zone="${1:-}"
    [ -n "$zone" ] || die "用法: tt system timezone-plan <Area/City>"
    print_header "时区修改预案"
    echo "目标时区: $zone"
    echo "当前时区: $(timedatectl 2>/dev/null | awk -F': ' '/Time zone/{print $2}' || true)"
    if [ ! -f "/usr/share/zoneinfo/$zone" ]; then
        print_warn "未找到 /usr/share/zoneinfo/$zone；请确认系统 tzdata 是否完整"
    fi
    echo "将执行: timedatectl set-timezone '$zone'"
    echo "安全措施: 写入前自动备份 /etc/timezone、/etc/localtime 状态。"
}

system_timezone_set() {
    local zone="${1:-}" yes="${2:-}"
    [ -n "$zone" ] || die "用法: tt system timezone-set <Area/City> --yes"
    _system_write_requires_yes "$yes"
    [ -f "/usr/share/zoneinfo/$zone" ] || die "时区不存在: $zone"
    check_root
    system_backup >/dev/null
    if has_cmd timedatectl; then
        timedatectl set-timezone "$zone"
    else
        ln -snf "/usr/share/zoneinfo/$zone" /etc/localtime
        echo "$zone" > /etc/timezone
    fi
    print_success "时区已设置为: $zone"
}

system_hostname_plan() {
    local name="${1:-}"
    [ -n "$name" ] || die "用法: tt system hostname-plan <new-hostname>"
    case "$name" in
        *[!A-Za-z0-9.-]*|.*|*..*|*-|-) die "主机名仅支持字母、数字、点、短横线，且不能以点/短横线异常开头结尾" ;;
    esac
    print_header "主机名修改预案"
    echo "当前主机名: $(hostname 2>/dev/null || true)"
    echo "目标主机名: $name"
    echo "将执行: hostnamectl set-hostname '$name'（无 hostnamectl 时写 /etc/hostname）"
    echo "安全措施: 写入前自动备份 /etc/hostname 与 /etc/hosts。"
    echo "提示: 如需 hosts 解析同步，可再使用 tt hosts add-plan 127.0.1.1 $name。"
}

system_hostname_set() {
    local name="${1:-}" yes="${2:-}"
    [ -n "$name" ] || die "用法: tt system hostname-set <new-hostname> --yes"
    _system_write_requires_yes "$yes"
    system_hostname_plan "$name" >/dev/null
    check_root
    system_backup >/dev/null
    if has_cmd hostnamectl; then
        hostnamectl set-hostname "$name"
    else
        echo "$name" > /etc/hostname
        hostname "$name" 2>/dev/null || true
    fi
    print_success "主机名已设置为: $name"
}

system_ip_prefer_status() {
    if [ -f /etc/gai.conf ] && grep -Eq '^\s*precedence\s+::ffff:0:0/96\s+100\s*$' /etc/gai.conf; then
        echo "当前倾向: IPv4 优先（/etc/gai.conf 已设置 precedence ::ffff:0:0/96 100）"
    else
        echo "当前倾向: 系统默认（通常 IPv6/IPv4 按系统解析策略）"
    fi
    [ -f /etc/gai.conf ] && grep -nE '^\s*(precedence|label)\s+' /etc/gai.conf | sed -n '1,12p' || true
}

system_ip_prefer_plan() {
    local mode="${1:-status}"
    print_header "IPv4/IPv6 优先级预案"
    system_ip_prefer_status
    echo ""
    case "$mode" in
        ipv4|v4)
            echo "目标: IPv4 优先"
            echo "将写入: precedence ::ffff:0:0/96  100 到 /etc/gai.conf（若已存在则先移除旧项）"
            ;;
        default|auto|reset)
            echo "目标: 恢复系统默认地址族策略"
            echo "将移除: /etc/gai.conf 中 TT 管理的 precedence ::ffff:0:0/96 100 项"
            ;;
        status)
            return 0
            ;;
        *) die "用法: tt system ip-prefer-plan [ipv4|default]" ;;
    esac
    echo "安全措施: 写入前自动备份 /etc/gai.conf。"
}

system_ip_prefer_set() {
    local mode="${1:-}" yes="${2:-}"
    [ -n "$mode" ] || die "用法: tt system ip-prefer-set <ipv4|default> --yes"
    _system_write_requires_yes "$yes"
    system_ip_prefer_plan "$mode" >/dev/null
    check_root
    system_backup >/dev/null
    touch /etc/gai.conf
    local tmp
    tmp="$(mktemp)"
    grep -Ev '^(# Managed by TianTian Ops: prefer IPv4-mapped addresses|[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100[[:space:]]*)$' /etc/gai.conf > "$tmp" || true
    case "$mode" in
        ipv4|v4)
            printf '\n# Managed by TianTian Ops: prefer IPv4-mapped addresses\nprecedence ::ffff:0:0/96  100\n' >> "$tmp"
            ;;
        default|auto|reset)
            :
            ;;
        *) rm -f "$tmp"; die "用法: tt system ip-prefer-set <ipv4|default> --yes" ;;
    esac
    cat "$tmp" > /etc/gai.conf
    rm -f "$tmp"
    print_success "地址族优先级已更新: $mode"
}

system_restore() {
    local backup_dir="${1:-}" yes="${2:-}"
    [ -n "$backup_dir" ] || die "用法: tt system restore <backup_dir> --yes"
    _system_write_requires_yes "$yes"
    [ -d "$backup_dir" ] || die "备份目录不存在: $backup_dir"
    check_root
    [ -f "$backup_dir/hostname" ] && cp -a "$backup_dir/hostname" /etc/hostname
    [ -f "$backup_dir/hosts" ] && cp -a "$backup_dir/hosts" /etc/hosts
    [ -f "$backup_dir/timezone" ] && cp -a "$backup_dir/timezone" /etc/timezone
    if [ -f "$backup_dir/localtime.link" ]; then
        local link
        link="$(cat "$backup_dir/localtime.link")"
        [ -n "$link" ] && ln -snf "$link" /etc/localtime
    fi
    [ -f "$backup_dir/gai.conf" ] && cp -a "$backup_dir/gai.conf" /etc/gai.conf
    print_success "系统设置已从备份恢复: $backup_dir"
}

system_menu() {
    while true; do
        echo ""
        echo -e "  ${BOLD}系统基础设置${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC}) 状态总览"
        echo -e "  ${GREEN}2${NC}) 时区修改预案"
        echo -e "  ${GREEN}3${NC}) 时区真实修改 ⚠️"
        echo -e "  ${GREEN}4${NC}) 主机名修改预案"
        echo -e "  ${GREEN}5${NC}) 主机名真实修改 ⚠️"
        echo -e "  ${GREEN}6${NC}) IPv4/IPv6 优先级状态"
        echo -e "  ${GREEN}7${NC}) IPv4/IPv6 优先级预案"
        echo -e "  ${GREEN}8${NC}) IPv4/IPv6 优先级真实修改 ⚠️"
        echo -e "  ${GREEN}9${NC}) 备份系统设置"
        echo -e "  ${GREEN}0${NC}) 返回"
        echo ""
        read -r -p "  tt/system> " choice
        case "$choice" in
            1) system_status ;;
            2) read -r -p "时区(如 Asia/Shanghai): " zone; system_timezone_plan "$zone" ;;
            3) read -r -p "时区(如 Asia/Shanghai): " zone; system_timezone_set "$zone" --yes ;;
            4) read -r -p "新主机名: " name; system_hostname_plan "$name" ;;
            5) read -r -p "新主机名: " name; system_hostname_set "$name" --yes ;;
            6) system_ip_prefer_status ;;
            7) read -r -p "模式 ipv4|default: " mode; system_ip_prefer_plan "$mode" ;;
            8) read -r -p "模式 ipv4|default: " mode; system_ip_prefer_set "$mode" --yes ;;
            9) system_backup ;;
            0|q|Q) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
