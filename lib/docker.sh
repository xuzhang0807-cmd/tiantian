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

# --- Docker 资源概览（只读） ---
docker_overview() {
    print_header "Docker 资源概览"
    if ! has_cmd docker; then
        print_warn "Docker 未安装"
        return 1
    fi

    print_title "引擎状态"
    docker info --format 'Server={{.ServerVersion}} Containers={{.Containers}} Running={{.ContainersRunning}} Paused={{.ContainersPaused}} Stopped={{.ContainersStopped}} Images={{.Images}}' 2>/dev/null || {
        print_warn "无法读取 Docker daemon，请确认服务是否运行"
        return 1
    }
    echo ""

    print_title "资源占用"
    docker system df 2>/dev/null || true
    echo ""

    print_title "容器资源 Top"
    docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}' 2>/dev/null | sed -n '1,12p' || true
}

# --- Docker 全局容器列表（只读） ---
docker_list_containers() {
    print_header "Docker 容器列表"
    if ! has_cmd docker; then
        print_warn "Docker 未安装"
        return 1
    fi
    docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null || {
        print_warn "无法读取容器列表"
        return 1
    }
}

# --- Docker 镜像列表（只读） ---
docker_list_images() {
    print_header "Docker 镜像列表"
    if ! has_cmd docker; then
        print_warn "Docker 未安装"
        return 1
    fi
    docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' 2>/dev/null || true
}

# --- Docker 卷/网络列表（只读） ---
docker_list_storage() {
    print_header "Docker 卷与网络"
    if ! has_cmd docker; then
        print_warn "Docker 未安装"
        return 1
    fi
    print_title "Volumes"
    docker volume ls 2>/dev/null || true
    echo ""
    print_title "Networks"
    docker network ls 2>/dev/null || true
}

