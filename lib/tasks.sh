#!/bin/bash
# =============================================================================
# TianTian Ops - tasks.sh
# Rsync task inventory and cron scheduling helpers.
# =============================================================================

TT_TASKS_FILE="${TT_TASKS_FILE:-${TT_HOME}/state/rsync-tasks.txt}"
TT_TASKS_CRON_MARK="TT_TASK"

_tasks_ensure_file() {
    mkdir -p "$(dirname "$TT_TASKS_FILE")"
    [ -f "$TT_TASKS_FILE" ] || touch "$TT_TASKS_FILE"
    chmod 600 "$TT_TASKS_FILE" 2>/dev/null || true
}

_tasks_valid_name() {
    [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]
}

_tasks_find() {
    local wanted="$1" task_name task_mode task_local task_remote task_port task_key task_opts task_rest
    [ -f "$TT_TASKS_FILE" ] || return 1
    while IFS='|' read -r task_name task_mode task_local task_remote task_port task_key task_opts task_rest || [ -n "$task_name" ]; do
        [ -n "$task_name" ] || continue
        case "$task_name" in \#*) continue ;; esac
        if [ "$task_name" = "$wanted" ]; then
            printf '%s|%s|%s|%s|%s|%s|%s\n' "$task_name" "$task_mode" "$task_local" "$task_remote" "${task_port:-22}" "$task_key" "${task_opts:--az}"
            return 0
        fi
    done < "$TT_TASKS_FILE"
    return 1
}

_tasks_ssh_args() {
    local port="$1" key="$2"
    local opts=(-p "$port" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
    [ -n "$key" ] && opts=(-i "$key" "${opts[@]}")
    printf '%q ' "${opts[@]}"
}

tasks_list() {
    print_header "Rsync 任务列表"
    _tasks_ensure_file
    echo "配置文件: ${TT_TASKS_FILE}"
    echo ""
    if [ ! -s "$TT_TASKS_FILE" ]; then
        print_warn "尚未配置任务。"
        echo "添加示例: tt tasks add backup_www push /home/web root@1.2.3.4:/backup/web 22 ~/.ssh/key"
        return 0
    fi
    printf '%-18s %-8s %-28s %-36s %-6s %s\n' "名称" "模式" "本地路径" "远端路径" "端口" "Key"
    while IFS='|' read -r name mode local_path remote_path port key opts rest; do
        [ -n "$name" ] || continue
        case "$name" in \#*) continue ;; esac
        printf '%-18s %-8s %-28s %-36s %-6s %s\n' "$name" "${mode:-push}" "$local_path" "$remote_path" "${port:-22}" "${key:-default}"
    done < "$TT_TASKS_FILE"
}

tasks_add() {
    local name="$1" mode="${2:-push}" local_path="$3" remote_path="$4" port="${5:-22}" key="${6:-}" opts="${7:--az}"
    print_header "添加 Rsync 任务"
    _tasks_ensure_file
    _tasks_valid_name "$name" || { print_fail "任务名称不合法，只能用字母数字 ._-"; return 1; }
    case "$mode" in push|pull) ;; *) print_fail "模式必须是 push 或 pull"; return 1 ;; esac
    [ -n "$local_path" ] || { print_fail "请指定本地路径"; return 1; }
    [ -n "$remote_path" ] || { print_fail "请指定远端路径，例如 root@1.2.3.4:/backup/web"; return 1; }
    validate_port "$port" || { print_fail "端口不合法: $port"; return 1; }
    if [ -n "$key" ] && [ ! -f "$key" ]; then
        print_fail "SSH key 不存在: $key"
        return 1
    fi
    if _tasks_find "$name" >/dev/null; then
        print_fail "任务已存在: $name"
        return 1
    fi
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$name" "$mode" "$local_path" "$remote_path" "$port" "$key" "$opts" >> "$TT_TASKS_FILE"
    chmod 600 "$TT_TASKS_FILE" 2>/dev/null || true
    print_success "已添加任务: $name"
    tasks_list
}

tasks_remove() {
    local name="$1" tmp
    print_header "删除 Rsync 任务"
    [ -n "$name" ] || { print_fail "请指定任务名称"; return 1; }
    _tasks_ensure_file
    tmp="${TT_TASKS_FILE}.tmp"
    awk -F'|' -v n="$name" '($1==n){next} {print}' "$TT_TASKS_FILE" > "$tmp"
    mv "$tmp" "$TT_TASKS_FILE"
    chmod 600 "$TT_TASKS_FILE" 2>/dev/null || true
    tasks_unschedule "$name" >/dev/null 2>&1 || true
    print_success "已删除任务: $name"
}

tasks_plan() {
    local name="$1" row mode local_path remote_path port key opts source dest ssh_args
    print_header "Rsync 执行预案"
    row="$(_tasks_find "$name")" || { print_fail "任务不存在: $name"; return 1; }
    IFS='|' read -r _ mode local_path remote_path port key opts <<< "$row"
    if [ "$mode" = "pull" ]; then
        source="$remote_path"
        dest="$local_path"
    else
        source="$local_path"
        dest="$remote_path"
    fi
    ssh_args="$(_tasks_ssh_args "$port" "$key")"
    echo "任务: $name"
    echo "模式: $mode"
    echo "源: $source"
    echo "目标: $dest"
    echo "命令: rsync ${opts:--az} -e \"ssh ${ssh_args}\" \"$source\" \"$dest\""
    echo ""
    print_warn "run/schedule 会真实同步文件；首次建议先用 plan 核对路径。"
}

