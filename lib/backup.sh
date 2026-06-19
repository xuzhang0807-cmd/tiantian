#!/bin/bash
# =============================================================================
# TianTian Ops - backup.sh
# Project backup, restore scaffolding, and backup listing
# =============================================================================

TT_BACKUP_ROOT="${TT_BACKUP_ROOT:-/home/tt-backups}"
TT_SECRETS_ROOT="${TT_SECRETS_ROOT:-/home/tt-secrets}"

backup_project() {
    local name="$1"
    local project_dir="${PROJECTS_BASE}/${name}"
    local ts backup_dir archive metadata

    if [ -z "$name" ]; then
        print_fail "请指定项目名称"
        return 1
    fi
    if [ ! -d "$project_dir" ]; then
        print_fail "项目目录不存在: ${project_dir}"
        return 1
    fi

    ts="$(date +%Y%m%d_%H%M%S)"
    backup_dir="${TT_BACKUP_ROOT}/${name}/${ts}"
    archive="${TT_BACKUP_ROOT}/${name}/${name}_${ts}.tar.gz"
    metadata="${backup_dir}/BACKUP_INFO.txt"

    print_info "创建项目备份: ${name}"
    mkdir -p "$backup_dir"

    {
        echo "project=${name}"
        echo "created=$(date -Iseconds)"
        echo "source=${project_dir}"
        echo "host=$(hostname 2>/dev/null || echo unknown)"
    } > "$metadata"

    if [ -f "${project_dir}/manifest.yaml" ]; then
        cp -a "${project_dir}/manifest.yaml" "$backup_dir/manifest.yaml"
    fi
    if [ -f "${project_dir}/docker-compose.yml" ]; then
        cp -a "${project_dir}/docker-compose.yml" "$backup_dir/docker-compose.yml"
    fi
    if [ -f "${project_dir}/.env" ]; then
        cp -a "${project_dir}/.env" "$backup_dir/.env"
        chmod 600 "$backup_dir/.env" 2>/dev/null || true
    fi

    local domain conf
    domain="$(project_get_domain "$project_dir" 2>/dev/null || true)"
    if [ -n "$domain" ]; then
        conf="/home/web/conf.d/${domain}.conf"
        [ -f "$conf" ] && cp -a "$conf" "$backup_dir/nginx-${domain}.conf"
    fi

    print_info "打包运行目录，可能需要一些时间 ..."
    mkdir -p "$(dirname "$archive")"
    if tar --exclude='./backups' -czf "$archive" -C "$(dirname "$project_dir")" "$(basename "$project_dir")" -C "$backup_dir" . 2>/tmp/tt-backup-${name}.err; then
        rm -rf "$backup_dir"
        print_success "备份完成: ${archive}"
        echo "$archive"
        return 0
    fi

    print_fail "备份失败: $(cat /tmp/tt-backup-${name}.err 2>/dev/null)"
    print_warn "已保留临时备份目录: ${backup_dir}"
    return 1
}

backup_list() {
    local name="${1:-}"
    print_header "备份列表"
    if [ -n "$name" ]; then
        find "${TT_BACKUP_ROOT}/${name}" -maxdepth 1 -type f -name '*.tar.gz' -printf '  %f\n' 2>/dev/null | sort || true
    else
        find "$TT_BACKUP_ROOT" -mindepth 2 -maxdepth 2 -type f -name '*.tar.gz' -printf '  %P\n' 2>/dev/null | sort || true
    fi
}

backup_root_info() {
    echo "$TT_BACKUP_ROOT"
}
