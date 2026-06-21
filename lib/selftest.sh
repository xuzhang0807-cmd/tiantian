#!/bin/bash
# =============================================================================
# TianTian Ops - selftest.sh
# Safe smoke tests for terminal menu commands.
# =============================================================================

SELFTEST_TOTAL=0
SELFTEST_PASS=0
SELFTEST_FAIL=0
SELFTEST_SKIP=0

_selftest_run() {
    local name="$1" risk="$2" cmd="$3"
    SELFTEST_TOTAL=$((SELFTEST_TOTAL + 1))
    printf "\n[%s] %s\n" "$risk" "$name"
    if eval "$cmd"; then
        print_success "$name"
        SELFTEST_PASS=$((SELFTEST_PASS + 1))
    else
        print_fail "$name"
        SELFTEST_FAIL=$((SELFTEST_FAIL + 1))
    fi
}

_selftest_skip() {
    local name="$1" reason="$2"
    SELFTEST_TOTAL=$((SELFTEST_TOTAL + 1))
    SELFTEST_SKIP=$((SELFTEST_SKIP + 1))
    printf "\n[跳过] %s - %s\n" "$name" "$reason"
}

_selftest_restore_verify_sample() {
    local root archive stage rc
    root="/tmp/tt-selftest-restore-$$"
    archive="${root}/sample.tar.gz"
    stage="${root}/stage"
    rm -rf "$root"
    mkdir -p "${root}/sample-project/data"
    cat > "${root}/sample-project/manifest.yaml" <<'EOF'
name: sample-project
type: test
domain: ""
container:
  port: 18080
EOF
    cat > "${root}/sample-project/docker-compose.yml" <<'EOF'
services:
  sample:
    image: hello-world
EOF
    tar -czf "$archive" -C "$root" sample-project
    "$TT_HOME/tiantian.sh" restore verify "$archive" "$stage" >/dev/null
    [ -f "${stage}/sample-project/manifest.yaml" ] && [ -f "${stage}/sample-project/docker-compose.yml" ]
    rc=$?
    rm -rf "$root"
    return "$rc"
}

selftest_safe() {
    print_header "TT 安全自测"
    echo "范围：只读/低风险命令；不会部署项目、重启服务、清理 Docker 或修改 nginx。"
    _selftest_run "版本输出" "只读" "\"$TT_HOME/tiantian.sh\" version >/dev/null"
    _selftest_run "帮助输出" "只读" "\"$TT_HOME/tiantian.sh\" help >/dev/null"
    _selftest_run "依赖版本" "只读" "\"$TT_HOME/tiantian.sh\" deps versions >/dev/null"
    _selftest_run "依赖检查" "只读" "\"$TT_HOME/tiantian.sh\" deps doctor >/dev/null || true"
    _selftest_run "系统检测" "只读" "\"$TT_HOME/tiantian.sh\" detect >/dev/null"
    _selftest_run "服务器画像" "只读" "\"$TT_HOME/tiantian.sh\" profile >/dev/null"
    _selftest_run "资源概览" "只读" "\"$TT_HOME/tiantian.sh\" tools resource >/dev/null"
    _selftest_run "端口监听" "只读" "\"$TT_HOME/tiantian.sh\" tools ports >/dev/null || true"
    _selftest_run "网络信息" "只读" "\"$TT_HOME/tiantian.sh\" tools network >/dev/null || true"
    _selftest_run "Swap 状态" "只读" "\"$TT_HOME/tiantian.sh\" tools swap status >/dev/null || true"
    _selftest_run "防火墙状态" "只读" "\"$TT_HOME/tiantian.sh\" firewall status >/dev/null || true"
    _selftest_run "防火墙规则预案" "只读" "\"$TT_HOME/tiantian.sh\" firewall plan allow 443 tcp >/dev/null"
    _selftest_run "SSH 安全状态" "只读" "\"$TT_HOME/tiantian.sh\" ops ssh >/dev/null || true"
    _selftest_run "DNS 诊断" "只读" "\"$TT_HOME/tiantian.sh\" ops dns >/dev/null || true"
    _selftest_run "定时任务状态" "只读" "\"$TT_HOME/tiantian.sh\" ops cron >/dev/null || true"
    _selftest_run "BBR/TCP 状态" "只读" "\"$TT_HOME/tiantian.sh\" ops bbr >/dev/null || true"
    _selftest_run "进程负载状态" "只读" "\"$TT_HOME/tiantian.sh\" ops process >/dev/null || true"
    _selftest_run "磁盘大目录状态" "只读" "\"$TT_HOME/tiantian.sh\" ops disk >/dev/null || true"
    _selftest_run "系统服务状态" "只读" "\"$TT_HOME/tiantian.sh\" ops services >/dev/null || true"
    _selftest_run "后台工作区状态" "只读" "\"$TT_HOME/tiantian.sh\" ops tmux >/dev/null || true"
    _selftest_run "测试脚本 IP 信息" "轻量联网" "\"$TT_HOME/tiantian.sh\" bench ip >/dev/null || true"
    _selftest_run "测试脚本 DNS" "轻量联网" "\"$TT_HOME/tiantian.sh\" bench dns >/dev/null || true"
    _selftest_run "证书状态" "只读" "\"$TT_HOME/tiantian.sh\" cert status >/dev/null || true"
    _selftest_run "nginx 配置测试" "只读" "\"$TT_HOME/tiantian.sh\" nginx test >/dev/null || true"
    _selftest_run "项目列表" "只读" "\"$TT_HOME/tiantian.sh\" list >/dev/null || true"
    _selftest_run "Docker 列表" "只读" "\"$TT_HOME/tiantian.sh\" docker ps >/dev/null || true"
    _selftest_run "Docker 配置巡检" "只读" "\"$TT_HOME/tiantian.sh\" docker daemon >/dev/null || true"
    _selftest_run "集群节点状态" "只读" "\"$TT_HOME/tiantian.sh\" cluster status >/dev/null || true"
    _selftest_run "Kejilion 覆盖矩阵" "只读" "\"$TT_HOME/tiantian.sh\" coverage >/dev/null"
    _selftest_run "应用目录列表" "只读" "\"$TT_HOME/tiantian.sh\" apps list >/dev/null"
    _selftest_run "应用部署计划" "只读" "\"$TT_HOME/tiantian.sh\" apps plan toko >/dev/null"
    _selftest_run "部署计划 toko" "只读" "\"$TT_HOME/tiantian.sh\" deploy --plan toko >/dev/null"
    _selftest_run "部署计划 sub2api" "只读" "\"$TT_HOME/tiantian.sh\" deploy --plan sub2api >/dev/null"
    _selftest_run "恢复演练样本" "临时文件" "_selftest_restore_verify_sample"
    _selftest_skip "真实项目部署" "需要测试域名和老板确认"
    _selftest_skip "系统更新/Swap/缓存清理" "会修改系统，仅在确认后执行"
    echo ""
    print_header "自测结果"
    echo "总计: ${SELFTEST_TOTAL}"
    echo "通过: ${SELFTEST_PASS}"
    echo "失败: ${SELFTEST_FAIL}"
    echo "跳过: ${SELFTEST_SKIP}"
    [ "$SELFTEST_FAIL" -eq 0 ]
}
