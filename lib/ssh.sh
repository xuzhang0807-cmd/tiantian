#!/bin/bash
# =============================================================================
# TianTian Ops - ssh.sh
# SSH hardening planner/writer. Defaults are plan-first; writes require --yes.
# =============================================================================

TT_SSH_BACKUP_ROOT="${TT_SSH_BACKUP_ROOT:-${TT_BACKUP_ROOT}/ssh}"
TT_SSH_DROPIN="${TT_SSH_DROPIN:-/etc/ssh/sshd_config.d/99-tt-hardening.conf}"

_ssh_service_name() {
    if has_cmd systemctl; then
        if systemctl list-unit-files ssh.service --no-legend 2>/dev/null | grep -q .; then
            echo ssh
            return 0
        fi
        if systemctl list-unit-files sshd.service --no-legend 2>/dev/null | grep -q .; then
            echo sshd
            return 0
        fi
    fi
    if service ssh status >/dev/null 2>&1; then
        echo ssh
    else
        echo sshd
    fi
}

_ssh_validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

_ssh_restart_or_reload() {
    local service_name
    service_name="$(_ssh_service_name)"
    if has_cmd systemctl; then
        systemctl reload "$service_name" 2>/dev/null || systemctl restart "$service_name"
    else
        service "$service_name" reload 2>/dev/null || service "$service_name" restart
    fi
}

_ssh_config_test() {
    if has_cmd sshd; then
        sshd -t
    elif [ -x /usr/sbin/sshd ]; then
        /usr/sbin/sshd -t
    else
        print_warn "未找到 sshd，跳过配置语法验证"
        return 0
    fi
}

ssh_harden_plan() {
    local port="${1:-22}"
    print_header "SSH 加固预案"
    if ! _ssh_validate_port "$port"; then
        print_fail "SSH 端口不合法: $port"
        return 1
    fi

    print_title "当前 SSH 状态"
    ops_ssh_status || true
    echo ""

    print_title "计划写入文件"
    echo "$TT_SSH_DROPIN"
    echo ""

    print_title "计划内容"
    cat <<EOF
Port ${port}
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
EOF
    echo ""
    print_warn "执行前必须确认当前会话可用公钥登录；改错端口/禁密码可能锁死 SSH。"
    print_info "真实执行: tt ssh harden-write ${port} --yes"
}

ssh_backup() {
    print_header "SSH 配置备份"
    local backup_dir="${TT_SSH_BACKUP_ROOT}/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    [ -f /etc/ssh/sshd_config ] && cp -a /etc/ssh/sshd_config "$backup_dir/sshd_config"
    if [ -d /etc/ssh/sshd_config.d ]; then
        mkdir -p "$backup_dir/sshd_config.d"
        cp -a /etc/ssh/sshd_config.d/. "$backup_dir/sshd_config.d/" 2>/dev/null || true
    fi
    ops_ssh_status > "$backup_dir/ssh-status.txt" 2>&1 || true
    print_success "SSH 配置已备份: $backup_dir"
}

ssh_harden_write() {
    local port="${1:-22}" yes="${2:-}"
    print_header "SSH 加固写入"
    if ! _ssh_validate_port "$port"; then
        print_fail "SSH 端口不合法: $port"
        return 1
    fi
    if [ "$yes" != "--yes" ]; then
        print_warn "将写入 SSH drop-in 并重载 SSH 服务。"
        confirm "确认当前公钥登录可用并继续加固 SSH？" || { print_info "已取消"; return 0; }
    fi

    local backup_dir
    backup_dir="$(ssh_backup | awk '/SSH 配置已备份:/ {print $NF}' | tail -n1)"
    [ -n "$backup_dir" ] || { print_fail "SSH 备份失败，停止写入"; return 1; }

    mkdir -p "$(dirname "$TT_SSH_DROPIN")"
    cat > "$TT_SSH_DROPIN" <<EOF
# Managed by TianTian Ops. Restore with: tt ssh restore <backup_dir>
Port ${port}
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
EOF
    chmod 0644 "$TT_SSH_DROPIN"

    if ! _ssh_config_test; then
        print_fail "SSH 配置语法失败，自动回滚"
        ssh_restore "$backup_dir"
        return 1
    fi

    _ssh_restart_or_reload
    print_success "SSH 已加固并重载；备份路径: $backup_dir"
    ops_ssh_status || true
}

ssh_restore() {
    local backup_dir="$1"
    print_header "SSH 配置回滚"
    [ -n "$backup_dir" ] || { print_fail "请指定备份目录"; return 1; }
    [ -d "$backup_dir" ] || { print_fail "备份目录不存在: $backup_dir"; return 1; }

    if [ -f "$backup_dir/sshd_config" ]; then
        cp -a "$backup_dir/sshd_config" /etc/ssh/sshd_config
    fi
    if [ -d "$backup_dir/sshd_config.d" ]; then
        mkdir -p /etc/ssh/sshd_config.d
        find /etc/ssh/sshd_config.d -maxdepth 1 -type f -name '*.conf' -delete 2>/dev/null || true
        cp -a "$backup_dir/sshd_config.d/." /etc/ssh/sshd_config.d/ 2>/dev/null || true
    else
        rm -f "$TT_SSH_DROPIN"
    fi

    if ! _ssh_config_test; then
        print_fail "回滚后的 SSH 配置语法仍失败，请人工检查: $backup_dir"
        return 1
    fi
    _ssh_restart_or_reload
    print_success "SSH 配置已回滚: $backup_dir"
}

ssh_menu() {
    while true; do
        echo ""
        print_title "SSH 管理"
        echo ""
        echo "  1) SSH 状态 ✅"
        echo "  2) SSH 加固预案 ✅"
        echo "  3) 备份 SSH 配置 ✅"
        echo "  4) 写入 SSH 加固 ⚠️"
        echo "  5) 回滚 SSH 配置 ⚠️"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/ssh> " choice
        case "$choice" in
            1) ops_ssh_status ;;
            2) read -r -p "  SSH 端口 [22]: " port; ssh_harden_plan "${port:-22}" ;;
            3) ssh_backup ;;
            4) read -r -p "  SSH 端口 [22]: " port; ssh_harden_write "${port:-22}" ;;
            5) read -r -p "  备份目录: " backup_dir; ssh_restore "$backup_dir" ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
