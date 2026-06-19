#!/bin/bash
# =============================================================================
# TianTian Ops - project.sh
# 项目管理：创建、部署、删除、状态
# 严格按 14 步流程部署
# =============================================================================

PROJECTS_BASE="${PROJECTS_BASE:-/home/docker}"
MANIFEST_TEMPLATE="${TT_HOME}/templates/manifest.yaml.tpl"
PROJECTS_CONFIG_DIR="${TT_HOME}/projects"

# --- 项目部署主流程（14 步）---
project_deploy() {
    local project_name="$1"
    local project_type="${2:-$project_name}"
    local project_domain="${3:-}"
    local project_port="${4:-8080}"
    local project_dir="${5:-}"
    project_dir="${project_dir:-$(preset_blueprint_default "$project_type" "project_dir")}"
    project_dir="${project_dir:-${PROJECTS_BASE}/${project_name}}"
    
    print_header "部署项目: ${project_name} (${project_type})"
    echo ""

    if ! preset_validate_project_name "$project_name"; then
        die "项目名称不合法：只能使用小写字母、数字、中划线，且不能以中划线开头/结尾"
    fi
    if ! validate_port "$project_port"; then
        die "端口不合法：${project_port}"
    fi
    if [ -n "$project_domain" ]; then
        project_domain="$(normalize_domain "$project_domain")"
        validate_domain "$project_domain" || die "域名不合法：${project_domain}"
    fi

    local deploy_phase="init"
    project_state_save "$project_name" "deploying" "$project_type" "$project_domain" "$project_port" "$deploy_phase"
    project_deploy_fail() {
        local rc=$?
        trap - INT TERM EXIT
        if [ "$rc" -ne 0 ]; then
            project_state_save "$project_name" "failed" "$project_type" "$project_domain" "$project_port" "$deploy_phase"
            print_warn "部署中断或失败，状态已标记为 failed；修复后可重新执行同一 deploy 命令"
        fi
        return "$rc"
    }
    trap project_deploy_fail INT TERM EXIT
    
    # Step 1: 检测服务器
    deploy_phase="detect"
    print_info "[1/14] 检测服务器 ..."
    local cpu=$(detect_cpu)
    local mem=$(detect_mem_mb)
    local mem_avail=$(detect_mem_avail_mb)
    print_success "CPU: ${cpu} 核, 内存: ${mem}MB (可用 ${mem_avail}MB)"
    
    # Step 2: 匹配 profile
    deploy_phase="profile"
    print_info "[2/14] 匹配服务器画像 ..."
    local profile=$(classify_server)
    print_success "服务器等级: ${profile}"
    
    # Step 3: 检查资源是否足够
    deploy_phase="resource-check"
    print_info "[3/14] 检查资源 ..."
    if ! can_deploy "$profile" "$project_type"; then
        die "资源不足，无法部署 ${project_type}"
    fi
    
    # Step 4: 准备项目目录
    deploy_phase="prepare-dir"
    print_info "[4/14] 准备项目目录: ${project_dir}"
    if [ -d "$project_dir" ] && [ -f "${project_dir}/manifest.yaml" ]; then
        print_warn "检测到已有项目，部署前先创建备份"
        backup_project "$project_name" >/dev/null || die "已有项目备份失败，部署已中止"
    elif [ -d "$project_dir" ] && [ -n "$(find "$project_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        die "目录已存在但不是 TianTian 托管项目：${project_dir}，请先手动确认或备份"
    fi
    mkdir -p "${project_dir}"/{data,logs,backups}
    print_success "目录已准备"
    
    # Step 5: 写 manifest.yaml
    deploy_phase="manifest"
    print_info "[5/14] 写入 manifest.yaml ..."
    project_write_manifest "$project_name" "$project_type" "$project_dir" "$project_domain" "$project_port"
    print_success "manifest.yaml 已生成"
    
    # Step 6: 写 docker-compose.yml
    deploy_phase="compose"
    print_info "[6/14] 生成 docker-compose.yml ..."
    if ! project_generate_compose "$project_name" "$project_type" "$project_dir" "$project_port" "$project_domain"; then
        # 没有预定义模板，生成通用框架
        project_generate_generic_compose "$project_name" "$project_type" "$project_dir" "$project_port"
    fi
    print_success "docker-compose.yml 已生成"
    
    # Step 7: docker compose up -d
    deploy_phase="docker-up"
    print_info "[7/14] 启动容器 ..."
    if ! docker_up "$project_dir"; then
        die "容器启动失败"
    fi
    
    # 短暂等待容器启动
    sleep 3
    
    # Step 8: 本地健康检查
    deploy_phase="health-check"
    print_info "[8/14] 本地健康检查 ..."
    local container_port=$(project_get_port "$project_dir")
    if [ -n "$container_port" ] && [ "$container_port" -gt 0 ] 2>/dev/null; then
        if docker_wait_healthy "$project_dir" "$container_port" 30; then
            print_success "健康检查通过 (127.0.0.1:${container_port})"
        else
            print_fail "健康检查失败"
            # 不终止，让用户决定
        fi
    else
        print_info "未检测到端口，跳过健康检查"
    fi
    
    # Step 9: 申请证书（如果有域名）
    deploy_phase="cert-obtain"
    local domain=$(project_get_domain "$project_dir")
    if [ -n "$domain" ]; then
        print_info "[9/14] 申请证书: ${domain} ..."
        cert_obtain "$domain" 2>/dev/null || print_warn "证书申请失败，可稍后手动处理"
    else
        print_info "[9/14] 无域名，跳过证书"
    fi
    
    # Step 10: 同步证书
    deploy_phase="cert-sync"
    if [ -n "$domain" ] && [ -d "/etc/letsencrypt/live/${domain}" ]; then
        print_info "[10/14] 同步证书 ..."
        cert_sync "$domain"
    else
        print_info "[10/14] 跳过证书同步"
    fi
    
    # Step 11: 生成 nginx 配置
    deploy_phase="nginx-render"
    if [ -n "$domain" ] && [ -n "$container_port" ]; then
        print_info "[11/14] 生成 nginx 配置 ..."
        nginx_render_site "$domain" "$container_port"
    else
        print_info "[11/14] 跳过 nginx 配置（缺域名或端口）"
    fi
    
    # Step 12: nginx -t
    deploy_phase="nginx-test"
    print_info "[12/14] 测试 nginx 配置 ..."
    nginx_test || print_warn "nginx 配置测试失败，请检查"
    
    # Step 13: reload nginx
    deploy_phase="nginx-reload"
    print_info "[13/14] 重载 nginx ..."
    nginx_reload || print_warn "nginx 重载失败"
    
    # Step 14: 最终验证
    deploy_phase="final-verify"
    print_info "[14/14] 最终验证 ..."
    if [ -n "$domain" ]; then
        sleep 2
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "https://${domain}" 2>/dev/null)
        if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
            print_success "HTTPS 验证通过: ${domain} (HTTP ${http_code})"
        else
            print_warn "HTTPS 验证: ${domain} 返回 ${http_code}"
        fi
    fi
    
    # 记录状态与端口池
    if ports_register "$project_name" "main" "$container_port" >/dev/null 2>&1; then
        project_state_save "$project_name" "running" "$project_type" "$domain" "$container_port" "complete"
    else
        deploy_phase="register"
        die "端口池注册失败，请运行 tt ports 检查后重试"
    fi
    trap - INT TERM EXIT
    
    echo ""
    print_success "项目 ${project_name} 部署完成！"
    echo ""
    
    if [ -n "$domain" ]; then
        echo -e "  ${GREEN}🌐 https://${domain}${NC}"
    fi
}

