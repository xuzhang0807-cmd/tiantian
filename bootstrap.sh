#!/bin/bash
# =============================================================================
# TianTian Ops - Bootstrap 一键安装
# 用法: bash <(curl -sL https://your-url/tt.sh)
# =============================================================================

set -e

INSTALL_DIR="/opt/tiantian"
REPO_URL="${TT_REPO_URL:-https://github.com/xuzhang0807-cmd/tiantian.git}"
TT_URL="${TT_INSTALL_URL:-https://raw.githubusercontent.com/xuzhang0807-cmd/tiantian/main/bootstrap.sh}"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     TianTian Ops 一键安装            ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# 检查 root
if [ "$(id -u)" -ne 0 ]; then
    echo "  需要 root 权限，请使用: sudo bash bootstrap.sh"
    exit 1
fi

# 检测系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "  系统: $PRETTY_NAME"
fi

# 检查基础依赖
ensure_pkg() {
    local cmd="$1" pkg="$2"
    command -v "$cmd" >/dev/null 2>&1 && return 0
    echo "  安装 ${pkg} ..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq "$pkg"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "$pkg"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$pkg"
    else
        echo "  无法识别包管理器，请手动安装 ${pkg}"
        return 1
    fi
}

ensure_pkg git git || exit 1
ensure_pkg curl curl || true
ensure_pkg python3 python3 || true
ensure_pkg tar tar || true

# 克隆/更新
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "  更新 TianTian Ops ..."
    cd "$INSTALL_DIR"
    git pull --ff-only 2>/dev/null || echo "  ⚠ git pull 失败，使用现有版本"
else
    if [ -d "$INSTALL_DIR" ]; then
        echo "  目录已存在但非 git 仓库，备份 ..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    echo "  克隆 TianTian Ops ..."
    if ! git clone "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
        echo "  ⚠ 无法从远程拉取，将使用本地版本"
        # 如果本地存在，就继续
        if [ ! -f "${INSTALL_DIR}/tiantian.sh" ]; then
            echo "  ✗ 本地也不存在 tiantian.sh"
            exit 1
        fi
    fi
fi

# 确保目录结构
mkdir -p "${INSTALL_DIR}"/{lib,templates/{nginx,docker},profiles,projects,state,logs}

# 设置权限
chmod +x "${INSTALL_DIR}"/tiantian.sh 2>/dev/null || true
chmod +x "${INSTALL_DIR}"/lib/*.sh 2>/dev/null || true

# 安装 tt 命令
ln -sf "${INSTALL_DIR}/tiantian.sh" /usr/local/bin/tt
echo "  ✓ tt 命令已安装到 /usr/local/bin/tt"

# 初始化
echo ""
echo "  启动 TianTian Ops ..."
echo ""

# 执行初始化检测
cd "$INSTALL_DIR"
bash tiantian.sh deps doctor || true

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║   TianTian Ops 安装完成！            ║"
echo "  ║   运行 tt 进入控制台                  ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
