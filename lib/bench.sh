#!/bin/bash
# =============================================================================
# TianTian Ops - bench.sh
# Lightweight network/server test panel. Heavy benchmark scripts are opt-in only.
# =============================================================================

bench_ip() {
    print_header "IP 信息"
    local ipv4 ipv6
    ipv4="$(curl -fsS --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo unknown)"
    ipv6="$(curl -fsS --max-time 5 https://v6.ipinfo.io/ip 2>/dev/null || echo none)"
    echo "公网 IPv4: $ipv4"
    echo "公网 IPv6: $ipv6"
    echo ""
    print_title "ipinfo 摘要"
    curl -fsS --max-time 8 https://ipinfo.io/json 2>/dev/null | python3 -m json.tool 2>/dev/null | sed -n '1,40p' || print_warn "无法获取 ipinfo JSON"
}

bench_dns() {
    print_header "DNS 解析测试"
    local domains=(google.com github.com cloudflare.com kazerush.xyz)
    local resolver
    echo "系统 resolv.conf:"
    sed -n '1,8p' /etc/resolv.conf 2>/dev/null || true
    echo ""
    for resolver in system 1.1.1.1 8.8.8.8; do
        print_title "Resolver: $resolver"
        for domain in "${domains[@]}"; do
            if [ "$resolver" = "system" ]; then
                getent ahosts "$domain" 2>/dev/null | awk 'NR==1{print "  '$domain' -> "$1}' || echo "  $domain -> failed"
            elif has_cmd dig; then
                local answer
                answer="$(dig +short +time=3 +tries=1 "@$resolver" "$domain" A 2>/dev/null | head -n1)"
                printf "  %-18s -> %s\n" "$domain" "${answer:-failed}"
            else
                print_warn "缺少 dig，跳过指定 DNS 服务器测试"
                break
            fi
        done
        echo ""
    done
}

bench_ping() {
    print_header "连通性测试"
    local hosts=(1.1.1.1 8.8.8.8 github.com cloudflare.com)
    local host
    for host in "${hosts[@]}"; do
        printf "%-18s" "$host"
        if ping -c 3 -W 2 "$host" 2>/dev/null | awk -F'= ' '/rtt|round-trip/ {split($2, parts, "/"); printf "min/avg/max=%s/%s/%sms\n", parts[1], parts[2], parts[3]; found=1} END {exit found?0:1}'; then
            true
        else
            echo "failed"
        fi
    done
}

bench_http() {
    print_header "HTTP 延迟测试"
    local urls=(https://www.cloudflare.com https://github.com https://ipinfo.io/ip)
    local url
    for url in "${urls[@]}"; do
        printf '%s ' "$url"
        curl -o /dev/null -sS -L --max-time 10 -w "code=%{http_code} dns=%{time_namelookup}s connect=%{time_connect}s total=%{time_total}s\n" "$url" 2>/dev/null || echo "failed"
    done
}

bench_menu() {
    while true; do
        echo ""
        print_title "测试脚本合集"
        echo ""
        echo "  1) IP 信息 ✅"
        echo "  2) DNS 解析测试 ✅"
        echo "  3) Ping 连通性 ✅"
        echo "  4) HTTP 延迟测试 ✅"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/test> " choice
        case "$choice" in
            1) bench_ip ;;
            2) bench_dns ;;
            3) bench_ping ;;
            4) bench_http ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
