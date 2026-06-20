#!/bin/bash
# =============================================================================
# TianTian Ops - preset.sh
# Deployment defaults and plan rendering
# =============================================================================

TT_DEFAULT_BASE_DOMAIN="${TT_DEFAULT_BASE_DOMAIN:-kazerush.xyz}"
TT_DEFAULT_HTTPS="${TT_DEFAULT_HTTPS:-true}"
TT_DEFAULT_BACKUP_BEFORE_DEPLOY="${TT_DEFAULT_BACKUP_BEFORE_DEPLOY:-true}"

preset_validate_project_name() {
    local name="$1"
    [[ "$name" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}

preset_normalize_name() {
    local name="$1"
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/^-*//; s/-*$//; s/--*/-/g'
}

preset_default_type() {
    local project="$1"
    case "$project" in
        wordpress|wp) echo "wordpress" ;;
        toko) echo "toko" ;;
        sub2|sub2api) echo "sub2api" ;;
        komari) echo "komari" ;;
        xray|singbox|network) echo "network" ;;
        *) echo "$project" ;;
    esac
}

preset_port_group() {
    local project="$1" type="$2"
    case "$project" in
        wordpress|wp) echo "wordpress"; return 0 ;;
        toko) echo "toko"; return 0 ;;
        sub2|sub2api) echo "sub2api"; return 0 ;;
        komari) echo "komari"; return 0 ;;
        xray|singbox|network) echo "network"; return 0 ;;
    esac
    case "$type" in
        wordpress|wp) echo "wordpress" ;;
        toko) echo "toko" ;;
        sub2|sub2api) echo "sub2api" ;;
        komari) echo "komari" ;;
        xray|singbox|network) echo "network" ;;
        *) echo "future" ;;
    esac
}

preset_default_domain() {
    local project="$1"
    local base_domain="${2:-$TT_DEFAULT_BASE_DOMAIN}"
    local type blueprint_domain
    project="$(preset_normalize_name "$project")"
    type="$(preset_default_type "$project")"
    blueprint_domain="$(preset_blueprint_default "$type" "domain")"
    if [ -n "$blueprint_domain" ] && [ "$blueprint_domain" != "none" ]; then
        normalize_domain "$blueprint_domain"
        return 0
    fi
    [ "$blueprint_domain" = "none" ] && return 0
    base_domain="$(normalize_domain "$base_domain")"
    [ -n "$project" ] && [ -n "$base_domain" ] || return 0
    echo "${project}.${base_domain}"
}

preset_blueprint_dir() {
    local type="$1"
    [ -d "${TT_HOME}/blueprints/${type}" ] && echo "${TT_HOME}/blueprints/${type}"
}

preset_blueprint_default() {
    local type="$1" key="$2" blueprint_dir
    blueprint_dir="$(preset_blueprint_dir "$type")"
    [ -n "$blueprint_dir" ] || return 0
    python3 - "$blueprint_dir/manifest.yaml" "$key" <<'PY'
import sys

def scalar(value):
    value = value.strip().strip('"').strip("'")
    if value.lower() == 'true':
        return True
    if value.lower() == 'false':
        return False
    if value.isdigit():
        return int(value)
    return value

def parse_simple_yaml(path):
    root = {}
    stack = [(-1, root)]
    for raw in open(path, encoding='utf-8'):
        if not raw.strip() or raw.lstrip().startswith('#'):
            continue
        indent = len(raw) - len(raw.lstrip(' '))
        line = raw.strip()
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        key = key.strip()
        value = value.strip()
        while stack and indent <= stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]
        if value == '':
            node = {}
            parent[key] = node
            stack.append((indent, node))
        else:
            parent[key] = scalar(value)
    return root

try:
    data = parse_simple_yaml(sys.argv[1])
    node = data.get('defaults') or {}
    for part in sys.argv[2].split('.'):
        node = node.get(part, '') if isinstance(node, dict) else ''
    print(node if node is not None else '')
except Exception:
    print('')
PY
}

preset_default_port() {
    local project="$1" type="$2" group key value
    type="${type:-$(preset_default_type "$project")}"
    group="$(preset_port_group "$project" "$type")"
    case "$group" in
        toko) key="ports.storefront" ;;
        sub2api) key="ports.api" ;;
        komari|wordpress) key="ports.web" ;;
        *) key="" ;;
    esac
    if [ -n "$key" ]; then
        value="$(preset_blueprint_default "$type" "$key")"
        [ -n "$value" ] && echo "$value" && return 0
    fi
    ports_suggest "$project" "$group" "main"
}

preset_build_plan_json() {
    local project="$1" type="$2" domain="$3" port="$4"
    local group project_dir https backup blueprint_dir
    group="$(preset_port_group "$project" "$type")"
    project_dir="$(preset_blueprint_default "$type" "project_dir")"
    project_dir="${project_dir:-${PROJECTS_BASE}/${project}}"
    https="false"
    [ -n "$domain" ] && https="$TT_DEFAULT_HTTPS"
    backup="$TT_DEFAULT_BACKUP_BEFORE_DEPLOY"
    python3 - "$project" "$type" "$domain" "$port" "$group" "$project_dir" "$https" "$backup" <<'PY'
import json, sys
project, project_type, domain, port, group, project_dir, https, backup = sys.argv[1:9]
plan = {
    "project": project,
    "type": project_type,
    "domain": domain,
    "port": int(port) if str(port).isdigit() else port,
    "port_group": group,
    "project_dir": project_dir,
    "https": https == "true",
    "backup_before_deploy": backup == "true",
    "nginx": bool(domain),
}
print(json.dumps(plan, ensure_ascii=False))
PY
}

preset_show_plan() {
    local plan_json="$1"
    python3 - "$plan_json" <<'PY'
import json, sys
p = json.loads(sys.argv[1])
print("  名称: " + str(p.get("project", "")))
print("  类型: " + str(p.get("type", "")))
print("  路径: " + str(p.get("project_dir", "")))
print("  端口: {}（{} 预设段）".format(p.get("port", ""), p.get("port_group", "future")))
print("  域名: " + (p.get("domain") or "无，跳过 HTTPS/nginx 域名配置"))
print("  HTTPS: " + ("启用" if p.get("https") else "跳过"))
print("  nginx: " + ("生成站点配置" if p.get("nginx") else "跳过站点配置"))
print("  备份策略: " + ("部署前如发现同名目录会先提示备份" if p.get("backup_before_deploy") else "不自动备份"))
PY
}

preset_plan_get() {
    local plan_json="$1" key="$2"
    python3 - "$plan_json" "$key" <<'PY'
import json, sys
p = json.loads(sys.argv[1])
node = p
for part in sys.argv[2].split('.'):
    node = node.get(part, "") if isinstance(node, dict) else ""
print(node)
PY
}
