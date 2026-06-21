#!/bin/bash
# =============================================================================
# TianTian Ops - firewall.sh
# Firewall discovery, planning, write, and rollback helpers.
# =============================================================================

TT_FIREWALL_BACKUP_DIR="${TT_FIREWALL_BACKUP_DIR:-${TT_HOME}/state/firewall-backups}"

_firewall_validate_change() {
    local action="$1" port="$2" proto="$3" source="$4"
    case "$action" in
        allow|deny|delete) ;;
        *)
            print_fail "动作不支持: $action"
            echo "用法: tt firewall [plan|apply] [allow|deny|delete] <port> [tcp|udp] [source_cidr]"
            return 1
            ;;
    esac
    if ! validate_port "$port"; then
        print_fail "端口不合法: ${port:-空}"
        echo "用法: tt firewall [plan|apply] [allow|deny|delete] <port> [tcp|udp] [source_cidr]"
        return 1
    fi
    case "$proto" in
        tcp|udp) ;;
        *)
            print_fail "协议不支持: $proto"
            echo "协议仅支持 tcp/udp"
            return 1
            ;;
    esac
    if [ -n "$source" ] && ! [[ "$source" =~ ^[0-9a-fA-F:.]+(/[0-9]{1,3})?$ ]]; then
        print_fail "来源网段格式可疑: $source"
        echo "示例: 203.0.113.0/24 或 2001:db8::/32"
        return 1
    fi
}

_firewall_backend() {
    if has_cmd ufw; then
        echo "ufw"
    elif has_cmd firewall-cmd; then
        echo "firewalld"
    elif has_cmd nft; then
        echo "nft"
    elif has_cmd iptables; then
        echo "iptables"
    else
        echo "none"
    fi
}

_firewall_backup() {
    local tag dir backend
    tag="$(date +%Y%m%d_%H%M%S)"
    dir="${TT_FIREWALL_BACKUP_DIR}/${tag}"
    mkdir -p "$dir"
    backend="$(_firewall_backend)"
    echo "$backend" > "${dir}/backend.txt"
    date -Is > "${dir}/created_at.txt"
    if has_cmd ufw; then
        ufw status verbose > "${dir}/ufw-status.txt" 2>&1 || true
        [ -d /etc/ufw ] && tar -czf "${dir}/ufw-etc.tar.gz" -C /etc ufw 2>/dev/null || true
    fi
    if has_cmd firewall-cmd; then
        firewall-cmd --state > "${dir}/firewalld-state.txt" 2>&1 || true
        firewall-cmd --list-all > "${dir}/firewalld-list-all.txt" 2>&1 || true
        [ -d /etc/firewalld ] && tar -czf "${dir}/firewalld-etc.tar.gz" -C /etc firewalld 2>/dev/null || true
    fi
    has_cmd nft && nft list ruleset > "${dir}/nft.rules" 2>/dev/null || true
    has_cmd iptables-save && iptables-save > "${dir}/iptables.rules" 2>/dev/null || true
    has_cmd ip6tables-save && ip6tables-save > "${dir}/ip6tables.rules" 2>/dev/null || true
    printf '%s\n' "$dir"
}

_firewall_ufw_apply() {
    local action="$1" port="$2" proto="$3" source="$4"
    local target="${port}/${proto}"
    if [ -n "$source" ]; then
        case "$action" in
            allow) ufw allow from "$source" to any port "$port" proto "$proto" ;;
            deny) ufw deny from "$source" to any port "$port" proto "$proto" ;;
            delete) ufw delete allow from "$source" to any port "$port" proto "$proto" || ufw delete deny from "$source" to any port "$port" proto "$proto" ;;
        esac
    else
        ufw "$action" "$target"
    fi
}

_firewall_firewalld_apply() {
    local action="$1" port="$2" proto="$3"
    local target="${port}/${proto}"
    case "$action" in
        allow) firewall-cmd --add-port="$target" --permanent ;;
        deny|delete) firewall-cmd --remove-port="$target" --permanent ;;
    esac
    firewall-cmd --reload
}

_firewall_nft_apply() {
    local action="$1" port="$2" proto="$3" source="$4"
    local family="ip" source_expr=""
    echo "$source" | grep -q ':' && family="ip6"
    [ -n "$source" ] && source_expr="${family} saddr ${source} "
    nft list table inet tt_filter >/dev/null 2>&1 || nft add table inet tt_filter
    nft list chain inet tt_filter input >/dev/null 2>&1 || nft 'add chain inet tt_filter input { type filter hook input priority 0; policy accept; }'
    case "$action" in
        allow) nft add rule inet tt_filter input ${source_expr}${proto} dport "$port" accept comment "tt-allow-${port}-${proto}" ;;
        deny) nft add rule inet tt_filter input ${source_expr}${proto} dport "$port" drop comment "tt-deny-${port}-${proto}" ;;
        delete)
            print_warn "nft 删除需要按 handle 精确删除；请使用 tt firewall restore <backup_dir> 或 nft -a list ruleset 手动删除。"
            return 2
            ;;
    esac
}

