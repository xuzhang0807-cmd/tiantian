#!/bin/bash
# =============================================================================
# TianTian Ops - cluster.sh
# Remote node inventory and controlled execution helpers.
# =============================================================================

TT_CLUSTER_FILE="${TT_CLUSTER_FILE:-${TT_HOME}/state/cluster-nodes.txt}"
TT_CLUSTER_TMP_ROOT="${TT_CLUSTER_TMP_ROOT:-/tmp/tt-cluster-run}"

_cluster_ensure_dir() {
    mkdir -p "$(dirname "$TT_CLUSTER_FILE")"
    [ -f "$TT_CLUSTER_FILE" ] || touch "$TT_CLUSTER_FILE"
    chmod 600 "$TT_CLUSTER_FILE" 2>/dev/null || true
}

_cluster_valid_name() {
    [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]
}

_cluster_find() {
    local wanted="$1" node_name node_host node_port node_key node_rest
    [ -f "$TT_CLUSTER_FILE" ] || return 1
    while read -r node_name node_host node_port node_key node_rest || [ -n "$node_name" ]; do
        [ -n "$node_name" ] || continue
        case "$node_name" in \#*) continue ;; esac
        if [ "$node_name" = "$wanted" ]; then
            printf '%s\t%s\t%s\t%s\n' "$node_name" "$node_host" "${node_port:-22}" "$node_key"
            return 0
        fi
    done < "$TT_CLUSTER_FILE"
    return 1
}

_cluster_ssh_base() {
    local port="$1" key="$2"
    local opts=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -p "$port")
    [ -n "$key" ] && opts=(-i "$key" "${opts[@]}")
    printf '%q ' "${opts[@]}"
}

cluster_list() {
    print_header "远程节点列表"
    echo "配置文件: ${TT_CLUSTER_FILE}"
    echo ""
    if [ ! -s "$TT_CLUSTER_FILE" ]; then
        print_warn "尚未配置节点。"
        echo "添加示例: tt cluster add jp root@1.2.3.4 22 /root/.ssh/tt_jp_test_ed25519"
        return 0
    fi
    printf '%-16s %-32s %-8s %s\n' "名称" "主机" "端口" "Key"
    while read -r name host port key rest; do
        [ -n "$name" ] || continue
        case "$name" in \#*) continue ;; esac
        printf '%-16s %-32s %-8s %s\n' "$name" "$host" "${port:-22}" "${key:-default}"
    done < "$TT_CLUSTER_FILE"
}

cluster_add() {
    local name="$1" host="$2" port="${3:-22}" key="${4:-}"
    print_header "添加远程节点"
    _cluster_ensure_dir
    _cluster_valid_name "$name" || { print_fail "节点名称不合法，只能用字母数字 ._-"; return 1; }
    [ -n "$host" ] || { print_fail "请指定 SSH 主机，例如 root@1.2.3.4"; return 1; }
    validate_port "$port" || { print_fail "端口不合法: $port"; return 1; }
    if [ -n "$key" ] && [ ! -f "$key" ]; then
        print_fail "SSH key 不存在: $key"
        return 1
    fi
    if _cluster_find "$name" >/dev/null; then
        print_fail "节点已存在: $name"
        return 1
    fi
    printf '%s %s %s %s\n' "$name" "$host" "$port" "$key" >> "$TT_CLUSTER_FILE"
    chmod 600 "$TT_CLUSTER_FILE" 2>/dev/null || true
    print_success "已添加节点: $name"
    cluster_status
}

cluster_remove() {
    local name="$1" tmp
    print_header "删除远程节点"
    [ -n "$name" ] || { print_fail "请指定节点名称"; return 1; }
    [ -f "$TT_CLUSTER_FILE" ] || { print_warn "节点文件不存在"; return 0; }
    tmp="${TT_CLUSTER_FILE}.tmp"
    awk -v n="$name" '($1==n){next} {print}' "$TT_CLUSTER_FILE" > "$tmp"
    mv "$tmp" "$TT_CLUSTER_FILE"
    chmod 600 "$TT_CLUSTER_FILE" 2>/dev/null || true
    print_success "已删除节点: $name"
}

cluster_status() {
    print_header "集群 / 多节点状态"
    echo "配置文件: ${TT_CLUSTER_FILE}"
    echo ""

    if [ ! -f "$TT_CLUSTER_FILE" ]; then
        print_warn "尚未配置集群节点。"
        echo "格式示例："
        echo "  jp root@103.127.243.32 22 /root/.ssh/tt_jp_test_ed25519"
        return 0
    fi

    local total=0 reachable=0
    while read -r name host port key rest; do
        [ -n "$name" ] || continue
        case "$name" in \#*) continue ;; esac
        total=$((total + 1))
        port="${port:-22}"
        printf "%-16s %-32s port=%s " "$name" "$host" "$port"
        if [ -n "$key" ] && [ ! -f "$key" ]; then
            printf "⚠️ key 缺失\n"
            continue
        fi
        if ssh $(_cluster_ssh_base "$port" "$key") "$host" 'hostname' >/tmp/tt-cluster-${name}.out 2>/dev/null; then
            reachable=$((reachable + 1))
            printf "✅ %s\n" "$(cat /tmp/tt-cluster-${name}.out 2>/dev/null)"
        else
            printf "⚠️ 不可达\n"
        fi
    done < "$TT_CLUSTER_FILE"

    echo ""
    echo "节点总数: $total"
    echo "可达节点: $reachable"
}

