#!/bin/bash
# =============================================================================
# TianTian Ops - deps.sh
# Dependency discovery, installation, and update helpers
# =============================================================================

TT_DEPS_REQUIRED="${TT_DEPS_REQUIRED:-git curl tar python3 ca-certificates openssl}"
TT_DEPS_RECOMMENDED="${TT_DEPS_RECOMMENDED:-docker docker-compose-plugin nginx certbot python3-yaml rsync unzip jq ss}"

_deps_os_id() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

_deps_pkg_manager() {
    if has_cmd apt-get; then echo apt; return 0; fi
    if has_cmd dnf; then echo dnf; return 0; fi
    if has_cmd yum; then echo yum; return 0; fi
    echo unknown
}

_deps_command_for() {
    case "$1" in
        docker|docker.io|docker-ce) echo docker ;;
        docker-compose-plugin|docker-compose) echo "docker compose" ;;
        python3-yaml|python3-pyyaml|PyYAML) echo python3-yaml ;;
        iproute2|ss) echo ss ;;
        ca-certificates) echo update-ca-certificates ;;
        *) echo "$1" ;;
    esac
}

_deps_apt_pkg_for() {
    case "$1" in
        docker) echo docker.io ;;
        ss) echo iproute2 ;;
        *) echo "$1" ;;
    esac
}

_deps_yum_pkg_for() {
    case "$1" in
        docker) echo docker ;;
        docker-compose-plugin) echo docker-compose-plugin ;;
        python3-yaml) echo python3-pyyaml ;;
        ss) echo iproute ;;
        *) echo "$1" ;;
    esac
}

_deps_has() {
    local dep="$1" cmd
    cmd="$(_deps_command_for "$dep")"
    case "$cmd" in
        "docker compose") docker compose version >/dev/null 2>&1 ;;
        python3-yaml) python3 - <<'PY' >/dev/null 2>&1
import yaml
PY
            ;;
        *) has_cmd "$cmd" ;;
    esac
}

deps_status_line() {
    local dep="$1" label="${2:-$1}"
    if _deps_has "$dep"; then
        printf "  ✓ %-24s %s\n" "$label" "已安装"
    else
        printf "  ✗ %-24s %s\n" "$label" "缺失"
        return 1
    fi
}

deps_doctor() {
    print_header "依赖检查"
    echo ""
    print_title "必需依赖"
    local missing=0 dep
    for dep in $TT_DEPS_REQUIRED; do
        deps_status_line "$dep" || missing=$((missing + 1))
    done
    echo ""
    print_title "推荐依赖"
    for dep in $TT_DEPS_RECOMMENDED; do
        deps_status_line "$dep" || true
    done
    echo ""
    print_title "安装器"
    printf "  系统: %s\n" "$(_deps_os_id)"
    printf "  包管理器: %s\n" "$(_deps_pkg_manager)"
    echo ""
    if [ "$missing" -gt 0 ]; then
        print_warn "存在 ${missing} 个必需依赖缺失，可运行: tt deps install"
        return 1
    fi
    print_success "必需依赖已满足"
}

deps_versions() {
    print_header "依赖版本"
    local item version
    for item in git curl python3 docker nginx certbot openssl; do
        if ! has_cmd "$item"; then
            printf "  %-10s %s\n" "$item" "未安装"
            continue
        fi
        case "$item" in
            docker) version="$(docker --version 2>/dev/null | sed 's/,//')" ;;
            nginx) version="$(nginx -v 2>&1 | sed 's/^nginx version: //')" ;;
            openssl) version="$(openssl version 2>/dev/null)" ;;
            *) version="$($item --version 2>/dev/null | head -n1)" ;;
        esac
        printf "  %-10s %s\n" "$item" "$version"
    done
    if docker compose version >/dev/null 2>&1; then
        printf "  %-10s %s\n" "compose" "$(docker compose version 2>/dev/null)"
    else
        printf "  %-10s %s\n" "compose" "未安装"
    fi
}

deps_install() {
    local scope="${1:-recommended}" pm dep pkg packages=()
    if [ "$(id -u)" -ne 0 ]; then
        die "安装依赖需要 root 权限"
    fi
    pm="$(_deps_pkg_manager)"
    [ "$pm" != "unknown" ] || die "未识别包管理器，请手动安装依赖"

    local list="$TT_DEPS_REQUIRED"
    case "$scope" in
        required|basic) ;;
        recommended|all) list="$TT_DEPS_REQUIRED $TT_DEPS_RECOMMENDED" ;;
        *) die "用法: tt deps install [required|recommended|all]" ;;
    esac

    for dep in $list; do
        _deps_has "$dep" && continue
        case "$pm" in
            apt) pkg="$(_deps_apt_pkg_for "$dep")" ;;
            dnf|yum) pkg="$(_deps_yum_pkg_for "$dep")" ;;
            *) pkg="$dep" ;;
        esac
        packages+=("$pkg")
    done

    if [ "${#packages[@]}" -eq 0 ]; then
        print_success "依赖已满足，无需安装"
        return 0
    fi

    print_warn "即将安装缺失依赖: ${packages[*]}"
    confirm "继续安装？" || return 0
    case "$pm" in
        apt)
            run_or_die "更新 apt 索引" apt-get update
            run_or_die "安装依赖" apt-get install -y "${packages[@]}"
            ;;
        dnf)
            run_or_die "安装依赖" dnf install -y "${packages[@]}"
            ;;
        yum)
            run_or_die "安装依赖" yum install -y "${packages[@]}"
            ;;
    esac

    if has_cmd systemctl && has_cmd docker; then
        systemctl enable --now docker >/dev/null 2>&1 || true
    fi
    deps_doctor || true
}

tt_update_system() {
    print_header "更新 TianTian Ops"
    if [ ! -d "${TT_HOME}/.git" ]; then
        print_warn "${TT_HOME} 不是 git 仓库，无法自动更新"
        return 1
    fi
    local old_rev new_rev
    old_rev="$(cd "$TT_HOME" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    print_info "当前版本: ${old_rev}"
    run_or_die "拉取最新代码" git -C "$TT_HOME" pull --ff-only
    new_rev="$(cd "$TT_HOME" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    print_success "TT 已更新: ${old_rev} -> ${new_rev}"
    chmod +x "${TT_HOME}/tiantian.sh" "${TT_HOME}/bootstrap.sh" "${TT_HOME}/lib/"*.sh 2>/dev/null || true
    deps_versions
}