_firewall_iptables_apply() {
    local action="$1" port="$2" proto="$3" source="$4"
    local source_arg=()
    [ -n "$source" ] && source_arg=(-s "$source")
    case "$action" in
        allow) iptables -I INPUT "${source_arg[@]}" -p "$proto" --dport "$port" -j ACCEPT ;;
        deny) iptables -I INPUT "${source_arg[@]}" -p "$proto" --dport "$port" -j DROP ;;
        delete)
            iptables -D INPUT "${source_arg[@]}" -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || \
            iptables -D INPUT "${source_arg[@]}" -p "$proto" --dport "$port" -j DROP
            ;;
    esac
}

firewall_status() {
    print_header "防火墙状态"

    print_title "系统防火墙服务"
    if has_cmd systemctl; then
        for svc in ufw firewalld nftables iptables docker; do
            local unit active enabled
            unit="${svc}.service"
            if systemctl list-unit-files --type=service --no-legend "$unit" 2>/dev/null | grep -q "^$unit"; then
                active="$(systemctl is-active "$unit" 2>/dev/null || true)"
                enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
                printf "  %-12s active=%-10s enabled=%s\n" "$svc" "${active:-unknown}" "${enabled:-unknown}"
            fi
        done
    else
        print_warn "缺少 systemctl，跳过服务状态"
    fi
    echo ""

    print_title "规则摘要"
    if has_cmd ufw; then
        echo "[ufw]"
        ufw status verbose 2>/dev/null | sed -n '1,20p' || true
        echo ""
    fi
    if has_cmd firewall-cmd; then
        echo "[firewalld]"
        firewall-cmd --state 2>/dev/null || true
        firewall-cmd --list-all 2>/dev/null | sed -n '1,30p' || true
        echo ""
    fi
    if has_cmd nft; then
        echo "[nftables]"
        nft list ruleset 2>/dev/null | sed -n '1,60p' || true
        echo ""
    elif has_cmd iptables; then
        echo "[iptables]"
        iptables -S 2>/dev/null | sed -n '1,60p' || true
        echo ""
    else
        print_warn "未找到 nft/iptables 命令"
    fi

    print_title "当前监听端口"
    tools_ports | sed -n '1,80p' || true
}

firewall_plan() {
    local action="${1:-allow}"
    local port="${2:-}"
    local proto="${3:-tcp}"
    local source="${4:-}"
    local backend target

    print_header "防火墙变更预案"
    echo "模式: 只生成计划，不执行任何防火墙写入。"
    echo ""

    _firewall_validate_change "$action" "$port" "$proto" "$source" || return 1
    backend="$(_firewall_backend)"
    target="${port}/${proto}"

    print_title "当前状态（只读摘要）"
    case "$backend" in
        ufw) ufw status 2>/dev/null | sed -n '1,12p' || true ;;
        firewalld) firewall-cmd --state 2>/dev/null || true; firewall-cmd --list-ports 2>/dev/null || true ;;
        nft) nft list ruleset 2>/dev/null | sed -n '1,25p' || true ;;
        iptables) iptables -S 2>/dev/null | sed -n '1,25p' || true ;;
        *) print_warn "未检测到 ufw/firewalld/nft/iptables。" ;;
    esac
    echo ""

    print_title "执行前备份"
    echo "tt firewall backup"
    echo ""

    print_title "候选命令（未执行）"
    case "$backend" in
        ufw)
            if [ -n "$source" ]; then
                case "$action" in
                    allow) echo "ufw allow from $source to any port $port proto $proto" ;;
                    deny) echo "ufw deny from $source to any port $port proto $proto" ;;
                    delete) echo "ufw delete allow from $source to any port $port proto $proto" ;;
                esac
            else
                echo "ufw $action $target"
            fi
            ;;
        firewalld)
            case "$action" in
                allow) echo "firewall-cmd --add-port=$target --permanent && firewall-cmd --reload" ;;
                deny|delete) echo "firewall-cmd --remove-port=$target --permanent && firewall-cmd --reload" ;;
            esac
            ;;
        nft)
            case "$action" in
                allow) echo "nft add rule inet tt_filter input ${proto} dport ${port} accept" ;;
                deny) echo "nft add rule inet tt_filter input ${proto} dport ${port} drop" ;;
                delete) echo "tt firewall restore <backup_dir> 或 nft -a list ruleset 后按 handle 删除" ;;
            esac
            ;;
        iptables)
            local ipt_source=""
            [ -n "$source" ] && ipt_source="-s $source "
            case "$action" in
                allow) echo "iptables -I INPUT ${ipt_source}-p $proto --dport $port -j ACCEPT" ;;
                deny) echo "iptables -I INPUT ${ipt_source}-p $proto --dport $port -j DROP" ;;
                delete) echo "iptables -D INPUT ${ipt_source}-p $proto --dport $port -j ACCEPT" ;;
            esac
            ;;
        *) print_warn "没有可用防火墙后端。" ;;
    esac
    echo ""
    print_warn "执行写规则前，请确认 SSH 管理端口已放行，并准备好控制台/救援登录。"
}

