#!/bin/bash
# =============================================================================
# TianTian Ops - ops.sh
# SSH / DNS / cron / kernel status helpers. Default commands are read-only.
# =============================================================================

ops_ssh_status() {
    print_header "SSH 安全状态"
    local sshd_config="/etc/ssh/sshd_config"
    local sshd_dropin="/etc/ssh/sshd_config.d"

    print_title "监听状态"
    if has_cmd ss; then
        ss -ltnp 2>/dev/null | awk 'NR==1 || /:(22|2222|2022|8022)\b/ || /sshd/' || true
    else
        print_warn "缺少 ss，无法读取监听端口"
    fi
    echo ""

    print_title "服务状态"
    if has_cmd systemctl; then
        systemctl is-active ssh 2>/dev/null | sed 's/^/ssh: /' || true
        systemctl is-active sshd 2>/dev/null | sed 's/^/sshd: /' || true
    else
        ps -eo pid,comm,args | grep -E '[s]shd' | sed -n '1,8p' || true
    fi
    echo ""

    print_title "关键配置"
    if [ -f "$sshd_config" ]; then
        grep -Ei '^[[:space:]]*(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AuthorizedKeysFile|AllowUsers|DenyUsers)\b' "$sshd_config" 2>/dev/null || print_info "主配置未显式设置关键项"
    else
        print_warn "未找到 $sshd_config"
    fi
    if [ -d "$sshd_dropin" ]; then
        find "$sshd_dropin" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort | while read -r cfg; do
            echo "-- $cfg"
            grep -Ei '^[[:space:]]*(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AuthorizedKeysFile|AllowUsers|DenyUsers)\b' "$cfg" 2>/dev/null || true
        done
    fi
    echo ""

    print_title "authorized_keys 概览"
    local ak="${HOME}/.ssh/authorized_keys"
    if [ -f "$ak" ]; then
        local count
        count="$(grep -Ec '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$ak" 2>/dev/null || true)"
        echo "${ak}: ${count} 条公钥"
        awk '/^[[:space:]]*(ssh-|ecdsa-|sk-)/ {comment=""; if (NF>2) comment=$NF; print "  - "$1" "substr($2,1,18)"... "comment}' "$ak" 2>/dev/null | sed -n '1,20p'
        local duplicates
        duplicates="$(awk '/^[[:space:]]*(ssh-|ecdsa-|sk-)/ {count[$2]++} END {for (key in count) if (count[key] > 1) print substr(key,1,18)"... x"count[key]}' "$ak" 2>/dev/null)"
        if [ -n "$duplicates" ]; then
            print_warn "发现重复 SSH 公钥："
            printf '%s\n' "$duplicates" | sed 's/^/  - /'
        fi
    else
        print_warn "未找到 ${ak}"
    fi
    echo ""

    print_title "最近 SSH 失败日志"
    if has_cmd journalctl; then
        journalctl -u ssh -u sshd --since '24 hours ago' --no-pager 2>/dev/null | grep -Ei 'failed|invalid|disconnect|refused|authentication failure' | tail -n 12 || true
    else
        grep -Eih 'failed|invalid|authentication failure' /var/log/auth.log /var/log/secure 2>/dev/null | tail -n 12 || true
    fi
}

ops_dns_status() {
    print_header "DNS / 解析诊断"
    print_title "本机 DNS 配置"
    sed -n '1,20p' /etc/resolv.conf 2>/dev/null || print_warn "无法读取 /etc/resolv.conf"
    echo ""

    print_title "hosts 关键记录"
    grep -Ev '^[[:space:]]*(#|$)' /etc/hosts 2>/dev/null | sed -n '1,20p' || true
    echo ""

    print_title "解析测试"
    local domains=(github.com google.com cloudflare.com kazerush.xyz)
    for domain in "${domains[@]}"; do
        if has_cmd getent && getent ahosts "$domain" >/tmp/tt-dns-getent.$$ 2>/dev/null; then
            printf '%-18s %s\n' "$domain" "$(awk 'NR==1{print $1}' /tmp/tt-dns-getent.$$)"
        elif has_cmd nslookup; then
            printf '%-18s ' "$domain"
            nslookup "$domain" 2>/dev/null | awk '/^Address: / {print $2; found=1; exit} END {if(!found) print "failed"}'
        else
            printf '%-18s %s\n' "$domain" "缺少 getent/nslookup"
        fi
        rm -f /tmp/tt-dns-getent.$$ 2>/dev/null || true
    done
}

ops_cron_status() {
    print_header "定时任务状态"
    print_title "当前用户 crontab"
    crontab -l 2>/dev/null | sed -n '1,80p' || print_info "当前用户无 crontab 或 crontab 不可用"
    echo ""

    print_title "系统 cron 目录"
    for target in /etc/crontab /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
        if [ -e "$target" ]; then
            if [ -d "$target" ]; then
                echo "-- $target"
                find "$target" -maxdepth 1 -type f -printf '  %f\n' 2>/dev/null | sort | sed -n '1,40p'
            else
                echo "-- $target"
                sed -n '1,40p' "$target" 2>/dev/null || true
            fi
        fi
    done
    echo ""

    print_title "systemd timers"
    if has_cmd systemctl; then
        systemctl list-timers --all --no-pager 2>/dev/null | sed -n '1,30p' || true
    else
        print_warn "缺少 systemctl"
    fi
}

