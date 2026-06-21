#!/bin/bash
# =============================================================================
# TianTian Ops - cluster.sh
# Cluster/node control read-only scaffolding.
# =============================================================================

TT_CLUSTER_FILE="${TT_CLUSTER_FILE:-${TT_HOME}/state/cluster-nodes.txt}"

cluster_status() {
    print_header "集群 / 多节点状态"
    echo "配置文件: ${TT_CLUSTER_FILE}"
    echo ""

    if [ ! -f "$TT_CLUSTER_FILE" ]; then
        print_warn "尚未配置集群节点。"
        echo "格式示例："
        echo "  jp root@103.127.243.32 22 /root/.ssh/tt_jp_test_ed25519"
        echo ""
        echo "当前仅提供只读骨架；添加节点前请先确认 SSH key、用途和安全边界。"
        return 0
    fi

    local total=0 reachable=0
    while read -r name host port key rest; do
        [ -n "$name" ] || continue
        case "$name" in \#*) continue ;; esac
        total=$((total + 1))
        port="${port:-22}"
        printf "%-16s %-32s port=%s " "$name" "$host" "$port"
        if [ -n "$key" ] && [ -f "$key" ]; then
            if ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=5 -p "$port" "$host" 'hostname' >/tmp/tt-cluster-${name}.out 2>/dev/null; then
                reachable=$((reachable + 1))
                printf "✅ %s\n" "$(cat /tmp/tt-cluster-${name}.out 2>/dev/null)"
            else
                printf "⚠️ 不可达\n"
            fi
        else
            printf "⚠️ key 缺失或未配置\n"
        fi
    done < "$TT_CLUSTER_FILE"

    echo ""
    echo "节点总数: $total"
    echo "可达节点: $reachable"
}

cluster_menu() {
    while true; do
        echo ""
        print_title "集群控制（只读骨架）"
        echo ""
        echo "  1) 节点状态 ✅"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/cluster> " choice
        case "$choice" in
            1) cluster_status ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
