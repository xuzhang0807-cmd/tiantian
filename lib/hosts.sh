#!/bin/bash
# =============================================================================
# TianTian Ops - hosts.sh
# /etc/hosts 管理：只读查看、预案、备份、显式确认写入
# =============================================================================

TT_HOSTS_BACKUP_ROOT="${TT_HOSTS_BACKUP_ROOT:-${TT_BACKUP_ROOT}/hosts}"

_hosts_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$ip" =~ ^[0-9A-Fa-f:]+$ ]]
}

_hosts_valid_name() {
    local name="$1"
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]
}

hosts_list() {
    print_header "/etc/hosts 当前记录"
    if [ ! -f /etc/hosts ]; then
        print_fail "/etc/hosts 不存在"
        return 1
    fi
    nl -ba /etc/hosts | sed -n '1,120p'
}

hosts_backup() {
    local ts dest
    ts=$(date '+%Y%m%d-%H%M%S')
    dest="${TT_HOSTS_BACKUP_ROOT}/${ts}"
    mkdir -p "$dest"
    cp -a /etc/hosts "$dest/hosts"
    print_success "hosts 已备份: $dest/hosts"
}

hosts_plan_add() {
    local ip="$1" name="$2"
    [ -n "$ip" ] && [ -n "$name" ] || { echo "用法: tt hosts add-plan <ip> <name>"; return 1; }
    _hosts_valid_ip "$ip" || { print_fail "IP 格式不合法: $ip"; return 1; }
    _hosts_valid_name "$name" || { print_fail "主机名不合法: $name"; return 1; }
    print_header "新增 hosts 记录预案"
    echo "目标文件: /etc/hosts"
    echo "新增记录: $ip $name"
    if grep -Eq "(^|[[:space:]])${name}([[:space:]]|$)" /etc/hosts 2>/dev/null; then
        print_warn "已存在同名记录，建议先执行: tt hosts delete-plan $name"
        grep -nE "(^|[[:space:]])${name}([[:space:]]|$)" /etc/hosts || true
    fi
    echo
    echo "将执行："
    echo "  hosts_backup"
    echo "  printf '%s %s\\n' '$ip' '$name' >> /etc/hosts"
    print_warn "实际写入需执行: tt hosts add $ip $name --yes"
}

hosts_add() {
    local ip="$1" name="$2" yes="${3:-}"
    [ "$yes" = "--yes" ] || { hosts_plan_add "$ip" "$name"; return 1; }
    hosts_plan_add "$ip" "$name" || return 1
    check_root
    hosts_backup
    printf '%s %s\n' "$ip" "$name" >> /etc/hosts
    print_success "hosts 记录已新增: $ip $name"
}

hosts_plan_delete() {
    local name="$1"
    [ -n "$name" ] || { echo "用法: tt hosts delete-plan <name>"; return 1; }
    _hosts_valid_name "$name" || { print_fail "主机名不合法: $name"; return 1; }
    print_header "删除 hosts 记录预案"
    echo "目标文件: /etc/hosts"
    echo "匹配名称: $name"
    local matches
    matches=$(grep -nE "(^|[[:space:]])${name}([[:space:]]|$)" /etc/hosts 2>/dev/null || true)
    if [ -z "$matches" ]; then
        print_warn "未找到匹配记录"
    else
        echo "将删除以下行："
        echo "$matches"
    fi
    echo
    echo "将执行："
    echo "  hosts_backup"
    echo "  删除包含独立名称 $name 的 hosts 行"
    print_warn "实际删除需执行: tt hosts delete $name --yes"
}

hosts_delete() {
    local name="$1" yes="${2:-}"
    [ "$yes" = "--yes" ] || { hosts_plan_delete "$name"; return 1; }
    hosts_plan_delete "$name" || return 1
    check_root
    hosts_backup
    local tmp
    tmp=$(mktemp)
    grep -Ev "(^|[[:space:]])${name}([[:space:]]|$)" /etc/hosts > "$tmp" || true
    cat "$tmp" > /etc/hosts
    rm -f "$tmp"
    print_success "hosts 记录已删除: $name"
}

hosts_restore() {
    local backup_file="$1"
    [ -n "$backup_file" ] || { echo "用法: tt hosts restore <backup_file|backup_dir> --yes"; return 1; }
    local yes="${2:-}"
    [ "$yes" = "--yes" ] || { print_warn "实际恢复需执行: tt hosts restore $backup_file --yes"; return 1; }
    if [ -d "$backup_file" ]; then
        backup_file="$backup_file/hosts"
    fi
    [ -f "$backup_file" ] || { print_fail "备份文件不存在: $backup_file"; return 1; }
    check_root
    hosts_backup
    cp -a "$backup_file" /etc/hosts
    print_success "hosts 已恢复: $backup_file"
}

hosts_menu() {
    while true; do
        print_header "hosts 管理"
        echo "1) 查看 /etc/hosts"
        echo "2) 新增记录预案"
        echo "3) 新增记录（--yes）"
        echo "4) 删除记录预案"
        echo "5) 备份 hosts"
        echo "0) 返回"
        read -r -p "  tt/hosts> " choice
        case "$choice" in
            1) hosts_list ;;
            2) read -r -p "IP: " ip; read -r -p "名称: " name; hosts_plan_add "$ip" "$name" ;;
            3) read -r -p "IP: " ip; read -r -p "名称: " name; hosts_add "$ip" "$name" --yes ;;
            4) read -r -p "名称: " name; hosts_plan_delete "$name" ;;
            5) hosts_backup ;;
            0|q|Q) break ;;
            *) print_warn "无效选择" ;;
        esac
        echo
    done
}
