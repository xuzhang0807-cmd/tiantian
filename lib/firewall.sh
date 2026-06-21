#!/bin/bash
# =============================================================================
# TianTian Ops - firewall.sh
# Firewall discovery and read-only status helpers.
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

firewall_menu() {
    while true; do
        echo ""
        print_title "防火墙管理"
        echo ""
        echo "  1) 查看防火墙状态 ✅"
        echo "  2) 查看监听端口 ✅"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/firewall> " choice
        case "$choice" in
            1) firewall_status ;;
            2) tools_ports ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
