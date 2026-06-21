#!/bin/bash
# =============================================================================
# TianTian Ops - bench.sh
# Lightweight network/server test panel plus opt-in heavy benchmarks.
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

bench_speed() {
    print_header "网络速度测试"
    local servers=(
        "https://speed.cloudflare.com/__down?bytes=104857600"
        "https://ash-speed.hetzner.com/100MB.bin"
        "https://speed.hetzner.de/100MB.bin"
    )
    print_warn "注意：每次测试会下载约 100MB 数据，请留意流量计费。"
    echo ""
    for url in "${servers[@]}"; do
        local label
        label="$(echo "$url" | sed 's|https://||; s|/.*||')"
        printf "%-25s " "$label"
        local result
        result="$(curl -o /dev/null -sS -w "size=%{size_download} speed=%{speed_download}B/s time=%{time_total}s code=%{http_code}" --max-time 60 "$url" 2>/dev/null || echo "failed")"
        if echo "$result" | grep -q 'speed='; then
            local size speed code
            size="$(echo "$result" | sed -n 's/.*size=\([0-9]*\).*/\1/p')"
            speed="$(echo "$result" | sed -n 's/.*speed=\([0-9]*\).*/\1/p')"
            code="$(echo "$result" | sed -n 's/.*code=\([0-9]*\).*/\1/p')"
            if [ "$speed" -ge 1000000 ]; then
                printf "%.1f MB/s  (%s MB, code=%s)\n" "$(echo "scale=1; $speed/1048576" | bc 2>/dev/null || echo "?" )" "$((size/1048576))" "$code"
            else
                printf "%.1f KB/s  (%s KB, code=%s)\n" "$(echo "scale=1; $speed/1024" | bc 2>/dev/null || echo "?" )" "$((size/1024))" "$code"
            fi
        else
            echo "$result"
        fi
    done
    echo ""
    print_info "若需本地 speedtest-cli，可运行: tt deps install recommended"
}

bench_streaming() {
    print_header "流媒体解锁检测"
    echo "源: 通过 HTTP 首响应码探测区域限制状态（不发送账号信息）。"
    echo ""
    local tests=(
        "Netflix:https://www.netflix.com/title/80018499:301"
        "YouTube Premium:https://www.youtube.com/premium:200"
        "Disney+:https://www.disneyplus.com/:200"
        "Spotify:https://api.spotify.com/v1/browse/new-releases:401"
        "B站港澳台:https://api.bilibili.com/x/web-interface/zone:200"
    )
    for test in "${tests[@]}"; do
        local label url expect
        label="${test%%:*}"
        expect="${test##*:}"
        url="${test#${label}:}"
        url="${url%:${expect}}"
        printf "%-20s " "$label"
        local code
        code="$(curl -o /dev/null -sS -w "%{http_code}" --max-time 8 "$url" 2>/dev/null)"
        [ -z "$code" ] && code="000"
        if [ "$code" = "$expect" ]; then
            echo "✅ 可达 (HTTP $code)"
        elif [ "$code" = "403" ] || [ "$code" = "451" ]; then
            echo "⛔ 受限 (HTTP $code)"
        elif [ "$code" = "302" ] || [ "$code" = "301" ]; then
            echo "🔄 重定向 (HTTP $code，可能需登录)"
        elif [ "$code" = "000" ]; then
            echo "❌ 不可达 (连接失败/超时)"
        else
            echo "❓ HTTP $code"
        fi
    done
    echo ""
    print_info "结果仅供参考：重定向/受限不等于地域封锁，需以实际播放为准。"
}

bench_hardware() {
    print_header "硬件基准测试"
    print_warn "仅使用 dd 做轻量 I/O 测试；不会写入生产数据目录。"
    echo ""

    print_title "CPU 信息"
    awk -F': ' '/model name/ {print "  " $2; exit}' /proc/cpuinfo 2>/dev/null || true
    printf "  核心数: %s 线程\n" "$(nproc 2>/dev/null || echo unknown)"
    echo ""

    print_title "内存"
    free -h 2>/dev/null | sed -n '1,2p' | sed 's/^/  /'
    echo ""

    print_title "磁盘顺序写 (dd 1GB 临时文件)"
    local tmpfile="/tmp/tt-bench-dd-$$.tmp"
    local result
    result="$(dd if=/dev/zero of="$tmpfile" bs=1M count=1024 2>&1 || true)"
    rm -f "$tmpfile"
    echo "$result" | tail -n1 | sed 's/^/  /'
    echo ""

    print_title "磁盘顺序读 (dd 1GB 临时文件)"
    dd if=/dev/zero of="$tmpfile" bs=1M count=1024 2>/dev/null
    result="$(dd if="$tmpfile" of=/dev/null bs=1M count=1024 2>&1 || true)"
    rm -f "$tmpfile"
    echo "$result" | tail -n1 | sed 's/^/  /'
    echo ""

    print_title "OpenSSL 速度 (单线程)"
    if has_cmd openssl; then
        openssl speed sha256 rsa2048 2>/dev/null | grep -E '^(md5|sha|rsa|Doing|The)' | sed -n '1,8p' | sed 's/^/  /'
    else
        print_info "openssl 不可用，跳过"
    fi
    echo ""
    print_info "以上为快速参考，若需深度测试建议安装 sysbench/fio。"
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
        echo "  5) 网络速度测试 ✅"
        echo "  6) 流媒体解锁检测 ✅"
        echo "  7) 硬件基准测试 ✅"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/test> " choice
        case "$choice" in
            1) bench_ip ;;
            2) bench_dns ;;
            3) bench_ping ;;
            4) bench_http ;;
            5) bench_speed ;;
            6) bench_streaming ;;
            7) bench_hardware ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
