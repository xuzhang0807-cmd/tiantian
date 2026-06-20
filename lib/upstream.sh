#!/bin/bash
# =============================================================================
# TianTian Ops - upstream.sh
# Read-only kejilion reference sync and report.
# =============================================================================

TT_UPSTREAM_ROOT="${TT_UPSTREAM_ROOT:-${TT_CACHE_ROOT}/upstream}"
TT_KEJILION_URL="${TT_KEJILION_URL:-https://raw.githubusercontent.com/kejilion/sh/main/kejilion.sh}"

upstream_sync_kejilion() {
    mkdir -p "$TT_UPSTREAM_ROOT"
    local target="${TT_UPSTREAM_ROOT}/kejilion.sh"
    local tmp="${target}.tmp"
    print_header "同步 kejilion 参考脚本"
    print_warn "仅下载为参考资料，不执行它的安装/部署函数。"
    if has_cmd curl; then
        run_or_die "下载 kejilion.sh" curl -fsSL "$TT_KEJILION_URL" -o "$tmp"
    elif has_cmd wget; then
        run_or_die "下载 kejilion.sh" wget -qO "$tmp" "$TT_KEJILION_URL"
    else
        die "缺少 curl/wget，无法下载"
    fi
    bash -n "$tmp"
    mv "$tmp" "$target"
    print_success "已保存: $target"
    upstream_report_kejilion
}

upstream_report_kejilion() {
    local src="${1:-${TT_UPSTREAM_ROOT}/kejilion.sh}"
    [ -f "$src" ] || die "未找到 kejilion.sh，请先运行: tt upstream sync"
    print_header "kejilion 参考报告"
    echo "文件: $src"
    echo "行数: $(wc -l < "$src" | tr -d ' ')"
    echo "版本: $(grep -m1 '^sh_v=' "$src" | cut -d= -f2- | tr -d '"' || echo unknown)"
    echo ""
    print_title "可借鉴菜单"
    grep -nE 'echo -e "\$\{gl_kjlan\}[0-9]+\.|echo "[0-9]+\.' "$src" | sed -n '1,80p' || true
    echo ""
    print_title "TT 冲突风险关键词"
    grep -nE 'docker stop nginx|/home/web/nginx\.conf|/home/web/conf\.d|/home/web/stream\.d|listen 443|443:443|standalone|certonly|send_stats|/usr/local/bin/k|/usr/bin/k' "$src" | sed -n '1,120p' || true
    echo ""
    print_title "建议"
    echo "- 菜单/工具/Docker/测试脚本可人工迁移到 TT。"
    echo "- 项目部署函数不可直接执行，必须翻译成 TT blueprint。"
    echo "- TT 的公网 443 必须继续由 stream/SNI 总入口管理。"
}

upstream_guard_check() {
    print_header "TT 网关保护检查"
    local stream_tpl="${TT_HOME}/blueprints/network/stream.conf.tpl"
    local site_tpl="${TT_HOME}/templates/nginx/site-4443.conf.tpl"
    grep -q 'ssl_preread on' "$stream_tpl" || die "stream 模板缺少 ssl_preread on"
    grep -q 'listen 443' "$stream_tpl" || die "stream 模板缺少公网 443 监听"
    grep -q '127.0.0.1:4443' "$stream_tpl" || die "stream 模板缺少网站内部 4443 upstream"
    grep -q 'listen 127.0.0.1:4443 ssl' "$site_tpl" || die "站点模板不是内部 4443 HTTPS"
    print_success "网关保护检查通过"
}
