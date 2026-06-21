#!/bin/bash
# =============================================================================
# TianTian Ops - security.sh
# Fail2ban and ClamAV helpers. Defaults are read-only or plan-first.
# =============================================================================

security_status() {
    print_header "安全工具状态"
    print_title "Fail2ban"
    if has_cmd fail2ban-client; then
        echo "fail2ban-client: $(command -v fail2ban-client)"
        if has_cmd systemctl; then
            echo "service: $(systemctl is-active fail2ban 2>/dev/null || true) / $(systemctl is-enabled fail2ban 2>/dev/null || true)"
        fi
        fail2ban-client status 2>/dev/null || print_warn "fail2ban-client 存在但服务未就绪"
    else
        print_warn "未安装 fail2ban"
    fi
    echo ""

    print_title "SSH 暴力破解线索"
    if has_cmd journalctl; then
        journalctl -u ssh -u sshd --since '24 hours ago' --no-pager 2>/dev/null | grep -Ei 'failed|invalid|authentication failure' | tail -n 12 || print_success "近 24 小时未见明显 SSH 失败日志"
    else
        grep -Eih 'failed|invalid|authentication failure' /var/log/auth.log /var/log/secure 2>/dev/null | tail -n 12 || true
    fi
    echo ""

    print_title "ClamAV"
    if has_cmd clamscan; then
        clamscan --version 2>/dev/null || true
    else
        print_warn "未安装本机 clamscan"
    fi
    if has_cmd docker; then
        echo "docker: 可用；可使用容器化 ClamAV 扫描预案"
        docker volume ls 2>/dev/null | awk '/clam_db/ {print "volume: "$2}' || true
    else
        print_warn "Docker 不可用；容器化 ClamAV 扫描不可用"
    fi
}

security_fail2ban_plan() {
    print_header "Fail2ban 安装/启用预案"
    local pm
    pm="$(_tools_pkg_manager 2>/dev/null || echo unknown)"
    echo "包管理器: $pm"
    case "$pm" in
        apt) echo "安装: apt-get update && apt-get install -y fail2ban rsyslog" ;;
        dnf) echo "安装: dnf install -y fail2ban" ;;
        yum) echo "安装: yum install -y fail2ban" ;;
        apk) echo "安装: apk add --no-cache fail2ban" ;;
        *) echo "安装: 请按系统发行版手动安装 fail2ban" ;;
    esac
    echo "启用: systemctl enable --now fail2ban"
    echo "检查: fail2ban-client status && fail2ban-client status sshd"
    echo ""
    print_warn "install 会修改系统包和服务；执行前请确认当前 SSH 仍可用，并保留一个活动会话。"
}

security_fail2ban_install() {
    print_header "安装/启用 Fail2ban"
    check_root
    security_fail2ban_plan
    confirm "确认安装并启用 fail2ban？" || return 0
    local pm
    pm="$(_tools_pkg_manager 2>/dev/null || echo unknown)"
    case "$pm" in
        apt)
            apt-get update
            apt-get install -y fail2ban rsyslog
            systemctl enable --now rsyslog 2>/dev/null || true
            ;;
        dnf) dnf install -y fail2ban ;;
        yum) yum install -y fail2ban ;;
        apk) apk add --no-cache fail2ban ;;
        *) die "未识别包管理器，请手动安装 fail2ban" ;;
    esac
    systemctl enable --now fail2ban 2>/dev/null || service fail2ban start 2>/dev/null || true
    security_status
}

security_clamav_plan() {
    local target="${1:-/home}"
    print_header "ClamAV 扫描预案"
    echo "目标目录: $target"
    echo "日志目录: /home/docker/clamav/log"
    echo "病毒库卷: clam_db"
    echo ""
    echo "步骤:"
    echo "  1. docker volume create clam_db"
    echo "  2. docker run --rm --name tt-clamav-update --mount source=clam_db,target=/var/lib/clamav clamav/clamav-debian:latest freshclam"
    echo "  3. docker run --rm --name tt-clamav-scan --mount source=clam_db,target=/var/lib/clamav --mount type=bind,source=${target},target=/mnt/scan,readonly -v /home/docker/clamav/log:/var/log/clamav clamav/clamav-debian:latest clamscan -r --log=/var/log/clamav/scan.log /mnt/scan"
    echo ""
    print_warn "扫描可能很慢且会拉取镜像；默认只读挂载目标目录，不删除文件。"
}

security_clamav_scan() {
    local target="${1:-/home}"
    print_header "ClamAV 容器扫描"
    [ -d "$target" ] || { print_fail "目标目录不存在: $target"; return 1; }
    has_cmd docker || { print_fail "缺少 Docker，无法运行容器化 ClamAV"; return 1; }
    security_clamav_plan "$target"
    confirm "确认开始扫描 ${target}？" || return 0
    mkdir -p /home/docker/clamav/log
    docker volume create clam_db >/dev/null
    docker run --rm --name tt-clamav-update --mount source=clam_db,target=/var/lib/clamav clamav/clamav-debian:latest freshclam
    docker run --rm --name tt-clamav-scan \
        --mount source=clam_db,target=/var/lib/clamav \
        --mount type=bind,source="${target}",target=/mnt/scan,readonly \
        -v /home/docker/clamav/log:/var/log/clamav \
        clamav/clamav-debian:latest \
        clamscan -r --log=/var/log/clamav/scan.log /mnt/scan
    print_success "扫描完成，报告: /home/docker/clamav/log/scan.log"
}

security_menu() {
    while true; do
        echo ""
        print_title "安全工具"
        echo ""
        echo "  1) 安全工具状态 ✅"
        echo "  2) Fail2ban 安装预案 ✅"
        echo "  3) 安装/启用 Fail2ban ⚠️"
        echo "  4) ClamAV 扫描预案 ✅"
        echo "  5) ClamAV 容器扫描 ⚠️"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/security> " choice
        case "$choice" in
            1) security_status ;;
            2) security_fail2ban_plan ;;
            3) security_fail2ban_install ;;
            4) read -r -p "  目标目录 [/home]: " target; security_clamav_plan "${target:-/home}" ;;
            5) read -r -p "  目标目录 [/home]: " target; security_clamav_scan "${target:-/home}" ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
