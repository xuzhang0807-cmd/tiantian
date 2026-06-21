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

backup_restore_plan() {
    local archive="${1:-}"
    if [ -z "$archive" ]; then
        print_fail "请指定备份包路径"
        echo "用法: tt restore plan /home/tt-backups/<project>/<file>.tar.gz"
        return 1
    fi
    if [ ! -f "$archive" ]; then
        print_fail "备份包不存在: $archive"
        return 1
    fi

    print_header "恢复预案（只读）"
    echo "备份包: $archive"
    echo "大小: $(du -h "$archive" 2>/dev/null | awk '{print $1}')"
    echo "SHA256: $(sha256sum "$archive" 2>/dev/null | awk '{print $1}')"
    echo ""
    print_title "包内关键文件"
    tar -tzf "$archive" 2>/dev/null | grep -E '(^|/)(manifest.yaml|docker-compose.yml|compose.yml|\.env|BACKUP_INFO.txt)$' | sed 's/^/  /' || true
    echo ""
    print_warn "安全规则：恢复不会直接覆盖生产目录。先用 tt restore stage 解包到 staging，人工检查后再迁移。"
}

backup_restore_stage() {
    local archive="${1:-}" target="${2:-}"
    if [ -z "$archive" ]; then
        print_fail "请指定备份包路径"
        echo "用法: tt restore stage <backup.tar.gz> [target-dir]"
        return 1
    fi
    if [ ! -f "$archive" ]; then
        print_fail "备份包不存在: $archive"
        return 1
    fi
    target="${target:-${TT_BACKUP_ROOT}/restore-stage/$(date +%Y%m%d_%H%M%S)}"
    if [ -e "$target" ]; then
        print_fail "目标目录已存在: $target"
        return 1
    fi

    print_info "解包到 staging: $target"
    mkdir -p "$target"
    tar -xzf "$archive" -C "$target"
    chmod -R go-rwx "$target" 2>/dev/null || true
    print_success "已解包到: $target"
    print_warn "请检查 compose/.env/数据目录后，再按项目恢复流程迁移；TT 不会自动覆盖生产数据。"
    echo "$target"
}

backup_restore_verify() {
    local archive="${1:-}" target="${2:-}"
    local list_file err_file
    list_file="/tmp/tt-restore-verify-list.$$"
    err_file="/tmp/tt-restore-verify-err.$$"

    if [ -z "$archive" ]; then
        print_fail "请指定备份包路径"
        echo "用法: tt restore verify <backup.tar.gz> [stage-dir]"
        return 1
    fi
    if [ ! -f "$archive" ]; then
        print_fail "备份包不存在: $archive"
        return 1
    fi

    print_header "恢复演练（不覆盖生产）"
    echo "备份包: $archive"
    echo "大小: $(du -h "$archive" 2>/dev/null | awk '{print $1}')"
    echo "SHA256: $(sha256sum "$archive" 2>/dev/null | awk '{print $1}')"
    echo ""

    print_title "压缩包完整性"
    if tar -tzf "$archive" >"$list_file" 2>"$err_file"; then
        print_success "tar 可读取"
    else
        print_fail "tar 读取失败: $(cat "$err_file" 2>/dev/null)"
        rm -f "$list_file" "$err_file"
        return 1
    fi

    print_title "关键文件检查"
    local has_manifest has_compose has_env
    has_manifest="$(grep -E '(^|/)manifest.yaml$' "$list_file" | head -n1 || true)"
    has_compose="$(grep -E '(^|/)(docker-compose.yml|compose.yml)$' "$list_file" | head -n1 || true)"
    has_env="$(grep -E '(^|/)\.env$' "$list_file" | head -n1 || true)"
    [ -n "$has_manifest" ] && print_success "manifest: $has_manifest" || print_warn "未发现 manifest.yaml"
    [ -n "$has_compose" ] && print_success "compose: $has_compose" || print_warn "未发现 docker-compose.yml/compose.yml"
    [ -n "$has_env" ] && print_warn "包含 .env：解包目录将设置为仅当前用户可读" || print_info "未发现根级 .env"
    echo ""

    target="${target:-${TT_BACKUP_ROOT}/restore-verify/$(date +%Y%m%d_%H%M%S)}"
    if [ -e "$target" ]; then
        print_fail "目标目录已存在: $target"
        rm -f "$list_file" "$err_file"
        return 1
    fi

    print_title "演练解包"
    mkdir -p "$target"
    if tar -xzf "$archive" -C "$target"; then
        chmod -R go-rwx "$target" 2>/dev/null || true
        print_success "已解包到: $target"
    else
        print_fail "解包失败"
        rm -f "$list_file" "$err_file"
        return 1
    fi

    print_title "解包后检查"
    find "$target" -maxdepth 3 \( -name manifest.yaml -o -name docker-compose.yml -o -name compose.yml -o -name .env \) -printf '  %P\n' 2>/dev/null | sort || true
    echo ""
    print_warn "演练完成：TT 没有覆盖生产目录。人工确认后，按项目 README/blueprint 恢复数据和配置。"
    echo "$target"

    rm -f "$list_file" "$err_file"
}
