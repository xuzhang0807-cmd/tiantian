#!/bin/bash
# =============================================================================
# TianTian Ops - cert.sh
# 证书系统：certbot 申请、同步到 /home/web/certs、自动续期 hook
# =============================================================================

CERT_DIR="/home/web/certs"
LETSENCRYPT_DIR="/home/web/letsencrypt"
WEBROOT="/home/web/html"
HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
TT_SYNC_HOOK="${HOOK_DIR}/tt-sync.sh"

# --- 检查 certbot ---
cert_check() {
    if has_cmd certbot; then
        local ver=$(certbot --version 2>/dev/null | head -1)
        echo -e "  Certbot       ${GREEN}${ver}${NC}"
        return 0
    else
        echo -e "  Certbot       ${YELLOW}未安装${NC}"
        return 1
    fi
}

# --- 安装 certbot ---
cert_install() {
    if has_cmd certbot; then
        print_success "certbot 已安装"
        return 0
    fi
    print_info "安装 certbot ..."
    if has_cmd apt; then
        run_or_die "安装 certbot" apt-get update -qq && apt-get install -y -qq certbot
    elif has_cmd snap; then
        run_or_die "安装 certbot" snap install --classic certbot
    else
        die "无法安装 certbot：不支持的包管理器"
    fi
}

# --- 申请证书 ---
cert_obtain() {
    local domain="$1"
    local email="${2:-admin@${domain}}"
    
    print_header "申请证书: ${domain}"
    
    # 确保 webroot 目录存在
    mkdir -p "$WEBROOT"
    
    # certbot webroot 模式（不需要停止 nginx）
    run_or_die "申请证书" certbot certonly \
        --webroot \
        -w "$WEBROOT" \
        -d "$domain" \
        --email "$email" \
        --non-interactive \
        --agree-tos \
        --keep-until-expiring
    
    print_success "证书申请成功"
    
    # 同步证书到 /home/web/certs
    cert_sync "$domain"
}

# --- 同步证书到 /home/web/certs ---
cert_sync() {
    local domain="$1"
    local live_dir="/etc/letsencrypt/live/${domain}"
    
    if [ ! -d "$live_dir" ]; then
        log_warn "letsencrypt 目录不存在: $live_dir"
        return 1
    fi
    
    print_info "同步证书: ${domain} → ${CERT_DIR}"
    
    mkdir -p "$CERT_DIR"
    
    cp "${live_dir}/fullchain.pem" "${CERT_DIR}/${domain}_cert.pem"
    cp "${live_dir}/privkey.pem"   "${CERT_DIR}/${domain}_key.pem"
    
    # 设置合理的权限
    chmod 644 "${CERT_DIR}/${domain}_cert.pem"
    chmod 600 "${CERT_DIR}/${domain}_key.pem"
    
    print_success "证书已同步"
}

# --- 部署自动同步 hook ---
cert_deploy_hook() {
    mkdir -p "$HOOK_DIR"
    
    cat > "$TT_SYNC_HOOK" <<'HOOKEOF'
#!/bin/bash
# TianTian Ops - Cert 自动同步 Hook
# 在 certbot 续期后自动同步证书

TT_HOME="/opt/tiantian"
source "${TT_HOME}/lib/core.sh" 2>/dev/null

DOMAIN="${RENEWED_DOMAIN:-$1}"
CERT_DIR="/home/web/certs"
LIVE_DIR="/etc/letsencrypt/live/${DOMAIN}"

if [ -z "$DOMAIN" ]; then
    echo "[tt-sync] 缺少域名参数"
    exit 0
fi

echo "[tt-sync] $(date) 同步证书: ${DOMAIN}"

if [ -d "$LIVE_DIR" ]; then
    cp "${LIVE_DIR}/fullchain.pem" "${CERT_DIR}/${DOMAIN}_cert.pem"
    cp "${LIVE_DIR}/privkey.pem"   "${CERT_DIR}/${DOMAIN}_key.pem"
    chmod 644 "${CERT_DIR}/${DOMAIN}_cert.pem"
    chmod 600 "${CERT_DIR}/${DOMAIN}_key.pem"
    echo "[tt-sync] 证书已同步"

    # 尝试 reload nginx
    if command -v tt &>/dev/null; then
        tt nginx reload 2>/dev/null
    elif docker exec nginx nginx -s reload 2>/dev/null; then
        echo "[tt-sync] nginx 已重载"
    fi
else
    echo "[tt-sync] 证书目录不存在: ${LIVE_DIR}"
fi
HOOKEOF
    
    chmod +x "$TT_SYNC_HOOK"
    print_success "自动同步 hook 已部署: ${TT_SYNC_HOOK}"
}

# --- 查看证书状态 ---
cert_status() {
    print_header "证书状态"
    echo ""
    
    if [ ! -d "$CERT_DIR" ]; then
        print_info "证书目录不存在: ${CERT_DIR}"
        return
    fi
    
    for cert in "$CERT_DIR"/*_cert.pem; do
        [ -f "$cert" ] || continue
        local domain=$(basename "$cert" _cert.pem)
        local subj=$(openssl x509 -subject -noout -in "$cert" 2>/dev/null | sed 's/.*CN=//')
        local exp=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
        
        if [ -n "$exp" ]; then
            local exp_ts=$(date -d "$exp" +%s 2>/dev/null)
            local now_ts=$(date +%s)
            local days_left=$(( (exp_ts - now_ts) / 86400 ))
            
            local icon="${GREEN}✓${NC}"
            [ "$days_left" -lt 30 ] && icon="${YELLOW}⚠${NC}"
            [ "$days_left" -lt 0 ] && icon="${RED}✗${NC}"
            
            printf "  %s %-25s 到期: %-25s 剩余: %s 天\n" "$icon" "$domain" "$exp" "$days_left"
        fi
    done
    echo ""
}

# --- 强制续期 ---
cert_renew() {
    print_info "检查并续期所有证书 ..."
    if has_cmd certbot; then
        certbot renew --quiet --webroot -w "$WEBROOT"
        print_success "续期检查完成"
    else
        print_fail "certbot 未安装"
        return 1
    fi
}
