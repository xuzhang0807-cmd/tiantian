#!/bin/bash
# =============================================================================
# TianTian Ops - firewall.sh
# Firewall discovery and plan-only helpers.
# =============================================================================

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

    print_header "防火墙变更预案"
    echo "模式: 只生成计划，不执行任何防火墙写入。"
    echo ""

    case "$action" in
        allow|deny|delete) ;;
        *)
            print_fail "动作不支持: $action"
            echo "用法: tt firewall plan [allow|deny|delete] <port> [tcp|udp] [source_cidr]"
            return 1
            ;;
    esac
    if ! validate_port "$port"; then
        print_fail "端口不合法: ${port:-空}"
        echo "用法: tt firewall plan [allow|deny|delete] <port> [tcp|udp] [source_cidr]"
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

    print_title "当前状态（只读摘要）"
    if has_cmd ufw; then
        ufw status 2>/dev/null | sed -n '1,12p' || true
    elif has_cmd firewall-cmd; then
        firewall-cmd --state 2>/dev/null || true
        firewall-cmd --list-ports 2>/dev/null || true
    elif has_cmd nft; then
        nft list ruleset 2>/dev/null | sed -n '1,25p' || true
    elif has_cmd iptables; then
        iptables -S 2>/dev/null | sed -n '1,25p' || true
    else
        print_warn "未检测到 ufw/firewalld/nft/iptables，仍可查看通用备份建议。"
    fi
    echo ""

    print_title "执行前备份（建议先手动执行）"
    echo "mkdir -p /root/firewall-backups"
    echo "date_tag=\$(date +%Y%m%d_%H%M%S)"
    echo "command -v ufw >/dev/null && ufw status verbose > /root/firewall-backups/ufw-\${date_tag}.txt || true"
    echo "command -v nft >/dev/null && nft list ruleset > /root/firewall-backups/nft-\${date_tag}.rules || true"
    echo "command -v iptables-save >/dev/null && iptables-save > /root/firewall-backups/iptables-\${date_tag}.rules || true"
    echo "command -v ip6tables-save >/dev/null && ip6tables-save > /root/firewall-backups/ip6tables-\${date_tag}.rules || true"
    echo ""

    print_title "候选命令（未执行）"
    local target="${port}/${proto}"
    if has_cmd ufw; then
        if [ -n "$source" ]; then
            case "$action" in
                allow) echo "ufw allow from $source to any port $port proto $proto" ;;
                deny) echo "ufw deny from $source to any port $port proto $proto" ;;
                delete) echo "ufw delete allow from $source to any port $port proto $proto" ;;
            esac
        else
            echo "ufw $action $target"
        fi
    fi
    if has_cmd firewall-cmd; then
        case "$action" in
            allow) echo "firewall-cmd --add-port=$target --permanent && firewall-cmd --reload" ;;
            deny) echo "firewall-cmd --remove-port=$target --permanent && firewall-cmd --reload  # firewalld 常用做法是移除允许端口" ;;
            delete) echo "firewall-cmd --remove-port=$target --permanent && firewall-cmd --reload" ;;
        esac
    fi
    if has_cmd nft; then
        local nft_source=""
        [ -n "$source" ] && nft_source="ip saddr ${source} "
        echo "# nft: 建议按现有 table/chain 命名手动追加，先用 nft list ruleset 确认链名。"
        case "$action" in
            allow) echo "# 示例: nft add rule inet filter input ${nft_source}${proto} dport ${port} accept" ;;
            deny) echo "# 示例: nft add rule inet filter input ${nft_source}${proto} dport ${port} drop" ;;
            delete) echo "# 示例: nft delete rule ...  # nft 删除需按 handle，先运行 nft -a list ruleset" ;;
        esac
    elif has_cmd iptables; then
        local ipt_source=""
        [ -n "$source" ] && ipt_source="-s $source "
        case "$action" in
            allow) echo "iptables -I INPUT ${ipt_source}-p $proto --dport $port -j ACCEPT" ;;
            deny) echo "iptables -I INPUT ${ipt_source}-p $proto --dport $port -j DROP" ;;
            delete) echo "iptables -D INPUT ${ipt_source}-p $proto --dport $port -j ACCEPT  # 按实际规则调整" ;;
        esac
    fi
    echo ""
    print_warn "执行写规则前，请确认 SSH 管理端口已放行，并准备好控制台/救援登录。"
}

firewall_menu() {
    while true; do
        echo ""
        print_title "防火墙管理"
        echo ""
        echo "  1) 查看防火墙状态 ✅"
        echo "  2) 查看监听端口 ✅"
        echo "  3) 生成规则变更预案 ✅"
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
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
