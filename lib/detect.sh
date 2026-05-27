#!/bin/bash
# =============================================================================
# TianTian Ops - detect.sh
# 服务器检测：CPU、内存、磁盘、系统信息
# =============================================================================

detect_cpu() {
    nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1
}

detect_mem_mb() {
    free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo 0
}

detect_mem_avail_mb() {
    free -m 2>/dev/null | awk '/Mem:/ {print $7}' || echo 0
}

detect_disk_free() {
    df -h / 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A"
}

detect_disk_total() {
    df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "N/A"
}

detect_disk_pct() {
    df -h / 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${PRETTY_NAME:-$NAME $VERSION_ID}"
    else
        uname -sr
    fi
}

detect_kernel() {
    uname -r
}

detect_arch() {
    uname -m
}

detect_virtualization() {
    systemd-detect-virt 2>/dev/null || echo "unknown"
}

detect_uptime() {
    uptime -p 2>/dev/null | sed 's/^up //' || uptime | awk -F'up' '{print $2}' | awk -F',' '{print $1}' | xargs
}

detect_docker_version() {
    docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo "未安装"
}

detect_docker_compose() {
    docker compose version 2>/dev/null | awk '{print $NF}' || echo "未安装"
}

detect_nginx_version() {
    if has_cmd nginx; then
        nginx -v 2>&1 | awk -F'/' '{print $NF}'
    elif docker exec nginx nginx -v 2>/dev/null; then
        docker exec nginx nginx -v 2>&1 | awk -F'/' '{print $NF}'
    else
        echo "未安装"
    fi
}

# 一次性全量检测
detect_all() {
    print_header "服务器检测报告"
    echo ""
    
    local cpu=$(detect_cpu)
    local mem=$(detect_mem_mb)
    local mem_avail=$(detect_mem_avail_mb)
    local disk_free=$(detect_disk_free)
    local disk_total=$(detect_disk_total)
    local disk_pct=$(detect_disk_pct)
    local os=$(detect_os)
    local kernel=$(detect_kernel)
    local arch=$(detect_arch)
    local virt=$(detect_virtualization)
    local uptime_val=$(detect_uptime)
    
    printf "  ${BOLD}%-20s${NC} %s\n" "操作系统" "$os"
    printf "  ${BOLD}%-20s${NC} %s (%s)\n" "内核/架构" "$kernel" "$arch"
    printf "  ${BOLD}%-20s${NC} %s\n" "虚拟化" "$virt"
    printf "  ${BOLD}%-20s${NC} %s\n" "运行时间" "$uptime_val"
    echo ""
    printf "  ${BOLD}%-20s${NC} %s 核\n" "CPU 核心数" "$cpu"
    printf "  ${BOLD}%-20s${NC} %s MB (可用 %s MB)\n" "内存总量" "$mem" "$mem_avail"
    printf "  ${BOLD}%-20s${NC} %s / %s (已用 %s)\n" "磁盘空间" "$disk_free" "$disk_total" "$disk_pct"
    echo ""
    printf "  ${BOLD}%-20s${NC} %s\n" "Docker" "$(detect_docker_version)"
    printf "  ${BOLD}%-20s${NC} %s\n" "Docker Compose" "$(detect_docker_compose)"
    printf "  ${BOLD}%-20s${NC} %s\n" "Nginx" "$(detect_nginx_version)"
    echo ""
    
    # 网络检查
    printf "  ${BOLD}%-20s${NC} " "网络连通性"
    if curl -s --connect-timeout 3 https://www.baidu.com >/dev/null 2>&1; then
        echo -e "${GREEN}正常${NC}"
    else
        echo -e "${RED}异常${NC}"
    fi
    
    echo ""
    log_info "detect_all 完成"
}