# --- 写 manifest.yaml ---
project_write_manifest() {
    local name="$1"
    local type="$2"
    local dir="$3"
    local domain="${4:-}"
    local port="${5:-8080}"
    local manifest_file="${dir}/manifest.yaml"

    python3 - "$manifest_file" "$name" "$type" "$domain" "$port" <<'PY'
import sys, datetime
path, name, project_type, domain, port = sys.argv[1:6]
created = datetime.datetime.now(datetime.timezone.utc).isoformat()
port_value = int(port) if str(port).isdigit() else port
content = f"""# TianTian Ops - Project Manifest
# Auto-generated by tt deploy
name: {name}
type: {project_type}
created: {created}
version: '1.0'

domain: \"{domain}\"

container:
  port: {port_value}

nginx:
  enabled: {str(bool(domain)).lower()}
  cert_enabled: {str(bool(domain)).lower()}

resources:
  cpu: 1
  memory: 512
"""
with open(path, "w") as f:
    f.write(content)
PY
}

# --- 生成 docker-compose.yml ---
project_generate_compose() {
    local name="$1"
    local type="$2"
    local dir="$3"
    local port="${4:-8080}"
    local domain="${5:-}"
    local blueprint_tpl="${TT_HOME}/blueprints/${type}/compose.yml.tpl"

    if [ -f "$blueprint_tpl" ]; then
        print_info "使用 blueprint compose 模板: ${blueprint_tpl}"
        python3 - "$blueprint_tpl" "${dir}/docker-compose.yml" "$name" "$domain" "$port" <<'PY'
import sys
from pathlib import Path
src, dst, name, domain, port = sys.argv[1:6]
text = Path(src).read_text()
replacements = {
    '{{NAME}}': name,
    '{{DOMAIN}}': domain,
    '{{WEB_PORT}}': port,
    '{{API_PORT}}': port,
    '{{BACKEND_PORT}}': port,
    '{{STOREFRONT_PORT}}': port,
    '{{DATA_DIR}}': '/home/komari/data' if name == 'komari' else './data',
}
for key, value in replacements.items():
    text = text.replace(key, str(value))
Path(dst).write_text(text)
PY
        print_success "docker-compose.yml 已由 blueprint 生成"
        return 0
    fi

    # 尝试加载预定义模板：先用项目名匹配，再回退到类型匹配
    local template="${PROJECTS_CONFIG_DIR}/${name}.yaml"
    [ -f "$template" ] || template="${PROJECTS_CONFIG_DIR}/${type}.yaml"
    if [ -f "$template" ]; then
        print_info "使用旧项目模板: ${template}"
        python3 -c "
import yaml,json,os,sys,random,string

name = '$name'
port = '$port'
domain = '$domain'

with open('$template') as f:
    cfg = yaml.safe_load(f)

compose = cfg.get('compose', {})

# 替换占位符
compose_str = yaml.dump(compose, default_flow_style=False, allow_unicode=True)
compose_str = compose_str.replace('{{NAME}}', name)
compose_str = compose_str.replace('{{PORT}}', port)
compose_str = compose_str.replace('{{DOMAIN}}', domain)
# 生成随机密码
db_pass = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
db_root_pass = ''.join(random.choices(string.ascii_letters + string.digits, k=24))
compose_str = compose_str.replace('{{DB_PASSWORD}}', db_pass)
compose_str = compose_str.replace('{{DB_ROOT_PASSWORD}}', db_root_pass)

out_path = '${dir}/docker-compose.yml'
with open(out_path, 'w') as f:
    f.write(compose_str)

# 保存密码到 .env
with open('${dir}/.env', 'w') as f:
    f.write(f'DB_PASSWORD={db_pass}\n')
    f.write(f'DB_ROOT_PASSWORD={db_root_pass}\n')

print(f'OK: written {len(compose_str)} bytes to {out_path}')
" || { print_warn "compose 模板渲染失败"; return 1; }
        
        print_success "docker-compose.yml 已生成（含随机密码）"
        return 0
    fi
    return 1
}