ops_bbr_status() {
    print_header "BBR / TCP 状态"
    echo "内核: $(uname -r)"
    echo "拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    echo "可用算法: $(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)"
    echo "默认队列: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
    echo ""
    print_title "BBR 模块"
    if lsmod 2>/dev/null | grep -q '^tcp_bbr'; then
        lsmod | grep '^tcp_bbr'
    else
        print_info "未见 tcp_bbr 模块；部分内核可能内建或未启用。"
    fi
    echo ""
    print_warn "本命令只读；开启/更换 BBR 可能涉及内核和重启，TT 暂不自动执行。"
}

ops_process_status() {
    print_header "进程 / 负载状态"
    print_title "系统负载"
    uptime 2>/dev/null || true
    echo ""
    print_title "CPU 占用 Top"
    ps -eo pid,ppid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | sed -n '1,12p' || true
    echo ""
    print_title "内存占用 Top"
    ps -eo pid,ppid,comm,%mem,%cpu --sort=-%mem 2>/dev/null | sed -n '1,12p' || true
    echo ""
    print_title "僵尸进程"
    local zombies
    zombies="$(ps -eo stat,pid,ppid,comm 2>/dev/null | awk '$1 ~ /Z/ {print}' | sed -n '1,20p')"
    if [ -n "$zombies" ]; then
        printf '%s\n' "$zombies"
        print_warn "发现僵尸进程，通常需要检查父进程或相关服务。"
    else
        print_success "未发现僵尸进程"
    fi
}

ops_disk_status() {
    print_header "磁盘 / 大目录状态"
    local mounts=(/ /home /tmp /var /var/lib/docker)
    local seen_mounts=() unique_mounts=() target mount
    for target in "${mounts[@]}"; do
        [ -e "$target" ] || continue
        mount="$(df -P "$target" 2>/dev/null | awk 'NR==2{print $6}')"
        [ -n "$mount" ] || continue
        local duplicate="false"
        for existing in "${seen_mounts[@]}"; do
            [ "$existing" = "$mount" ] && duplicate="true"
        done
        if [ "$duplicate" = "false" ]; then
            seen_mounts+=("$mount")
            unique_mounts+=("$target")
        fi
    done
    [ "${#unique_mounts[@]}" -gt 0 ] || unique_mounts=(/)

    print_title "文件系统"
    df -hT "${unique_mounts[@]}" 2>/dev/null || df -hT 2>/dev/null || true
    echo ""
    print_title "inode 使用"
    df -ih "${unique_mounts[@]}" 2>/dev/null || df -ih 2>/dev/null || true
    echo ""
    print_title "常见目录占用"
    for target in /home /opt /var/log /var/lib/docker /tmp "$TT_HOME"; do
        [ -e "$target" ] || continue
        du -sh "$target" 2>/dev/null | sed 's/^/  /'
    done
    echo ""
    print_title "最大日志文件"
    find /var/log "$TT_HOME/logs" -type f -size +1M -printf '%s %p\n' 2>/dev/null | sort -nr | head -n 10 | awk '{size=$1; $1=""; printf "  %.1fM%s\n", size/1024/1024, $0}' || true
}

ops_services_status() {
    print_header "系统服务状态"
    local services=(ssh sshd docker nginx cron crond certbot fail2ban nftables ufw)
    if has_cmd systemctl; then
        printf '%-14s %-10s %-10s\n' "service" "active" "enabled"
        for service in "${services[@]}"; do
            if systemctl list-unit-files "${service}.service" --no-legend 2>/dev/null | grep -q .; then
                local active enabled
                active="$(systemctl is-active "$service" 2>/dev/null || true)"
                enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
                printf '%-14s %-10s %-10s\n' "$service" "${active:-n/a}" "${enabled:-n/a}"
            fi
        done
        echo ""
        print_title "失败服务"
        systemctl --failed --no-pager 2>/dev/null || true
    else
        print_warn "缺少 systemctl，退化为进程检查"
        ps -eo pid,comm,args | grep -E '[s]shd|[d]ockerd|[n]ginx|[c]ron|[f]ail2ban' | sed -n '1,30p' || true
    fi
}

ops_tmux_status() {
    print_header "后台工作区 / tmux 状态"
    if ! has_cmd tmux; then
        print_warn "tmux 未安装；可用 deps/tools 安装后再创建常驻工作区。"
        return 0
    fi
    print_title "tmux sessions"
    tmux list-sessions 2>/dev/null || print_info "当前没有 tmux session"
    echo ""
    print_title "tmux 进程"
    ps -eo pid,comm,args | grep -E '[t]mux' | sed -n '1,20p' || true
}

ops_menu() {
    while true; do
        echo ""
        print_title "常用运维"
        echo ""
        echo "  1) SSH 安全状态 ✅"
        echo "  2) DNS / 解析诊断 ✅"
        echo "  3) 定时任务状态 ✅"
        echo "  4) BBR / TCP 状态 ✅"
        echo "  5) 进程 / 负载状态 ✅"
        echo "  6) 磁盘 / 大目录状态 ✅"
        echo "  7) 系统服务状态 ✅"
        echo "  8) 后台工作区 / tmux 状态 ✅"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/ops> " choice
        case "$choice" in
            1) ops_ssh_status ;;
            2) ops_dns_status ;;
            3) ops_cron_status ;;
            4) ops_bbr_status ;;
            5) ops_process_status ;;
            6) ops_disk_status ;;
            7) ops_services_status ;;
            8) ops_tmux_status ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
