#!/bin/bash
# =============================================================================
# TianTian Ops - health.sh
# 巡检系统：检查各服务状态、资源使用率、告警
# =============================================================================

# --- 检查函数 ---

health_docker() {
    if ! has_cmd docker; then
        echo -e "  Docker        ${RED}未安装${NC}"
        return 1
    fi
    if docker info >/dev/null 2>&1; then
        local cnt=$(docker ps -q 2>/dev/null | wc -l)
        echo -e "  Docker        ${GREEN}运行中${NC} (${cnt} 个容器)"
    else
        echo -e "  Docker        ${RED}异常${NC}"
        return 1
    fi
}

health_nginx() {
    if ! has_cmd nginx && ! docker exec nginx nginx -v >/dev/null 2>&1; then
        echo -e "  Nginx         ${YELLOW}未安装${NC}"
        return 1
    fi
    # 测试配置
    if has_cmd nginx; then
        if ! nginx -t >/dev/null 2>&1; then
            echo -e "  Nginx         ${RED}配置错误${NC}"
            return 1
        fi
    elif docker exec nginx nginx -t >/dev/null 2>&1; then
        :  # 配置正确
    else
        echo -e "  Nginx         ${RED}配置错误${NC}"
        return 1
    fi
    # 检查运行状态
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "  Nginx         ${GREEN}运行中${NC}"
    elif pgrep -x nginx >/dev/null 2>&1; then
        echo -e "  Nginx         ${GREEN}运行中${NC} (非 systemd)"
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nginx'; then
        echo -e "  Nginx         ${GREEN}运行中${NC} (Docker)"
    else
        echo -e "  Nginx         ${RED}未运行${NC}"
        return 1
    fi
}

health_443() {
    if ss -tlnp 2>/dev/null | grep -q ':443 '; then
        echo -e "  公网 443      ${GREEN}已监听${NC}"
    else
        echo -e "  公网 443      ${YELLOW}未监听${NC}"
    fi
}

health_memory() {
    local avail=$(detect_mem_avail_mb)
    local total=$(detect_mem_mb)
    local pct=$(( (total - avail) * 100 / total ))
    if [ "$pct" -lt 80 ]; then
        echo -e "  内存使用      ${GREEN}${pct}%${NC} (${avail}MB / ${total}MB 可用)"
    elif [ "$pct" -lt 95 ]; then
        echo -e "  内存使用      ${YELLOW}${pct}%${NC} (${avail}MB / ${total}MB 可用)"
    else
        echo -e "  内存使用      ${RED}${pct}%${NC} (${avail}MB / ${total}MB 可用)"
    fi
}

health_disk() {
    local pct=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    local free=$(detect_disk_free)
    local total=$(detect_disk_total)
    if [ "$pct" -lt 80 ]; then
        echo -e "  磁盘使用      ${GREEN}${pct}%${NC} ($free / $total 剩余)"
    elif [ "$pct" -lt 95 ]; then
        echo -e "  磁盘使用      ${YELLOW}${pct}%${NC} ($free / $total 剩余)"
    else
        echo -e "  磁盘使用      ${RED}${pct}%${NC} ($free / $total 剩余)"
    fi
}

health_cpu() {
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cores=$(detect_cpu)
    echo -e "  CPU 负载      ${load} (${cores} 核)"
}

health_certs() {
    if [ -d /home/web/certs ]; then
        local cnt=$(ls /home/web/certs/*_cert.pem 2>/dev/null | wc -l)
        echo -e "  证书数量      ${cnt}"
        # 检查即将过期的证书
        local soon=0
        for cert in /home/web/certs/*_cert.pem; do
            [ -f "$cert" ] || continue
            local exp=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
            if [ -n "$exp" ]; then
                local exp_ts=$(date -d "$exp" +%s 2>/dev/null)
                local now_ts=$(date +%s)
                local days_left=$(( (exp_ts - now_ts) / 86400 ))
                if [ "$days_left" -lt 30 ] && [ "$days_left" -ge 0 ]; then
                    echo -e "    ${YELLOW}⚠ ${cert##*/} 还剩 ${days_left} 天过期${NC}"
                    soon=1
                elif [ "$days_left" -lt 0 ]; then
                    echo -e "    ${RED}✗ ${cert##*/} 已过期${NC}"
                    soon=1
                fi
            fi
        done
        [ "$soon" -eq 0 ] && echo -e "    全部证书有效"
    fi
}

health_projects() {
    if [ -f "$TT_STATE" ]; then
        local cnt=$(python3 -c "import json; d=json.load(open('$TT_STATE')); print(len(d.get('projects',{})))" 2>/dev/null || echo 0)
        echo -e "  托管项目      ${cnt} 个"
        if [ "$cnt" -gt 0 ]; then
            python3 -c "
import json
d=json.load(open('$TT_STATE'))
for name,p in d.get('projects',{}).items():
    status = p.get('status','unknown')
    icon = '✓' if status == 'running' else '✗' if status == 'stopped' else '?'
    print(f'    {icon} {name} [{status}]')
" 2>/dev/null
        fi
    else
        echo -e "  托管项目      0 个"
    fi
}

# --- 主巡检 ---
health_check() {
    print_header "系统巡检"
    echo ""
    
    print_title "🖥️  系统资源"
    health_memory
    health_disk
    health_cpu
    echo ""
    
    print_title "🐳 容器服务"
    health_docker
    echo ""
    
    print_title "🌐 网络服务"
    health_nginx
    health_443
    health_certs
    echo ""
    
    print_title "📦 托管项目"
    health_projects
    echo ""
    
    log_info "health_check 完成"
}

# 简洁输出（适合 cron）
health_quick() {
    local issues=0
    
    # 内存
    local avail=$(detect_mem_avail_mb)
    local total=$(detect_mem_mb)
    local mem_pct=$(( (total - avail) * 100 / total ))
    [ "$mem_pct" -ge 90 ] && { echo "WARN: 内存使用 ${mem_pct}%"; issues=1; }
    
    # 磁盘
    local disk_pct=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    [ "$disk_pct" -ge 90 ] && { echo "WARN: 磁盘使用 ${disk_pct}%"; issues=1; }
    
    # Docker
    if has_cmd docker && ! docker info >/dev/null 2>&1; then
        echo "ERROR: Docker 异常"; issues=1
    fi
    
    # Nginx
    if has_cmd nginx && ! pgrep -x nginx >/dev/null 2>&1; then
        echo "ERROR: Nginx 未运行"; issues=1
    fi
    
    [ "$issues" -eq 0 ] && echo "OK: 所有服务正常"
}