# --- 通用 compose 生成 ---
project_generate_generic_compose() {
    local name="$1"
    local type="$2"
    local dir="$3"
    local port="${4:-8080}"
    
    cat > "${dir}/docker-compose.yml" <<YAML
# TianTian Ops - ${name}
# Type: ${type}
services:
  ${name}:
    image: nginx:alpine
    container_name: tt-${name}
    restart: unless-stopped
    ports:
      - '127.0.0.1:${port}:80'
    volumes:
      - ./data:/usr/share/nginx/html:ro
      - ./logs:/var/log/nginx
    logging:
      driver: json-file
      options:
        max-size: '10m'
        max-file: '3'
YAML
}

# --- 读 manifest ---
project_read_manifest() {
    local dir="$1"
    if [ -f "${dir}/manifest.yaml" ]; then
        python3 -c "
import yaml,json
with open('${dir}/manifest.yaml') as f:
    d = yaml.safe_load(f)
print(json.dumps(d, ensure_ascii=False, default=str))
" 2>/dev/null
    fi
}

project_get_domain() {
    local dir="$1"
    project_read_manifest "$dir" | python3 -c "import json,sys; d=json.load(sys.stdin); v=d.get('domain') or ''; print(v)" 2>/dev/null
}

project_get_port() {
    local dir="$1"
    project_read_manifest "$dir" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('container',{}).get('port',''))" 2>/dev/null
}

