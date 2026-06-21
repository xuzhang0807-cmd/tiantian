#!/bin/bash
# =============================================================================
# TianTian Ops - apps.sh
# Personal app catalog backed by TT blueprints.
# =============================================================================

_apps_manifest_value() {
    local manifest="$1" key="$2"
    python3 - "$manifest" "$key" <<'PY'
import sys
path, key = sys.argv[1:3]
parts = key.split('.')

def scalar(v):
    v = v.strip().strip('"').strip("'")
    if v.lower() == 'true': return True
    if v.lower() == 'false': return False
    if v.isdigit(): return int(v)
    return v

def parse(path):
    root = {}
    stack = [(-1, root)]
    for raw in open(path, encoding='utf-8'):
        if not raw.strip() or raw.lstrip().startswith('#'):
            continue
        indent = len(raw) - len(raw.lstrip(' '))
        line = raw.strip()
        if ':' not in line or line.startswith('- '):
            continue
        k, v = line.split(':', 1)
        k, v = k.strip(), v.strip()
        while stack and indent <= stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]
        if v == '':
            node = {}
            parent[k] = node
            stack.append((indent, node))
        else:
            parent[k] = scalar(v)
    return root

try:
    node = parse(path)
    for part in parts:
        node = node.get(part, '') if isinstance(node, dict) else ''
    print('' if node is None else node)
except Exception:
    print('')
PY
}

apps_list() {
    print_header "TT 应用目录 / Blueprint 市场"
    echo "来源: ${TT_HOME}/blueprints"
    echo ""
    printf '%-14s %-12s %-8s %-28s %s\n' "应用" "类型" "端口" "默认域名" "说明"
    local dir manifest name type port domain summary
    for dir in "${TT_HOME}"/blueprints/*; do
        [ -d "$dir" ] || continue
        manifest="${dir}/manifest.yaml"
        [ -f "$manifest" ] || continue
        name="$(_apps_manifest_value "$manifest" name)"
        type="$(_apps_manifest_value "$manifest" type)"
        port="$(_apps_manifest_value "$manifest" defaults.ports.web)"
        [ -n "$port" ] || port="$(_apps_manifest_value "$manifest" defaults.ports.api)"
        [ -n "$port" ] || port="$(_apps_manifest_value "$manifest" defaults.ports.storefront)"
        [ -n "$port" ] || port="-"
        domain="$(_apps_manifest_value "$manifest" defaults.domain)"
        [ -n "$domain" ] || domain="none"
        summary="$(_apps_manifest_value "$manifest" summary)"
        printf '%-14s %-12s %-8s %-28s %s\n' "${name:-$(basename "$dir")}" "${type:-unknown}" "$port" "$domain" "$summary"
    done
    echo ""
    echo "用法: tt apps show <name> | tt apps plan <name> [domain|none] [port]"
}

apps_show() {
    local app="${1:-}"
    if [ -z "$app" ]; then
        print_fail "请指定应用名称"
        echo "用法: tt apps show <name>"
        return 1
    fi
    app="$(preset_normalize_name "$app")"
    local type dir manifest
    type="$(preset_default_type "$app")"
    dir="$(preset_blueprint_dir "$type")"
    manifest="${dir}/manifest.yaml"
    if [ -z "$dir" ] || [ ! -f "$manifest" ]; then
        print_fail "未找到应用 blueprint: $app"
        return 1
    fi

    print_header "应用详情: $app"
    echo "类型: $(_apps_manifest_value "$manifest" type)"
    echo "说明: $(_apps_manifest_value "$manifest" summary)"
    echo "默认路径: $(_apps_manifest_value "$manifest" defaults.project_dir)"
    echo "默认域名: $(_apps_manifest_value "$manifest" defaults.domain)"
    echo "默认端口: $(preset_default_port "$app" "$type" 2>/dev/null || echo unknown)"
    echo "Blueprint: $dir"
    echo ""
    if [ -f "${dir}/README.md" ]; then
        print_title "README 摘要"
        sed -n '1,60p' "${dir}/README.md"
    fi
}

apps_plan() {
    local app="${1:-}" domain="${2:-}" port="${3:-}"
    if [ -z "$app" ]; then
        print_fail "请指定应用名称"
        echo "用法: tt apps plan <name> [domain|none] [port]"
        return 1
    fi
    app="$(preset_normalize_name "$app")"
    local type
    type="$(preset_default_type "$app")"
    if [ -z "$(preset_blueprint_dir "$type")" ]; then
        print_fail "未找到应用 blueprint: $app"
        return 1
    fi
    domain="${domain:-$(preset_default_domain "$app")}" 
    [ "$domain" = "none" ] && domain=""
    port="${port:-$(preset_default_port "$app" "$type")}" 
    print_header "应用部署计划: $app"
    preset_show_plan "$(preset_build_plan_json "$app" "$type" "$domain" "$port")"
    echo ""
    print_warn "这是计划预览，不会创建目录、写配置或启动容器。执行部署前请先运行 tt configure $app。"
}

apps_menu() {
    while true; do
        echo ""
        print_title "应用目录"
        echo ""
        echo "  1) 列出应用 ✅"
        echo "  2) 查看应用详情 ✅"
        echo "  3) 生成部署计划 ✅"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/apps> " choice
        case "$choice" in
            1) apps_list ;;
            2) read -r -p "  应用名称: " app; [ -n "$app" ] && apps_show "$app" ;;
            3) read -r -p "  应用名称: " app; [ -n "$app" ] && apps_plan "$app" ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
