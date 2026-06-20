#!/bin/bash
# =============================================================================
# TianTian Ops - doctor.sh
# Read-only readiness checks
# =============================================================================

doctor_check() {
    print_header "TianTian Ops 诊断"
    echo ""
    print_title "基础命令"
    for cmd in docker curl python3 tar ss; do
        if has_cmd "$cmd"; then
            echo "  ✓ ${cmd}"
        else
            echo "  ✗ ${cmd} 未安装"
        fi
    done
    echo ""

    deps_doctor || true
    echo ""

    print_title "目录"
    for dir in "$TT_HOME" /home/web /home/docker "$TT_BACKUP_ROOT" "$TT_SECRETS_ROOT"; do
        if [ -d "$dir" ]; then
            echo "  ✓ ${dir}"
        else
            echo "  ⚠ ${dir} 不存在（需要时会创建）"
        fi
    done
    echo ""

    print_title "nginx 网关"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nginx'; then
        echo "  ✓ 检测到 Docker nginx 容器"
        docker exec nginx nginx -t >/dev/null 2>&1 && echo "  ✓ nginx 配置语法通过" || echo "  ✗ nginx 配置语法失败"
    elif has_cmd nginx; then
        echo "  ✓ 检测到宿主机 nginx"
        nginx -t >/dev/null 2>&1 && echo "  ✓ nginx 配置语法通过" || echo "  ✗ nginx 配置语法失败"
    else
        echo "  ⚠ 未检测到 nginx"
    fi
    if [ -f /home/web/nginx.conf ] && grep -q 'stream' /home/web/nginx.conf; then
        echo "  ✓ /home/web stream/SNI 网关存在"
    else
        echo "  ⚠ 未确认 /home/web stream/SNI 网关"
    fi
    echo ""

    print_title "端口池"
    ports_list
}