tasks_run() {
    local name="$1" row mode local_path remote_path port key opts source dest ssh_args
    print_header "执行 Rsync 任务"
    has_cmd rsync || { print_fail "缺少 rsync，请先安装: tt tools install rsync"; return 1; }
    row="$(_tasks_find "$name")" || { print_fail "任务不存在: $name"; return 1; }
    IFS='|' read -r _ mode local_path remote_path port key opts <<< "$row"
    if [ -n "$key" ] && [ ! -f "$key" ]; then
        print_fail "SSH key 不存在: $key"
        return 1
    fi
    if [ "$mode" = "pull" ]; then
        source="$remote_path"
        dest="$local_path"
    else
        source="$local_path"
        dest="$remote_path"
    fi
    ssh_args="$(_tasks_ssh_args "$port" "$key")"
    print_info "$name: $source → $dest"
    rsync ${opts:--az} -e "ssh ${ssh_args}" "$source" "$dest"
    print_success "任务完成: $name"
}

tasks_schedule() {
    local name="$1" interval="${2:-daily}" cron_time current line
    print_header "添加任务计划"
    _tasks_find "$name" >/dev/null || { print_fail "任务不存在: $name"; return 1; }
    has_cmd crontab || { print_fail "缺少 crontab，请先安装 cron/cronie"; return 1; }
    case "$interval" in
        hourly) cron_time="17 * * * *" ;;
        daily) cron_time="23 3 * * *" ;;
        weekly) cron_time="31 4 * * 1" ;;
        *)
            if [[ "$interval" =~ ^[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+[0-9*,/-]+$ ]]; then
                cron_time="$interval"
            else
                print_fail "间隔必须是 hourly/daily/weekly 或 5 段 cron 表达式"
                return 1
            fi
            ;;
    esac
    current="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$current" | grep -q "# ${TT_TASKS_CRON_MARK}:${name}$"; then
        print_fail "该任务已存在计划: $name"
        return 1
    fi
    line="${cron_time} TT_HOME='${TT_HOME}' '${TT_HOME}/tiantian.sh' tasks run '${name}' # ${TT_TASKS_CRON_MARK}:${name}"
    { printf '%s\n' "$current" | sed '/^[[:space:]]*$/d'; printf '%s\n' "$line"; } | crontab -
    print_success "已添加计划: $line"
}

tasks_unschedule() {
    local name="$1" current
    print_header "删除任务计划"
    [ -n "$name" ] || { print_fail "请指定任务名称"; return 1; }
    has_cmd crontab || { print_warn "缺少 crontab"; return 0; }
    current="$(crontab -l 2>/dev/null || true)"
    printf '%s\n' "$current" | grep -v "# ${TT_TASKS_CRON_MARK}:${name}$" | crontab -
    print_success "已删除计划: $name"
}

tasks_cron() {
    print_header "TT 任务计划"
    if ! has_cmd crontab; then
        print_warn "缺少 crontab"
        return 0
    fi
    crontab -l 2>/dev/null | grep "# ${TT_TASKS_CRON_MARK}:" || print_info "没有 TT rsync 任务计划"
}

tasks_menu() {
    while true; do
        echo ""
        print_title "任务 / Rsync 管理"
        echo ""
        echo "  1) 任务列表 ✅"
        echo "  2) 添加任务 🔧"
        echo "  3) 执行预案 ✅"
        echo "  4) 立即执行 ⚠️"
        echo "  5) 添加计划 ⚠️"
        echo "  6) 删除计划 ⚠️"
        echo "  7) 删除任务 ⚠️"
        echo "  8) 查看计划 ✅"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/tasks> " choice
        case "$choice" in
            1) tasks_list ;;
            2)
                read -r -p "  名称: " name
                read -r -p "  模式 push/pull [push]: " mode
                read -r -p "  本地路径: " local_path
                read -r -p "  远端路径(user@host:/path): " remote_path
                read -r -p "  端口 [22]: " port
                read -r -p "  SSH key路径（可空）: " key
                tasks_add "$name" "${mode:-push}" "$local_path" "$remote_path" "${port:-22}" "$key"
                ;;
            3) read -r -p "  名称: " name; tasks_plan "$name" ;;
            4) read -r -p "  名称: " name; tasks_plan "$name" && confirm "确认立即同步？" && tasks_run "$name" ;;
            5) read -r -p "  名称: " name; read -r -p "  间隔 hourly/daily/weekly 或 cron [daily]: " interval; tasks_schedule "$name" "${interval:-daily}" ;;
            6) read -r -p "  名称: " name; tasks_unschedule "$name" ;;
            7) read -r -p "  名称: " name; confirm "确认删除任务 ${name}？" && tasks_remove "$name" ;;
            8) tasks_cron ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