cluster_run() {
    local name="$1"
    shift || true
    local cmd="$*" row host port key
    print_header "远程节点执行"
    [ -n "$name" ] || { print_fail "请指定节点名称"; echo "用法: tt cluster run <name> <command>"; return 1; }
    [ -n "$cmd" ] || { print_fail "请指定远程命令"; echo "用法: tt cluster run <name> <command>"; return 1; }
    row="$(_cluster_find "$name")" || { print_fail "节点不存在: $name"; return 1; }
    IFS=$'\t' read -r _ host port key <<< "$row"
    print_info "${name} → ${host}:${port}"
    ssh $(_cluster_ssh_base "$port" "$key") "$host" "$cmd"
}

cluster_copy() {
    local name="$1" src="$2" dest="$3" row host port key
    print_header "远程节点复制"
    [ -n "$name" ] && [ -n "$src" ] && [ -n "$dest" ] || { echo "用法: tt cluster copy <name> <local_path> <remote_path>"; return 1; }
    [ -e "$src" ] || { print_fail "本地路径不存在: $src"; return 1; }
    row="$(_cluster_find "$name")" || { print_fail "节点不存在: $name"; return 1; }
    IFS=$'\t' read -r _ host port key <<< "$row"
    local scp_opts=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -P "$port")
    [ -n "$key" ] && scp_opts=(-i "$key" "${scp_opts[@]}")
    scp "${scp_opts[@]}" -r "$src" "${host}:${dest}"
    print_success "复制完成: $src → ${name}:${dest}"
}

cluster_tt_selftest() {
    local name="$1" row host port key archive remote_root remote_archive
    print_header "远程 TT 自测"
    [ -n "$name" ] || { print_fail "请指定节点名称"; echo "用法: tt cluster tt-selftest <name>"; return 1; }
    row="$(_cluster_find "$name")" || { print_fail "节点不存在: $name"; return 1; }
    IFS=$'\t' read -r _ host port key <<< "$row"
    archive="/tmp/tt-cluster-current-$$.tar.gz"
    remote_root="${TT_CLUSTER_TMP_ROOT}-${name}-$$"
    remote_archive="/tmp/tt-cluster-current-$$.tar.gz"
    tar --exclude .git --exclude logs --exclude 'state/firewall-backups' -czf "$archive" -C "$TT_HOME" .
    ssh $(_cluster_ssh_base "$port" "$key") "$host" "rm -rf '$remote_root' '$remote_archive'; mkdir -p '$remote_root'"
    cluster_copy "$name" "$archive" "$remote_archive" >/dev/null
    rm -f "$archive"
    ssh $(_cluster_ssh_base "$port" "$key") "$host" "tar -xzf '$remote_archive' -C '$remote_root' && TT_HOME='$remote_root' bash '$remote_root/tiantian.sh' selftest; rc=\$?; rm -rf '$remote_root' '$remote_archive'; exit \$rc"
}

cluster_menu() {
    while true; do
        echo ""
        print_title "集群 / 远程节点控制"
        echo ""
        echo "  1) 节点状态 ✅"
        echo "  2) 节点列表 ✅"
        echo "  3) 添加节点 ⚠️"
        echo "  4) 删除节点 ⚠️"
        echo "  5) 执行远程命令 ⚠️"
        echo "  6) 复制文件到节点 ⚠️"
        echo "  7) 上传临时 TT 并自测 ✅"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/cluster> " choice
        case "$choice" in
            1) cluster_status ;;
            2) cluster_list ;;
            3)
                read -r -p "  名称: " name
                read -r -p "  SSH 主机(root@ip): " host
                read -r -p "  端口 [22]: " port
                read -r -p "  SSH key路径（可空）: " key
                cluster_add "$name" "$host" "${port:-22}" "$key"
                ;;
            4)
                read -r -p "  名称: " name
                cluster_remove "$name"
                ;;
            5)
                read -r -p "  名称: " name
                read -r -p "  命令: " cmd
                cluster_run "$name" "$cmd"
                ;;
            6)
                read -r -p "  名称: " name
                read -r -p "  本地路径: " src
                read -r -p "  远端路径: " dest
                cluster_copy "$name" "$src" "$dest"
                ;;
            7)
                read -r -p "  名称: " name
                cluster_tt_selftest "$name"
                ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
