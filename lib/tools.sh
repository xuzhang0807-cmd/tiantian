#!/bin/bash
# =============================================================================
# TianTian Ops - tools.sh
# Terminal-first server toolbox inspired by mature numeric-menu scripts.
# =============================================================================

_tools_pkg_manager() {
    if has_cmd apt-get; then echo apt; return 0; fi
    if has_cmd dnf; then echo dnf; return 0; fi
    if has_cmd yum; then echo yum; return 0; fi
    if has_cmd apk; then echo apk; return 0; fi
    echo unknown
}

_tools_install_pkg() {
    local pkg="$1" pm
    pm="$(_tools_pkg_manager)"
    check_root
    case "$pm" in
        apt)
            apt-get update
            apt-get install -y "$pkg"
            ;;
        dnf) dnf install -y "$pkg" ;;
        yum) yum install -y "$pkg" ;;
        apk) apk add --no-cache "$pkg" ;;
        *) die "未识别包管理器，请手动安装: $pkg" ;;
    esac
}

tools_resource() {
    print_header "资源概览"
    echo "系统: $(uname -a)"
    echo "运行时间: $(uptime -p 2>/dev/null || uptime)"
    echo ""
    print_title "CPU / 负载"
    nproc 2>/dev/null | awk '{print "CPU核心: "$1}' || true
    uptime | sed 's/^/负载: /'
    echo ""
    print_title "内存"
    free -h || true
    echo ""
    print_title "磁盘"
    df -hT / /home /tmp 2>/dev/null || df -hT
    echo ""
    print_title "Top 进程"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 8
}

tools_ports() {
    print_header "端口监听"
    if has_cmd ss; then
        ss -ltnup 2>/dev/null || ss -ltnp 2>/dev/null || true
    elif has_cmd netstat; then
        netstat -ltnup 2>/dev/null || true
    else
        print_warn "缺少 ss/netstat，可运行: tt deps install"
        return 1
    fi
}

tools_clean_cache() {
    print_header "清理缓存"
    local before after
    before="$(df -h / | awk 'NR==2{print $4}')"
    if has_cmd apt-get; then
        run "清理 apt 缓存" apt-get clean
        apt-get autoremove -y || true
    elif has_cmd dnf; then
        run "清理 dnf 缓存" dnf clean all
    elif has_cmd yum; then
        run "清理 yum 缓存" yum clean all
    fi
    journalctl --vacuum-time=14d >/dev/null 2>&1 || true
    find "${TT_HOME}/logs" -type f -name '*.log' -mtime +30 -delete 2>/dev/null || true
    after="$(df -h / | awk 'NR==2{print $4}')"
    print_success "清理完成，可用空间: ${before} -> ${after}"
}

tools_system_update() {
    print_header "系统更新"
    print_warn "系统更新会改动系统软件包，建议在重要服务低峰期执行。"
    confirm "确认执行系统更新？" || return 0
    check_root
    if has_cmd apt-get; then
        run_or_die "更新 apt 索引" apt-get update
        run_or_die "升级系统包" apt-get upgrade -y
    elif has_cmd dnf; then
        run_or_die "升级系统包" dnf upgrade -y
    elif has_cmd yum; then
        run_or_die "升级系统包" yum update -y
    elif has_cmd apk; then
        run_or_die "升级系统包" apk upgrade --no-cache
    else
        die "未识别包管理器"
    fi
}

tools_swap_status() {
    print_header "Swap 状态"
    free -h || true
    echo ""
    swapon --show 2>/dev/null || true
}

tools_swap_add() {
    local size_mb="${1:-}"
    if [ -z "$size_mb" ]; then
        read -r -p "请输入 swap 大小 MB（如 1024/2048）: " size_mb
    fi
    [[ "$size_mb" =~ ^[0-9]+$ ]] || die "swap 大小必须是数字 MB"
    [ "$size_mb" -ge 256 ] || die "swap 建议至少 256MB"
    check_root
    print_warn "将创建或替换 /swapfile，并写入 /etc/fstab。"
    confirm "确认设置 ${size_mb}MB swap？" || return 0
    swapoff /swapfile 2>/dev/null || true
    rm -f /swapfile
    if has_cmd fallocate; then
        fallocate -l "${size_mb}M" /swapfile
    else
        dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress
    fi
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    tools_swap_status
}

tools_install() {
    local tool="${1:-}"
    if [ -z "$tool" ]; then
        read -r -p "请输入要安装的工具名: " tool
    fi
    [ -n "$tool" ] || die "工具名不能为空"
    case "$tool" in
        docker) deps_install recommended ;;
        ss) _tools_install_pkg iproute2 ;;
        *) _tools_install_pkg "$tool" ;;
    esac
}

tools_network() {
    print_header "网络信息"
    echo "公网 IPv4: $(curl -fsS --max-time 3 https://ipinfo.io/ip 2>/dev/null || echo unknown)"
    echo "公网 IPv6: $(curl -fsS --max-time 3 https://v6.ipinfo.io/ip 2>/dev/null || echo none)"
    echo ""
    print_title "默认路由"
    ip route 2>/dev/null | sed -n '1,8p' || true
    echo ""
    print_title "DNS"
    sed -n '1,8p' /etc/resolv.conf 2>/dev/null || true
}

tools_logs_recent() {
    print_header "系统最近日志"
    journalctl -p warning -n "${1:-80}" --no-pager 2>/dev/null || dmesg | tail -n "${1:-80}" || true
}

tools_menu() {
    while true; do
        echo ""
        print_title "系统工具"
        echo ""
        echo "  1) 资源概览 ✅"
        echo "  2) 端口监听 ✅"
        echo "  3) 网络信息 ✅"
        echo "  4) Swap 状态 ✅"
        echo "  5) 最近系统日志 ✅"
        echo "  6) 清理缓存 🔧"
        echo "  7) 安装常用工具 🔧"
        echo "  8) 添加/重建 Swap ⚠️"
        echo "  9) 系统更新 ⚠️"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/tools> " choice
        case "$choice" in
            1) tools_resource ;;
            2) tools_ports ;;
            3) tools_network ;;
            4) tools_swap_status ;;
            5) tools_logs_recent ;;
            6) tools_clean_cache ;;
            7) tools_install ;;
            8) tools_swap_add ;;
            9) tools_system_update ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