firewall_backup() {
    print_header "防火墙备份"
    local dir
    dir="$(_firewall_backup)"
    print_success "已备份到: $dir"
    echo "$dir"
}

firewall_apply() {
    local action="${1:-allow}"
    local port="${2:-}"
    local proto="${3:-tcp}"
    local source="${4:-}"
    local assume_yes="${TT_ASSUME_YES:-false}"
    local backend backup_dir rc

    print_header "防火墙写入"
    _firewall_validate_change "$action" "$port" "$proto" "$source" || return 1
    check_root
    backend="$(_firewall_backend)"
    if [ "$backend" = "none" ]; then
        print_fail "未检测到 ufw/firewalld/nft/iptables，无法写入"
        return 1
    fi
    echo "后端: $backend"
    echo "动作: $action ${port}/${proto} ${source:+from $source}"
    if [ "$assume_yes" != "true" ]; then
        confirm "确认写入防火墙规则？" || { print_info "已取消"; return 0; }
    fi
    backup_dir="$(_firewall_backup)"
    print_success "写入前备份: $backup_dir"
    case "$backend" in
        ufw) _firewall_ufw_apply "$action" "$port" "$proto" "$source" ;;
        firewalld) _firewall_firewalld_apply "$action" "$port" "$proto" ;;
        nft) _firewall_nft_apply "$action" "$port" "$proto" "$source" ;;
        iptables) _firewall_iptables_apply "$action" "$port" "$proto" "$source" ;;
    esac
    rc=$?
    if [ "$rc" -eq 0 ]; then
        print_success "规则写入完成"
        echo "回滚命令: tt firewall restore $backup_dir"
        firewall_status | sed -n '1,80p'
    else
        print_fail "规则写入失败，建议执行: tt firewall restore $backup_dir"
    fi
    return "$rc"
}

firewall_restore() {
    local dir="${1:-}"
    print_header "防火墙回滚"
    check_root
    [ -n "$dir" ] || { print_fail "请指定备份目录"; echo "用法: tt firewall restore <backup_dir>"; return 1; }
    [ -d "$dir" ] || { print_fail "备份目录不存在: $dir"; return 1; }
    if [ -f "${dir}/nft.rules" ] && has_cmd nft; then
        nft flush ruleset
        nft -f "${dir}/nft.rules"
        print_success "已完整恢复 nft ruleset"
    fi
    if [ -f "${dir}/iptables.rules" ] && has_cmd iptables-restore; then
        iptables-restore < "${dir}/iptables.rules"
        print_success "已恢复 iptables ruleset"
    fi
    if [ -f "${dir}/ip6tables.rules" ] && has_cmd ip6tables-restore; then
        ip6tables-restore < "${dir}/ip6tables.rules"
        print_success "已恢复 ip6tables ruleset"
    fi
    if [ -f "${dir}/ufw-etc.tar.gz" ] && [ -d /etc/ufw ]; then
        tar -xzf "${dir}/ufw-etc.tar.gz" -C /etc
        has_cmd ufw && ufw reload >/dev/null 2>&1 || true
        print_success "已恢复 /etc/ufw 配置"
    fi
    if [ -f "${dir}/firewalld-etc.tar.gz" ] && [ -d /etc/firewalld ]; then
        tar -xzf "${dir}/firewalld-etc.tar.gz" -C /etc
        has_cmd firewall-cmd && firewall-cmd --reload >/dev/null 2>&1 || true
        print_success "已恢复 /etc/firewalld 配置"
    fi
    firewall_status | sed -n '1,80p'
}

firewall_menu() {
    while true; do
        echo ""
        print_title "防火墙管理"
        echo ""
        echo "  1) 查看防火墙状态 ✅"
        echo "  2) 查看监听端口 ✅"
        echo "  3) 生成规则变更预案 ✅"
        echo "  4) 写入规则（自动备份）⚠️"
        echo "  5) 备份当前规则 ✅"
        echo "  6) 从备份回滚 ⚠️"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/firewall> " choice
        case "$choice" in
            1) firewall_status ;;
            2) tools_ports ;;
            3)
                read -r -p "  动作 allow/deny/delete [allow]: " action
                read -r -p "  端口: " port
                read -r -p "  协议 tcp/udp [tcp]: " proto
                read -r -p "  来源 CIDR（可空）: " source
                firewall_plan "${action:-allow}" "$port" "${proto:-tcp}" "$source"
                ;;
            4)
                read -r -p "  动作 allow/deny/delete [allow]: " action
                read -r -p "  端口: " port
                read -r -p "  协议 tcp/udp [tcp]: " proto
                read -r -p "  来源 CIDR（可空）: " source
                firewall_apply "${action:-allow}" "$port" "${proto:-tcp}" "$source"
                ;;
            5) firewall_backup ;;
            6)
                read -r -p "  备份目录: " backup_dir
                firewall_restore "$backup_dir"
                ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
