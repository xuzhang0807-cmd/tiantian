#!/bin/bash
# =============================================================================
# TianTian Ops - input.sh
# Interactive input and validation helpers
# =============================================================================

normalize_domain() {
    local domain="$1"
    echo "$domain" | tr '[:upper:]' '[:lower:]' | sed 's#^https\?://##; s#/.*$##; s/[[:space:]]//g'
}

validate_domain() {
    local domain
    domain="$(normalize_domain "$1")"
    [ -n "$domain" ] || return 1
    [[ "$domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

port_in_use() {
    local port="$1"
    ss -tuln 2>/dev/null | awk '{print $5}' | grep -Eq "(^|:)${port}$"
}

prompt_required() {
    local label="$1"
    local value=""
    while true; do
        read -r -p "  ${label}: " value
        if [ -n "$value" ]; then
            echo "$value"
            return 0
        fi
        print_warn "${label} 不能为空，请重新输入"
    done
}

prompt_optional() {
    local label="$1"
    local default="${2:-}"
    local value=""
    if [ -n "$default" ]; then
        read -r -p "  ${label} [${default}]: " value
        echo "${value:-$default}"
    else
        read -r -p "  ${label}: " value
        echo "$value"
    fi
}

prompt_domain() {
    local label="${1:-域名}"
    local allow_empty="${2:-false}"
    local default="${3:-}"
    local value=""
    while true; do
        if [ -n "$default" ]; then
            read -r -p "  ${label} [${default}]: " value
            value="${value:-$default}"
        else
            read -r -p "  ${label}: " value
        fi
        value="$(normalize_domain "$value")"
        if [ -z "$value" ] && [ "$allow_empty" = "true" ]; then
            echo ""
            return 0
        fi
        if validate_domain "$value"; then
            echo "$value"
            return 0
        fi
        print_warn "域名格式不正确，请输入例如 example.com 或 app.example.com；输入空值可跳过"
    done
}

prompt_port() {
    local label="${1:-端口}"
    local default="${2:-}"
    local value=""
    while true; do
        if [ -n "$default" ]; then
            read -r -p "  ${label} [${default}]: " value
            value="${value:-$default}"
        else
            read -r -p "  ${label}: " value
        fi
        if ! validate_port "$value"; then
            print_warn "端口必须是 1-65535 的数字"
            continue
        fi
        if port_in_use "$value"; then
            print_warn "端口 ${value} 已被占用，请换一个端口"
            continue
        fi
        echo "$value"
        return 0
    done
}

check_domain_dns() {
    local domain="$1"
    local public_ip resolved
    public_ip="$(curl -fsS --connect-timeout 4 https://api.ipify.org 2>/dev/null || true)"
    resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, -)"
    if [ -z "$public_ip" ] || [ -z "$resolved" ]; then
        print_warn "无法完整检查 DNS：当前公网 IP 或域名解析为空"
        return 2
    fi
    if echo ",$resolved," | grep -q ",$public_ip,"; then
        print_success "DNS 检查通过：${domain} → ${public_ip}"
        return 0
    fi
    print_warn "DNS 可能未指向当前服务器"
    echo "  当前服务器 IP: ${public_ip}"
    echo "  域名解析 IP: ${resolved}"
    return 1
}
