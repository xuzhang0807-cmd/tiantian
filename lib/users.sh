#!/bin/bash
# =============================================================================
# TianTian Ops - users.sh
# 系统用户管理：只读巡检、创建/锁定/删除预案、显式确认写入
# =============================================================================

TT_USER_BACKUP_ROOT="${TT_USER_BACKUP_ROOT:-${TT_BACKUP_ROOT}/system-users}"

_users_valid_name() {
    local name="$1"
    [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

_users_sudo_group() {
    if getent group sudo >/dev/null 2>&1; then
        echo "sudo"
    elif getent group wheel >/dev/null 2>&1; then
        echo "wheel"
    else
        echo ""
    fi
}

_users_home_size() {
    local home="$1"
    if [ -d "$home" ] && has_cmd du; then
        du -sh "$home" 2>/dev/null | awk '{print $1}'
    else
        echo "-"
    fi
}

users_list() {
    print_header "系统用户概览"
    printf "%-20s %-7s %-7s %-22s %-18s %-8s %-8s\n" "用户名" "UID" "GID" "HOME" "SHELL" "sudo" "家目录"
    awk -F: '$3 == 0 || $3 >= 1000 {print $1":"$3":"$4":"$6":"$7}' /etc/passwd | while IFS=: read -r username uid gid home shell; do
        [ -n "$username" ] || continue
        local sudo_status="no"
        if id -nG "$username" 2>/dev/null | tr ' ' '\n' | grep -Eq '^(sudo|wheel)$'; then
            sudo_status="group"
        elif [ -f "/etc/sudoers.d/$username" ]; then
            sudo_status="file"
        elif grep -Eq "^[[:space:]]*${username}[[:space:]]+ALL=" /etc/sudoers 2>/dev/null; then
            sudo_status="sudoers"
        fi
        printf "%-20s %-7s %-7s %-22s %-18s %-8s %-8s\n" "$username" "$uid" "$gid" "$home" "$shell" "$sudo_status" "$(_users_home_size "$home")"
    done
    echo
    print_info "锁定状态"
    passwd -S root 2>/dev/null | awk '{print "  root: "$2}' || true
    awk -F: '$3 >= 1000 {print $1}' /etc/passwd | head -n 20 | while read -r username; do
        passwd -S "$username" 2>/dev/null | awk -v u="$username" '{print "  "u": "$2}' || true
    done
}

users_plan_create() {
    local username="$1"
    local mode="${2:-normal}"
    [ -n "$username" ] || { echo "用法: tt users create-plan <username> [normal|sudo]"; return 1; }
    _users_valid_name "$username" || { print_fail "用户名不合法：仅支持小写字母、数字、_、-，且需以字母或 _ 开头"; return 1; }
    if id "$username" >/dev/null 2>&1; then
        print_fail "用户已存在: $username"
        return 1
    fi
    local sudo_group="$(_users_sudo_group)"
    print_header "创建用户预案"
    echo "用户: $username"
    echo "模式: $mode"
    echo "家目录: /home/$username"
    echo "登录 shell: /bin/bash"
    echo "密码状态: 创建后锁定密码，仅保留密钥/后续手动设置密码路径"
    echo "sudo: $([ "$mode" = "sudo" ] && echo "加入 ${sudo_group:-sudo/wheel 未检测到，需先安装/配置 sudo}" || echo "不授予")"
    echo
    echo "将执行："
    echo "  useradd -m -s /bin/bash $username"
    [ "$mode" = "sudo" ] && [ -n "$sudo_group" ] && echo "  usermod -aG $sudo_group $username"
    echo "  passwd -l $username"
    echo
    print_warn "实际创建需执行: tt users create $username $mode --yes"
}

users_backup() {
    local ts dest
    ts=$(date '+%Y%m%d-%H%M%S')
    dest="${TT_USER_BACKUP_ROOT}/${ts}"
    mkdir -p "$dest"
    for file in /etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/sudoers; do
        [ -e "$file" ] && cp -a "$file" "$dest/"
    done
    if [ -d /etc/sudoers.d ]; then
        mkdir -p "$dest/sudoers.d"
        cp -a /etc/sudoers.d/. "$dest/sudoers.d/" 2>/dev/null || true
    fi
    print_success "用户/权限配置已备份: $dest"
}

users_create() {
    local username="$1"
    local mode="${2:-normal}"
    local yes="${3:-}"
    [ "$yes" = "--yes" ] || { users_plan_create "$username" "$mode"; return 1; }
    [ "$mode" = "normal" ] || [ "$mode" = "sudo" ] || { print_fail "模式仅支持 normal|sudo"; return 1; }
    users_plan_create "$username" "$mode" || return 1
    check_root
    users_backup
    useradd -m -s /bin/bash "$username"
    if [ "$mode" = "sudo" ]; then
        local sudo_group="$(_users_sudo_group)"
        [ -n "$sudo_group" ] || die "未检测到 sudo/wheel 组，已停止创建 sudo 权限"
        usermod -aG "$sudo_group" "$username"
    fi
    passwd -l "$username" >/dev/null 2>&1 || true
    print_success "用户已创建并锁定密码: $username"
}

users_plan_lock() {
    local username="$1"
    [ -n "$username" ] || { echo "用法: tt users lock-plan <username>"; return 1; }
    id "$username" >/dev/null 2>&1 || { print_fail "用户不存在: $username"; return 1; }
    print_header "锁定用户预案"
    echo "用户: $username"
    echo "将执行: passwd -l $username"
    print_warn "实际锁定需执行: tt users lock $username --yes"
}

users_lock() {
    local username="$1"
    local yes="${2:-}"
    [ "$yes" = "--yes" ] || { users_plan_lock "$username"; return 1; }
    users_plan_lock "$username" || return 1
    check_root
    users_backup
    passwd -l "$username"
    print_success "用户已锁定: $username"
}

users_plan_delete() {
    local username="$1"
    [ -n "$username" ] || { echo "用法: tt users delete-plan <username>"; return 1; }
    id "$username" >/dev/null 2>&1 || { print_fail "用户不存在: $username"; return 1; }
    [ "$username" != "root" ] || { print_fail "禁止删除 root"; return 1; }
    local home
    home=$(getent passwd "$username" | awk -F: '{print $6}')
    print_header "删除用户预案"
    echo "用户: $username"
    echo "家目录: $home"
    echo "家目录大小: $(_users_home_size "$home")"
    echo "将执行："
    echo "  users_backup"
    echo "  userdel -r $username"
    echo "  rm -f /etc/sudoers.d/$username"
    print_warn "会删除用户家目录；实际删除需执行: tt users delete $username --yes"
}

users_delete() {
    local username="$1"
    local yes="${2:-}"
    [ "$yes" = "--yes" ] || { users_plan_delete "$username"; return 1; }
    users_plan_delete "$username" || return 1
    check_root
    users_backup
    rm -f "/etc/sudoers.d/$username" 2>/dev/null || true
    local err_file
    err_file=$(mktemp)
    if userdel -r "$username" 2>"$err_file"; then
        grep -v 'mail spool .* not found' "$err_file" >&2 || true
        rm -f "$err_file"
        print_success "用户已删除: $username"
    else
        cat "$err_file" >&2
        rm -f "$err_file"
        return 1
    fi
}

users_menu() {
    while true; do
        print_header "用户管理"
        echo "1) 用户列表"
        echo "2) 创建用户预案"
        echo "3) 创建用户（--yes）"
        echo "4) 锁定用户预案"
        echo "5) 删除用户预案"
        echo "0) 返回"
        read -r -p "  tt/users> " choice
        case "$choice" in
            1) users_list ;;
            2) read -r -p "用户名: " username; read -r -p "模式 normal|sudo: " mode; users_plan_create "$username" "${mode:-normal}" ;;
            3) read -r -p "用户名: " username; read -r -p "模式 normal|sudo: " mode; users_create "$username" "${mode:-normal}" --yes ;;
            4) read -r -p "用户名: " username; users_plan_lock "$username" ;;
            5) read -r -p "用户名: " username; users_plan_delete "$username" ;;
            0|q|Q) break ;;
            *) print_warn "无效选择" ;;
        esac
        echo
    done
}
