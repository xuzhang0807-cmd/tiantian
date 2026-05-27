#!/bin/bash
# =============================================================================
# TianTian Ops - nginx.sh
# nginx 配置管理：模板渲染、生成 4443 站点配置、reload
# 严格遵守：不占用公网 443，走 127.0.0.1:4443
# =============================================================================

NGINX_CONF_DIR="${NGINX_CONF_DIR:-/home/web/conf.d}"
NGINX_CERTS_DIR="/home/web/certs"
NGINX_TEMPLATE="${TT_HOME}/templates/nginx/site-4443.conf.tpl"
TT_NGINX_CONF_DIR="/home/web/conf.d"

# --- 检查现有 nginx 体系 ---
nginx_check_gateway() {
    # 检查 /home/web/nginx.conf 是否存在 stream 块
    if [ -f /home/web/nginx.conf ]; then
        if grep -q "stream" /home/web/nginx.conf; then
            echo "✓ 检测到 stream 网关，将使用 4443 反代模式"
            return 0
        fi
    fi
    # 检查 nginx 是否直接监听 443
    if ss -tlnp 2>/dev/null | grep -q ':443 '; then
        echo "✓ 检测到 nginx 监听公网 443，将使用 4443 反代模式"
        return 0
    fi
    echo "⚠ 未检测到现有 nginx 网关，可能直接使用 443"
    return 1
}

# --- 渲染 nginx 站点配置 ---
nginx_render_site() {
    local domain="$1"
    local port="$2"
    local conf_file="${TT_NGINX_CONF_DIR}/${domain}.conf"
    
    print_info "生成 nginx 配置: ${domain} → 127.0.0.1:${port}"
    
    if [ ! -f "$NGINX_TEMPLATE" ]; then
        # 内置模板（如果没有模板文件）
        cat > "$conf_file" <<'NGINXEOF'
# TianTian Ops - auto-generated
# Domain: {{DOMAIN}}
# Port: {{PORT}}

server {
    listen 127.0.0.1:4443 ssl;
    http2 on;
    server_name {{DOMAIN}};

    ssl_certificate     /etc/nginx/certs/{{DOMAIN}}_cert.pem;
    ssl_certificate_key /etc/nginx/certs/{{DOMAIN}}_key.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    location / {
        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 90;
        proxy_connect_timeout 30;
        proxy_buffering off;
        client_max_body_size 100m;
    }
}
NGINXEOF
        # 替换占位符
        sed -i "s/{{DOMAIN}}/${domain}/g" "$conf_file"
        sed -i "s/{{PORT}}/${port}/g" "$conf_file"
    else
        # 使用外部模板渲染
        cp "$NGINX_TEMPLATE" "$conf_file"
        sed -i "s/{{DOMAIN}}/${domain}/g" "$conf_file"
        sed -i "s/{{PORT}}/${port}/g" "$conf_file"
    fi
    
    print_success "配置已生成: ${conf_file}"
}

# --- 检测 nginx 并测试配置 ---
nginx_test() {
    print_info "测试 nginx 配置 ..."
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nginx'; then
        if docker exec nginx nginx -t 2>&1; then
            print_success "nginx 配置测试通过"
            return 0
        else
            print_fail "nginx 配置测试失败"
            return 1
        fi
    elif has_cmd nginx; then
        if nginx -t 2>&1; then
            print_success "nginx 配置测试通过"
            return 0
        else
            print_fail "nginx 配置测试失败"
            return 1
        fi
    else
        print_fail "nginx 未运行"
        return 1
    fi
}

# --- reload nginx ---
nginx_reload() {
    print_info "重载 nginx ..."
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nginx'; then
        if docker exec nginx nginx -s reload 2>&1; then
            print_success "nginx 重载成功"
            log_info "nginx reload 成功 (docker)"
            return 0
        else
            print_fail "nginx 重载失败"
            log_error "nginx reload 失败"
            return 1
        fi
    elif has_cmd nginx; then
        if nginx -s reload 2>&1; then
            print_success "nginx 重载成功"
            log_info "nginx reload 成功"
            return 0
        else
            print_fail "nginx 重载失败"
            return 1
        fi
    else
        print_fail "nginx 未运行"
        return 1
    fi
}

# --- 移除站点配置 ---
nginx_remove_site() {
    local domain="$1"
    local conf_file="${TT_NGINX_CONF_DIR}/${domain}.conf"
    
    if [ -f "$conf_file" ]; then
        print_info "移除 nginx 配置: ${domain}"
        rm -f "$conf_file"
        print_success "已移除: ${conf_file}"
    else
        log_warn "配置文件不存在: ${conf_file}"
    fi
}

# --- 列出所有 tt 管理的站点 ---
nginx_list_sites() {
    echo ""
    print_title "TT 管理的 nginx 站点："
    echo ""
    if [ -d "$TT_NGINX_CONF_DIR" ]; then
        for conf in "$TT_NGINX_CONF_DIR"/*.conf; do
            [ -f "$conf" ] || continue
            local domain=$(basename "$conf" .conf)
            local port=$(grep "proxy_pass http://127.0.0.1:" "$conf" 2>/dev/null | head -1 | sed 's/.*://' | tr -d ';')
            printf "  %-30s → 127.0.0.1:%-6s\n" "$domain" "${port:-?}"
        done
    fi
    echo ""
}

# --- 健康检查 ---
nginx_health_check() {
    # 检查 nginx 是否可达
    if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80/ >/dev/null 2>&1; then
        print_success "nginx 健康检查通过"
        return 0
    else
        print_fail "nginx 健康检查失败"
        return 1
    fi
}
