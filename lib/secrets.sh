#!/bin/bash
# =============================================================================
# TianTian Ops - secrets.sh
# Generate local-only env files from blueprint examples.
# =============================================================================

BLUEPRINTS_DIR="${TT_HOME}/blueprints"

secret_random() {
    local length="${1:-32}"
    if has_cmd openssl; then
        openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$length"
    else
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
    fi
}

secret_is_placeholder() {
    local value="$1"
    case "$value" in
        CHANGE_ME*|GENERATE*|REQUIRED*|TODO*|YOUR_*|"" ) return 0 ;;
        *) return 1 ;;
    esac
}

secret_target_path() {
    local example_name="$1"
    case "$example_name" in
        env.example) echo ".env" ;;
        *.env.example) echo "${example_name%.env.example}/.env" ;;
        *) echo "${example_name%.example}" ;;
    esac
}

secret_read_value() {
    local prompt="$1" silent="${2:-false}" value=""
    if [ "$silent" = "true" ] && [ -t 0 ]; then
        read -r -s -p "$prompt" value
        echo "" >&2
    else
        read -r -p "$prompt" value
    fi
    echo "$value"
}

secret_prompt_value() {
    local key="$1" default="$2" generated="" value="" silent="false"
    if secret_is_placeholder "$default"; then
        generated="$(secret_random 32)"
        [[ "$key" =~ (PASSWORD|SECRET|TOKEN|KEY|PRIVATE|UUID) ]] && silent="true"
        value="$(secret_read_value "  ${key} [回车自动生成]: " "$silent")"
        echo "${value:-$generated}"
        return 0
    fi
    value="$(secret_read_value "  ${key} [${default}]: " false)"
    echo "${value:-$default}"
}

secret_render_example() {
    local example_file="$1" output_file="$2"
    local key value rendered line tmp
    tmp="${output_file}.tmp"
    mkdir -p "$(dirname "$output_file")"
    : > "$tmp"
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            key="${line%%=*}"
            value="${line#*=}"
            rendered="$(secret_prompt_value "$key" "$value")"
            printf '%s=%s\n' "$key" "$rendered" >> "$tmp"
        else
            printf '%s\n' "$line" >> "$tmp"
        fi
    done < "$example_file"
    chmod 600 "$tmp"
    mv "$tmp" "$output_file"
}

secret_configure_blueprint() {
    local blueprint="$1" target_dir="${2:-}"
    local blueprint_dir="${BLUEPRINTS_DIR}/${blueprint}"
    local default_dir example output rel

    [ -d "$blueprint_dir" ] || die "blueprint 不存在: ${blueprint}"
    default_dir="$(python3 - "$blueprint_dir/manifest.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
print((data.get('defaults') or {}).get('project_dir') or '')
PY
)"
    target_dir="${target_dir:-$default_dir}"
    [ -n "$target_dir" ] || die "无法确定目标目录，请传入 target_dir"

    print_header "生成本地配置: ${blueprint}"
    print_warn "只会写入目标目录本地 .env；不会把真实敏感值写回 Git blueprint"
    echo "  目标目录: ${target_dir}"
    echo ""

    shopt -s nullglob
    local examples=("$blueprint_dir"/*.example)
    shopt -u nullglob
    [ "${#examples[@]}" -gt 0 ] || die "未找到 .example 文件: ${blueprint_dir}"

    for example in "${examples[@]}"; do
        rel="$(secret_target_path "$(basename "$example")")"
        output="${target_dir}/${rel}"
        if [ -f "$output" ]; then
            print_warn "已存在: ${output}"
            if ! confirm "覆盖这个配置文件？"; then
                print_info "跳过 ${output}"
                continue
            fi
            cp -a "$output" "${output}.bak.$(date +%Y%m%d_%H%M%S)"
        fi
        print_info "生成 ${output}"
        secret_render_example "$example" "$output"
        print_success "已写入 ${output} (0600)"
    done
}

secret_missing_local_config() {
    local blueprint="$1" target_dir="$2"
    local blueprint_dir="${BLUEPRINTS_DIR}/${blueprint}"
    local example rel
    [ -d "$blueprint_dir" ] || return 1
    shopt -s nullglob
    local examples=("$blueprint_dir"/*.example)
    shopt -u nullglob
    [ "${#examples[@]}" -gt 0 ] || return 1
    for example in "${examples[@]}"; do
        rel="$(secret_target_path "$(basename "$example")")"
        [ -f "${target_dir}/${rel}" ] || return 0
    done
    return 1
}

secret_warn_missing_local_config() {
    local blueprint="$1" target_dir="$2"
    if secret_missing_local_config "$blueprint" "$target_dir"; then
        print_warn "检测到 ${blueprint} 需要本地敏感配置，但目标目录缺少 .env"
        echo "  请先运行: tt configure ${blueprint} ${target_dir}"
        return 1
    fi
    return 0
}
