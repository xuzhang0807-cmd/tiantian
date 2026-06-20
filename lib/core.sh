#!/bin/bash
# =============================================================================
# TianTian Ops - core.sh
# 基础函数库：日志、错误处理、命令执行、颜色输出
# =============================================================================

TT_VERSION="0.2.0"
TT_HOME="${TT_HOME:-/opt/tiantian}"
TT_LOG="${TT_HOME}/logs/tt.log"
TT_STATE="${TT_HOME}/state/projects.json"
TT_BACKUP_ROOT="${TT_BACKUP_ROOT:-/home/tt-backups}"
TT_SECRETS_ROOT="${TT_SECRETS_ROOT:-/home/tt-secrets}"
TT_CACHE_ROOT="${TT_CACHE_ROOT:-/home/tt-cache}"

# Ensure runtime directories exist after a fresh Git clone.
mkdir -p "$(dirname "$TT_LOG")" "$(dirname "$TT_STATE")" 2>/dev/null || true

# --- 颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- 日志函数 ---
_log() {
    local level="$1"; shift
    local msg="$*"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${ts}] [${level}] ${msg}" >> "$TT_LOG"
}

log_info()  { _log INFO "$@"; }
log_warn()  { _log WARN "$@"; echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { _log ERROR "$@"; echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- 打印函数 ---
print_success() { echo -e "${GREEN}✓${NC} $*"; }
print_fail()    { echo -e "${RED}✗${NC} $*"; }
print_info()    { echo -e "${BLUE}→${NC} $*"; }
print_warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
print_header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }
print_title()   { echo -e "${BOLD}${BLUE}$*${NC}"; }

# --- 错误处理 ---
die() {
    log_error "$@"
    echo -e "${RED}[FATAL]${NC} $*" >&2
    exit 1
}

# --- 命令执行 ---
# run "描述" command args...
run() {
    local desc="$1"; shift
    print_info "$desc ..."
    log_info "RUN: $*"
    if "$@"; then
        print_success "$desc 完成"
        log_info "OK: $desc"
        return 0
    else
        local rc=$?
        print_fail "$desc 失败 (exit=$rc)"
        log_error "FAIL: $desc (exit=$rc)"
        return $rc
    fi
}

# run_quiet: 静默执行，失败才报错
run_quiet() {
    local desc="$1"; shift
    log_info "RUN(quiet): $*"
    if "$@" >/dev/null 2>&1; then
        log_info "OK: $desc"
        return 0
    else
        print_fail "$desc 失败"
        return 1
    fi
}

# run_or_die: 失败就退出
run_or_die() {
    local desc="$1"; shift
    if ! run "$desc" "$@"; then
        die "$desc 失败，终止执行"
    fi
}

# --- 确认函数 ---
confirm() {
    local prompt="${1:-确认继续？}"
    read -p "$(echo -e ${YELLOW}${prompt}${NC} [y/N]) " yn
    case "$yn" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

# --- JSON 状态管理 ---
# 极简 JSON 读写（不依赖 jq，纯 bash）
state_init() {
    if [ ! -f "$TT_STATE" ]; then
        echo '{"projects":{},"updated":"","version":"0.2"}' > "$TT_STATE"
    fi
}

state_set() {
    # state_set dotted.key '{"json":"value"}'
    local key="$1" val="$2"
    local tmp="${TT_STATE}.tmp"
    mkdir -p "$(dirname "$TT_STATE")"
    python3 - "$TT_STATE" "$tmp" "$key" "$val" <<'PY'
import json, sys, datetime
path, tmp, key, raw = sys.argv[1:5]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {"projects": {}, "updated": "", "version": "0.2"}
value = json.loads(raw)
node = data
parts = key.split('.')
for part in parts[:-1]:
    child = node.get(part)
    if not isinstance(child, dict):
        child = {}
        node[part] = child
    node = child
node[parts[-1]] = value
data['updated'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
with open(tmp, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
    local rc=$?
    [ "$rc" -eq 0 ] && mv "$tmp" "$TT_STATE"
    return "$rc"
}

state_get() {
    # state_get dotted.key
    local key="$1"
    python3 - "$TT_STATE" "$key" <<'PY' 2>/dev/null
import json, sys
path, key = sys.argv[1:3]
with open(path) as f:
    data = json.load(f)
node = data
for part in key.split('.'):
    if not isinstance(node, dict) or part not in node:
        node = ''
        break
    node = node[part]
print(json.dumps(node, ensure_ascii=False))
PY
}

# --- 工具函数 ---
is_root() {
    [ "$(id -u)" -eq 0 ]
}

check_root() {
    if ! is_root; then
        die "需要 root 权限，请用 sudo 运行"
    fi
}

# 检查命令是否存在
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# 获取系统信息
get_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        uname -s
    fi
}

# 初始化
state_init
log_info "core.sh loaded (TT v${TT_VERSION})"