project_get_type() {
    local dir="$1"
    project_read_manifest "$dir" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('type',''))" 2>/dev/null
}

# --- 状态管理 ---
project_state_save() {
    local name="$1"
    local status="$2"
    local type="${3:-}"
    local domain="${4:-}"
    local port="${5:-}"
    local phase="${6:-}"
    local payload
    payload="$(python3 - "$name" "$status" "$type" "$domain" "$port" "$phase" <<'PY'
import json, sys, datetime
name, status, project_type, domain, port, phase = sys.argv[1:7]
record = {
    "name": name,
    "status": status,
    "type": project_type,
    "domain": domain,
    "port": int(port) if str(port).isdigit() else port,
    "phase": phase,
    "updated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
print(json.dumps(record, ensure_ascii=False))
PY
)"
    state_set "projects.${name}" "$payload"
}

# --- 列出托管项目 ---
project_list() {
    print_header "托管项目"
    echo ""
    
    if [ -f "$TT_STATE" ]; then
        python3 -c "
import json
with open('$TT_STATE') as f:
    d = json.load(f)
projects = d.get('projects', {})
if not projects:
    print('  (暂无托管项目)')
else:
    for name, p in sorted(projects.items()):
        status = p.get('status', 'unknown')
        updated = p.get('updated', '')[:19]
        port = p.get('port', '')
        phase = p.get('phase', '')
        icon = '✓' if status == 'running' else '!' if status in ('failed', 'deploying') else '✗' if status == 'stopped' else '?'
        detail = f"port={port}" if port else "port=?"
        if phase and status != 'running':
            detail += f" phase={phase}"
        print(f'  {icon} {name:20s} [{status:10s}] {detail:24s} {updated}')
" 2>/dev/null
    else
        echo "  (暂无状态文件)"
    fi
    echo ""
    
    # 列出所有 /home/docker 下的项目
    if [ -d "$PROJECTS_BASE" ]; then
        for dir in "$PROJECTS_BASE"/*/; do
            [ -d "$dir" ] || continue
            local name=$(basename "$dir")
            if [ -f "${dir}manifest.yaml" ] && [ -f "${dir}docker-compose.yml" ]; then
                local domain=$(project_get_domain "$dir")
                local port=$(project_get_port "$dir")
                local type=$(project_get_type "$dir")
                printf "  📦 %s  |  类型: %s  |  %s:%-s\n" "$name" "$type" "${domain:-no-domain}" "${port:-?}"
            fi
        done
    fi
    echo ""
}

# --- 删除项目 ---
project_remove() {
    local name="$1"
    local project_dir="${PROJECTS_BASE}/${name}"
    
    if [ ! -d "$project_dir" ]; then
        print_fail "项目不存在: ${name}"
        return 1
    fi
    
    print_header "删除项目: ${name}"
    echo ""
    print_warn "删除前会先创建完整本地备份，备份保存在: ${TT_BACKUP_ROOT}/${name}/"
    print_warn "删除会停止容器、移除 nginx 配置，并把项目目录移入备份归档后清除运行目录"
    
    if ! confirm "确认继续删除项目 ${name}？"; then
        print_info "取消删除"
        return 0
    fi
    
    local backup_archive
    if ! backup_archive="$(backup_project "$name" | tail -1)"; then
        print_fail "删除已中止：备份失败，未对项目做任何清理"
        return 1
    fi
    print_success "删除前备份已完成: ${backup_archive}"
    
    # 停止容器
    if ! run "停止容器" docker_down "$project_dir"; then
        print_warn "容器停止失败，项目目录和备份均已保留，请检查后重试"
        return 1
    fi
    
    # 移除 nginx 配置
    local domain=$(project_get_domain "$project_dir")
    if [ -n "$domain" ]; then
        nginx_remove_site "$domain"
    fi
    
    # 重载 nginx
    nginx_reload 2>/dev/null || print_warn "nginx 重载失败，请手动检查配置"
    
    # 删除运行目录（备份已存在）
    rm -rf "$project_dir"
    print_success "项目运行目录已清除: ${project_dir}"
    print_info "如需彻底删除备份，可手动删除: ${TT_BACKUP_ROOT}/${name}/"
    
    # 更新状态
    state_set "projects.${name}" '{"name":"'${name}'","status":"removed","backup":"'${backup_archive}'","updated":"'$(date -Iseconds)'"}'
    ports_release_project "$name" 2>/dev/null || true
}
