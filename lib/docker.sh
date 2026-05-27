#!/bin/bash
# =============================================================================
# TianTian Ops - docker.sh
# Docker 容器控制：compose 管理、日志、状态
# =============================================================================

# --- 检查 compose 命令 ---
docker_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif has_cmd docker-compose; then
        echo "docker-compose"
    else
        die "docker compose 未安装"
    fi
}

# --- 项目目录下执行 compose ---
docker_project() {
    local project_dir="$1"; shift
    local compose_cmd=$(docker_compose_cmd)
    (cd "$project_dir" && $compose_cmd "$@")
}

# --- 启动项目 ---
docker_up() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")
    
    print_info "启动容器: ${project_name}"
    
    if [ ! -f "${project_dir}/docker-compose.yml" ]; then
        print_fail "docker-compose.yml 不存在: ${project_dir}"
        return 1
    fi
    
    docker_project "$project_dir" up -d --remove-orphans
    local rc=$?
    
    if [ "$rc" -eq 0 ]; then
        print_success "容器启动成功: ${project_name}"
    else
        print_fail "容器启动失败: ${project_name}"
    fi
    return $rc
}

# --- 停止项目 ---
docker_down() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")
    
    print_info "停止容器: ${project_name}"
    docker_project "$project_dir" down
    print_success "容器已停止: ${project_name}"
}

# --- 重启项目 ---
docker_restart() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")
    
    print_info "重启容器: ${project_name}"
    docker_project "$project_dir" restart
    print_success "容器已重启: ${project_name}"
}

# --- 查看项目状态 ---
docker_status() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")
    
    echo ""
    print_title "容器状态: ${project_name}"
    docker_project "$project_dir" ps
}

# --- 查看日志 ---
docker_logs() {
    local project_dir="$1"
    local lines="${2:-50}"
    local project_name=$(basename "$project_dir")
    
    print_title "容器日志: ${project_name} (最近 ${lines} 行)"
    docker_project "$project_dir" logs --tail "$lines"
}

# --- 进入容器 ---
docker_shell() {
    local project_dir="$1"
    local service="${2:-}"
    local project_name=$(basename "$project_dir")
    
    if [ -z "$service" ]; then
        # 找第一个服务
        service=$(docker_project "$project_dir" config --services 2>/dev/null | head -1)
    fi
    
    if [ -z "$service" ]; then
        print_fail "未找到服务"
        return 1
    fi
    
    print_info "进入容器: ${project_name}/${service}"
    docker_project "$project_dir" exec "$service" sh
}

# --- 等待服务健康 ---
docker_wait_healthy() {
    local project_dir="$1"
    local port="${2:-80}"
    local max_wait="${3:-60}"
    local project_name=$(basename "$project_dir")
    
    print_info "等待服务就绪: ${project_name}:${port} (最多 ${max_wait}s)"
    
    local waited=0
    while [ "$waited" -lt "$max_wait" ]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${port}" 2>/dev/null | grep -qE '^[23]'; then
            print_success "服务就绪 (${waited}s)"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        if [ $((waited % 10)) -eq 0 ]; then
            print_info "等待中... ${waited}s"
        fi
    done
    
    print_fail "服务超时未就绪 (${max_wait}s)"
    return 1
}

# --- 列出所有 docker 项目 ---
docker_list_projects() {
    echo ""
    print_title "Docker 项目"
    echo ""
    
    # 扫描 /home/docker/
    if [ -d /home/docker ]; then
        for dir in /home/docker/*/; do
            [ -d "$dir" ] || continue
            local name=$(basename "$dir")
            if [ -f "${dir}docker-compose.yml" ]; then
                local status="unknown"
                local containers=$(docker_project "$dir" ps -q 2>/dev/null | wc -l)
                if [ "$containers" -gt 0 ]; then
                    status="${GREEN}running${NC}"
                else
                    status="${YELLOW}stopped${NC}"
                fi
                printf "  %-25s %b (%s containers)\n" "$name" "$status" "$containers"
            fi
        done
    fi
    echo ""
}
