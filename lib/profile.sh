#!/bin/bash
# =============================================================================
# TianTian Ops - profile.sh
# 服务器画像系统：根据硬件资源自动分级，推荐/禁止部署方案
# =============================================================================

PROFILE_FILE="${TT_HOME}/profiles/current.txt"

# --- 分级逻辑 ---
classify_server() {
    local cpu=$(detect_cpu)
    local mem=$(detect_mem_mb)
    local disk_free_raw=$(df / 2>/dev/null | awk 'NR==2 {print $4}')
    local disk_free_gb=$((disk_free_raw / 1024 / 1024))
    
    if [ "$cpu" -le 2 ] && [ "$mem" -le 2048 ]; then
        echo "small"
    elif [ "$cpu" -le 4 ] && [ "$mem" -le 4096 ]; then
        echo "medium"
    elif [ "$cpu" -le 8 ] && [ "$mem" -le 8192 ]; then
        echo "large"
    else
        echo "xlarge"
    fi
}

# --- 加载 profile 配置 ---
load_profile() {
    local profile="$1"
    local pf="${TT_HOME}/profiles/${profile}.yaml"
    if [ ! -f "$pf" ]; then
        log_warn "profile 文件不存在: $pf"
        return 1
    fi
    # 用 python3 解析 YAML
    python3 -c "
import yaml,sys
with open('$pf') as f: d=yaml.safe_load(f)
print(json.dumps(d))
" 2>/dev/null
}

# --- 推荐部署列表 ---
get_recommended() {
    local profile="$1"
    python3 -c "
import yaml,json
with open('${TT_HOME}/profiles/${profile}.yaml') as f: d=yaml.safe_load(f)
for item in d.get('recommended',[]): print(item)
" 2>/dev/null
}

# --- 禁止部署列表 ---
get_forbidden() {
    local profile="$1"
    python3 -c "
import yaml,json
with open('${TT_HOME}/profiles/${profile}.yaml') as f: d=yaml.safe_load(f)
for item in d.get('forbidden',[]): print(item)
" 2>/dev/null
}

# --- 资源预估 ---
estimate_resources() {
    local profile="$1"
    local cpu=$(detect_cpu)
    local mem=$(detect_mem_mb)
    local mem_avail=$(detect_mem_avail_mb)
    local disk_free=$(detect_disk_free)
    local disk_total=$(detect_disk_total)
    local os=$(detect_os)
    
    # 估算可部署项目数
    local max_projects=0
    case "$profile" in
        small)  max_projects=2 ;;
        medium) max_projects=5 ;;
        large)  max_projects=10 ;;
        xlarge) max_projects=20 ;;
    esac
    
    # 检查已部署项目
    local deployed=0
    if [ -f "$TT_STATE" ]; then
        deployed=$(python3 -c "import json; d=json.load(open('$TT_STATE')); print(len(d.get('projects',{})))" 2>/dev/null || echo 0)
    fi
    
    echo ""
    print_title "📊 资源预估"
    echo ""
    printf "  服务器等级：     ${BOLD}${GREEN}%s${NC}\n" "$profile"
    printf "  CPU 核心：       %s 核\n" "$cpu"
    printf "  总内存：         %s MB\n" "$mem"
    printf "  当前可用内存：   ${YELLOW}%s MB${NC}\n" "$mem_avail"
    printf "  磁盘剩余：       %s / %s\n" "$disk_free" "$disk_total"
    printf "  已部署项目：     %s\n" "$deployed"
    printf "  推荐上限：       %s 个项目\n" "$max_projects"
    printf "  剩余可部署：     ${GREEN}%s${NC} 个\n" $((max_projects - deployed))
    echo ""
}

# --- 检查是否可以部署 ---
can_deploy() {
    local profile="$1"
    local project_type="$2"
    
    # 检查是否在禁止列表
    local forbidden=$(get_forbidden "$profile")
    if echo "$forbidden" | grep -qw "$project_type"; then
        echo -e "${RED}✗ 服务器等级 ${profile} 禁止部署 ${project_type}${NC}"
        return 1
    fi
    
    # 检查内存是否足够（粗略估算）
    local mem_avail=$(detect_mem_avail_mb)
    case "$project_type" in
        postgres|mysql|ai)
            if [ "$mem_avail" -lt 512 ]; then
                echo -e "${RED}✗ 可用内存不足 512MB，无法部署 ${project_type}${NC}"
                return 1
            fi
            ;;
        wordpress|node)
            if [ "$mem_avail" -lt 256 ]; then
                echo -e "${RED}✗ 可用内存不足 256MB，无法部署 ${project_type}${NC}"
                return 1
            fi
            ;;
        static)
            # 静态站内存要求很低
            ;;
    esac
    
    echo -e "${GREEN}✓ 资源足够部署 ${project_type}${NC}"
    return 0
}

# --- 主函数：显示完整画像 ---
profile_show() {
    local profile=$(classify_server)
    echo "$profile" > "$PROFILE_FILE"
    
    print_header "服务器画像"
    
    # 基本检测
    local cpu=$(detect_cpu)
    local mem=$(detect_mem_mb)
    local mem_avail=$(detect_mem_avail_mb)
    
    echo ""
    print_title "🏷️  服务器等级：${GREEN}${profile}${NC}"
    echo ""
    printf "  CPU: %s 核  |  内存: %s MB (可用 %s MB)  |  磁盘: %s / %s\n" \
        "$cpu" "$mem" "$mem_avail" "$(detect_disk_free)" "$(detect_disk_total)"
    echo ""
    
    # 推荐部署
    print_title "✅ 推荐部署："
    echo ""
    get_recommended "$profile" | while read -r item; do
        echo "  • $item"
    done
    echo ""
    
    # 禁止部署
    print_title "🚫 禁止部署："
    echo ""
    get_forbidden "$profile" | while read -r item; do
        echo "  • $item"
    done
    echo ""
    
    # 资源预估
    estimate_resources "$profile"
    
    log_info "profile_show: $profile"
}

# 简洁版本
profile_short() {
    local profile=$(classify_server)
    echo "$profile"
}