# --- 校验 compose 项目（只读） ---
docker_compose_check() {
    local project_name="${1:-}"
    local root="${PROJECTS_BASE:-/home/docker}"
    local checked=0 failed=0

    if [ -n "$project_name" ]; then
        _docker_compose_check_one "${root}/${project_name}" || return 1
        return 0
    fi

    print_header "Compose 配置校验"
    if [ ! -d "$root" ]; then
        print_warn "项目目录不存在: $root"
        return 0
    fi

    for dir in "$root"/*/; do
        [ -d "$dir" ] || continue
        if [ -f "${dir}docker-compose.yml" ] || [ -f "${dir}compose.yml" ] || [ -f "${dir}docker-compose.yaml" ] || [ -f "${dir}compose.yaml" ]; then
            checked=$((checked + 1))
            if ! _docker_compose_check_one "$dir"; then
                failed=$((failed + 1))
            fi
        fi
    done

    echo ""
    if [ "$checked" -eq 0 ]; then
        print_warn "未发现 compose 项目"
    elif [ "$failed" -eq 0 ]; then
        print_success "校验完成：${checked} 个项目全部通过"
    else
        print_fail "校验完成：${checked} 个项目，${failed} 个失败"
        return 1
    fi
}

_docker_compose_check_one() {
    local project_dir="$1"
    local name
    name=$(basename "$project_dir")

    if [ ! -d "$project_dir" ]; then
        print_fail "项目目录不存在: $project_dir"
        return 1
    fi
    if [ ! -f "${project_dir}/docker-compose.yml" ] && [ ! -f "${project_dir}/compose.yml" ] && [ ! -f "${project_dir}/docker-compose.yaml" ] && [ ! -f "${project_dir}/compose.yaml" ]; then
        print_warn "跳过 ${name}: 未找到 compose 文件"
        return 0
    fi

    if (cd "$project_dir" && $(docker_compose_cmd) config -q >/dev/null 2>&1); then
        print_success "${name}: compose 配置通过"
        return 0
    fi

    print_fail "${name}: compose 配置失败"
    (cd "$project_dir" && $(docker_compose_cmd) config 2>&1 | sed -n '1,20p') || true
    return 1
}

# --- Docker daemon 配置巡检（只读） ---
docker_daemon_config() {
    print_header "Docker 配置 / 镜像源 / IPv6"
    if ! has_cmd docker; then
        print_warn "Docker 未安装"
        return 1
    fi

    print_title "daemon.json"
    if [ -f /etc/docker/daemon.json ]; then
        sed -n '1,120p' /etc/docker/daemon.json 2>/dev/null || true
    else
        print_warn "未发现 /etc/docker/daemon.json"
    fi
    echo ""

    print_title "镜像源"
    local mirrors
    mirrors="$(docker info --format '{{json .RegistryConfig.Mirrors}}' 2>/dev/null || true)"
    if [ -n "$mirrors" ] && [ "$mirrors" != "null" ] && [ "$mirrors" != "[]" ]; then
        echo "$mirrors"
    else
        print_warn "未配置 registry mirrors，拉取镜像可能较慢。"
    fi
    echo ""

    print_title "Docker IPv6"
    local ipv6 fixed_cidr_v6
    ipv6="$(docker info --format '{{.IPv6}}' 2>/dev/null || true)"
    fixed_cidr_v6="$(docker info --format '{{.IPv6}} {{.DefaultAddressPools}}' 2>/dev/null || true)"
    echo "IPv6: ${ipv6:-unknown}"
    echo "Address pools: ${fixed_cidr_v6:-unknown}"
    if [ "$ipv6" != "true" ]; then
        print_warn "Docker IPv6 未启用；仅在需要容器 IPv6 出站/入站时再规划开启。"
    fi
}

# --- Docker 安全巡检（只读） ---
docker_safety_audit() {
    print_header "Docker 安全巡检"
    if ! has_cmd docker; then
        print_warn "Docker 未安装"
        return 1
    fi

    print_title "宿主机资源"
    free -h 2>/dev/null || true
    df -hT / /home /var/lib/docker 2>/dev/null || df -hT / /var/lib/docker 2>/dev/null || true
    echo ""

    print_title "Docker 空间"
    docker system df 2>/dev/null || true
    echo ""

    print_title "未设置内存限制的运行容器"
    local unlimited
    unlimited="$(docker ps -q | xargs -r docker inspect --format '{{.Name}} {{.HostConfig.Memory}}' 2>/dev/null | awk '$2==0 {sub(/^\//,"",$1); print "  - "$1}')"
    if [ -n "$unlimited" ]; then
        printf '%s\n' "$unlimited"
        print_warn "低内存服务器新增容器建议设置 mem_limit/memory，避免 OOM。"
    else
        print_success "运行容器均设置了内存限制，或当前无运行容器"
    fi
    echo ""

    print_title "重启策略"
    docker ps -a -q | xargs -r docker inspect --format '{{.Name}} Restart={{.HostConfig.RestartPolicy.Name}}' 2>/dev/null | sed 's#^/##' || true
}

_docker_prune_snapshot() {
    local backup_dir="$1"
    mkdir -p "$backup_dir"
    docker system df -v > "${backup_dir}/system-df.txt" 2>&1 || true
    docker ps -a --no-trunc > "${backup_dir}/containers.txt" 2>&1 || true
    docker images --digests --no-trunc > "${backup_dir}/images.txt" 2>&1 || true
    docker volume ls > "${backup_dir}/volumes.txt" 2>&1 || true
    docker network ls > "${backup_dir}/networks.txt" 2>&1 || true
}

# --- Docker 清理预案（只读） ---
docker_prune_plan() {
    local mode="${1:-safe}"
    print_header "Docker 清理预案"
    if ! has_cmd docker; then
        print_warn "Docker 未安装"
        return 1
    fi

    print_title "当前 Docker 空间"
    docker system df 2>/dev/null || true
    echo ""

    print_title "将执行的命令"
    case "$mode" in
        safe)
            echo "docker container prune -f        # 删除已停止容器"
            echo "docker image prune -f            # 删除悬空镜像"
            echo "docker builder prune -f          # 删除构建缓存"
            ;;
        all|aggressive)
            echo "docker system prune -a --volumes -f  # 删除未使用容器/网络/镜像/卷，风险高"
            print_warn "all 模式可能删除未挂载但仍有价值的 volume；只在确认无生产依赖后执行。"
            ;;
        *)
            print_fail "未知模式: $mode；可用 safe|all"
            return 1
            ;;
    esac
    echo ""
    print_info "真实执行: tt docker prune-run ${mode} --yes"
}

# --- Docker 清理执行（写入/删除，先快照） ---
docker_prune_run() {
    local mode="${1:-safe}" yes="${2:-}"
    print_header "Docker 清理执行"
    if ! has_cmd docker; then
        print_warn "Docker 未安装"
        return 1
    fi
    if [ "$yes" != "--yes" ]; then
        print_warn "将删除 Docker 可再生资源；执行前会保存清理前清单。"
        confirm "确认执行 Docker ${mode} 清理？" || { print_info "已取消"; return 0; }
    fi

    local backup_dir="${TT_BACKUP_ROOT}/docker-prune/$(date +%Y%m%d_%H%M%S)"
    _docker_prune_snapshot "$backup_dir"
    print_success "清理前清单已保存: $backup_dir"

    print_title "清理前空间"
    docker system df 2>/dev/null || true
    echo ""

    case "$mode" in
        safe)
            docker container prune -f
            docker image prune -f
            docker builder prune -f
            ;;
        all|aggressive)
            docker system prune -a --volumes -f
            ;;
        *)
            print_fail "未知模式: $mode；可用 safe|all"
            return 1
            ;;
    esac

    echo ""
    print_title "清理后空间"
    docker system df 2>/dev/null || true
    print_success "Docker 清理完成"
}
