#!/bin/bash
# =============================================================================
# TianTian Ops - 主入口
# tt 命令：一键运维管理
# 用法: tt [command] [args...]
# =============================================================================

set -e

TT_HOME="${TT_HOME:-/opt/tiantian}"
export TT_HOME

# 加载核心库
source "${TT_HOME}/lib/core.sh"
source "${TT_HOME}/lib/detect.sh"
source "${TT_HOME}/lib/profile.sh"
source "${TT_HOME}/lib/input.sh"
source "${TT_HOME}/lib/ports.sh"
source "${TT_HOME}/lib/preset.sh"
source "${TT_HOME}/lib/secrets.sh"
source "${TT_HOME}/lib/backup.sh"
source "${TT_HOME}/lib/deps.sh"
source "${TT_HOME}/lib/tools.sh"
source "${TT_HOME}/lib/ops.sh"
source "${TT_HOME}/lib/firewall.sh"
source "${TT_HOME}/lib/bench.sh"
source "${TT_HOME}/lib/cluster.sh"
source "${TT_HOME}/lib/coverage.sh"
source "${TT_HOME}/lib/selftest.sh"
source "${TT_HOME}/lib/upstream.sh"
source "${TT_HOME}/lib/doctor.sh"
source "${TT_HOME}/lib/health.sh"
source "${TT_HOME}/lib/nginx.sh"
source "${TT_HOME}/lib/cert.sh"
source "${TT_HOME}/lib/docker.sh"
source "${TT_HOME}/lib/project.sh"

# --- 安装 tt 命令 ---
install_tt() {
    local tt_path="/usr/local/bin/tt"
    if [ "$(readlink -f "$tt_path" 2>/dev/null)" != "${TT_HOME}/tiantian.sh" ]; then
        ln -sf "${TT_HOME}/tiantian.sh" "$tt_path"
        print_success "tt 命令已安装: /usr/local/bin/tt"
    fi
}

# --- 显示 Banner ---
show_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║        TianTian 运维系统             ║"
    echo "  ║        v${TT_VERSION}  · 工程化运维             ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

# --- 显示主菜单 ---
show_menu() {
    echo ""
    echo -e "  ${BOLD}请选择操作：${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC}) 系统检测"
    echo -e "  ${GREEN}2${NC}) 服务器画像"
    echo -e "  ${GREEN}3${NC}) 项目管理"
    echo -e "  ${GREEN}4${NC}) nginx 管理"
    echo -e "  ${GREEN}5${NC}) 证书管理"
    echo -e "  ${GREEN}6${NC}) 容器管理"
    echo -e "  ${GREEN}7${NC}) 监控巡检"
    echo -e "  ${GREEN}8${NC}) 备份恢复"
    echo -e "  ${GREEN}9${NC}) 系统工具"
    echo -e "  ${GREEN}10${NC}) 防火墙状态"
    echo -e "  ${GREEN}11${NC}) 测试脚本合集"
    echo -e "  ${GREEN}12${NC}) 常用运维"
    echo -e "  ${GREEN}13${NC}) 集群控制"
    echo -e "  ${GREEN}14${NC}) 高级操作"
    echo ""
    echo -e "  ${GREEN}0${NC}) 退出"
    echo ""
}

# --- 项目管理子菜单 ---
show_project_menu() {
    echo ""
    echo -e "  ${BOLD}项目管理${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC}) 列出项目"
    echo -e "  ${GREEN}2${NC}) 部署项目"
    echo -e "  ${GREEN}3${NC}) 删除项目"
    echo -e "  ${GREEN}4${NC}) 项目状态"
    echo -e "  ${GREEN}5${NC}) 查看日志"
    echo -e "  ${GREEN}0${NC}) 返回"
    echo ""
}

# --- nginx 管理子菜单 ---
show_nginx_menu() {
    echo ""
    echo -e "  ${BOLD}nginx 管理${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC}) 列出站点"
    echo -e "  ${GREEN}2${NC}) 测试配置"
    echo -e "  ${GREEN}3${NC}) 重载 nginx"
    echo -e "  ${GREEN}4${NC}) 添加站点配置"
    echo -e "  ${GREEN}5${NC}) 移除站点配置"
    echo -e "  ${GREEN}0${NC}) 返回"
    echo ""
}

# --- 容器管理子菜单 ---
show_docker_menu() {
    echo ""
    echo -e "  ${BOLD}容器管理${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC}) 列出项目"
    echo -e "  ${GREEN}2${NC}) 启动项目"
    echo -e "  ${GREEN}3${NC}) 停止项目"
    echo -e "  ${GREEN}4${NC}) 重启项目"
    echo -e "  ${GREEN}5${NC}) 查看日志"
    echo -e "  ${GREEN}6${NC}) Docker 资源概览 ✅"
    echo -e "  ${GREEN}7${NC}) 全部容器列表 ✅"
    echo -e "  ${GREEN}8${NC}) 镜像列表 ✅"
    echo -e "  ${GREEN}9${NC}) 卷/网络列表 ✅"
    echo -e "  ${GREEN}10${NC}) Compose 配置校验 ✅"
    echo -e "  ${GREEN}11${NC}) Docker 安全巡检 ✅"
    echo -e "  ${GREEN}12${NC}) Docker 配置/镜像源/IPv6 ✅"
    echo -e "  ${GREEN}0${NC}) 返回"
    echo ""
}

docker_menu() {
    while true; do
        show_docker_menu
        read -r -p "  tt/docker> " dchoice
        case "$dchoice" in
            1) docker_list_projects ;;
            2)
                read -r -p "  项目名称: " dname
                [ -n "$dname" ] && docker_up "${PROJECTS_BASE}/${dname}"
                ;;
            3)
                read -r -p "  项目名称: " dname
                [ -n "$dname" ] && docker_down "${PROJECTS_BASE}/${dname}"
                ;;
            4)
                read -r -p "  项目名称: " dname
                [ -n "$dname" ] && docker_restart "${PROJECTS_BASE}/${dname}"
                ;;
            5)
                read -r -p "  项目名称: " dname
                [ -n "$dname" ] && docker_logs "${PROJECTS_BASE}/${dname}" 50
                ;;
            6) docker_overview ;;
            7) docker_list_containers ;;
            8) docker_list_images ;;
            9) docker_list_storage ;;
            10)
                read -r -p "  项目名称（留空校验全部）: " dname
                docker_compose_check "$dname"
                ;;
            11) docker_safety_audit ;;
            12) docker_daemon_config ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}

# --- 高级操作子菜单 ---
show_advanced_menu() {
    echo ""
    echo -e "  ${BOLD}高级操作${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC}) 安装 certbot"
    echo -e "  ${GREEN}2${NC}) 部署证书自动同步 hook"
    echo -e "  ${GREEN}3${NC}) 更新 tt 系统"
    echo -e "  ${GREEN}4${NC}) 清理日志"
    echo -e "  ${GREEN}5${NC}) 检查/安装依赖"
    echo -e "  ${GREEN}0${NC}) 返回"
    echo ""
}

# --- 部署交互流程 ---
deploy_interactive() {
    echo ""
    print_title "部署新项目"
    echo ""
    
    read -r -p "  项目名称 (如 wordpress/toko): " project_name
    project_name="$(preset_normalize_name "$project_name")"
    if [ -z "$project_name" ]; then
        print_fail "项目名称不能为空"
        return 1
    fi
    
    # 检查是否已存在
    if [ -f "${PROJECTS_BASE}/${project_name}/manifest.yaml" ]; then
        print_warn "项目 ${project_name} 已存在，继续部署前会先创建备份"
    fi
    
    local default_type default_domain port_group suggested_port plan_json
    default_type="$(preset_default_type "$project_name")"
    project_type="$(prompt_optional "项目类型" "$default_type")"
    project_type="${project_type:-$default_type}"
    port_group="$(preset_port_group "$project_name" "$project_type")"
    default_domain="$(preset_default_domain "$project_name")"
    domain="$(prompt_domain "域名（回车采用默认；输入 none 跳过 HTTPS）" true "$default_domain")"
    [ "$domain" = "none" ] && domain=""
    if [ -n "$domain" ]; then
        check_domain_dns "$domain" || print_warn "DNS 未完全通过，证书申请可能失败；可先继续本地部署"
    fi
    
    suggested_port="$(preset_default_port "$project_name" "$project_type" 2>/dev/null || echo 8085)"
    port="$(prompt_port "容器入口端口" "$suggested_port")"
    plan_json="$(preset_build_plan_json "$project_name" "$project_type" "$domain" "$port")"
    
    echo ""
    print_info "部署计划（可回车采用默认，也可手动覆盖后再确认）："
    preset_show_plan "$plan_json"
    echo ""
    
    if ! confirm "确认按以上计划部署？"; then
        print_info "取消部署"
        return 0
    fi
    
    local plan_project_dir
    plan_project_dir="$(preset_plan_get "$plan_json" "project_dir")"
    secret_warn_missing_local_config "$project_type" "$plan_project_dir" || return 1
    
    # 部署
    project_deploy "$project_name" "$project_type" "$domain" "$port" "$plan_project_dir"
}

# --- 主循环（交互模式）---
main_loop() {
    show_banner
    install_tt
    
    while true; do
        show_menu
        read -p "  tt> " choice
        
        case "$choice" in
            1)
                detect_all
                ;;
            2)
                profile_show
                ;;
            3)
                # 项目管理子菜单
                while true; do
                    show_project_menu
                    read -p "  tt/project> " pchoice
                    case "$pchoice" in
                        1) project_list ;;
                        2) deploy_interactive ;;
                        3)
                            read -p "  项目名称: " pname
                            [ -n "$pname" ] && project_remove "$pname"
                            ;;
                        4)
                            read -p "  项目名称: " pname
                            [ -n "$pname" ] && docker_status "${PROJECTS_BASE}/${pname}"
                            ;;
                        5)
                            read -p "  项目名称: " pname
                            [ -n "$pname" ] && docker_logs "${PROJECTS_BASE}/${pname}" 50
                            ;;
                        0) break ;;
                        *) echo -e "  ${RED}无效选项${NC}" ;;
                    esac
                done
                ;;
            4)
                # nginx 管理子菜单
                while true; do
                    show_nginx_menu
                    read -p "  tt/nginx> " nchoice
                    case "$nchoice" in
                        1) nginx_list_sites ;;
                        2) nginx_test ;;
                        3) nginx_reload ;;
                        4)
                            read -p "  域名: " ndomain
                            read -p "  端口: " nport
                            [ -n "$ndomain" ] && [ -n "$nport" ] && nginx_render_site "$ndomain" "$nport"
                            ;;
                        5)
                            read -p "  域名: " ndomain
                            [ -n "$ndomain" ] && nginx_remove_site "$ndomain" && nginx_reload
                            ;;
                        0) break ;;
                        *) echo -e "  ${RED}无效选项${NC}" ;;
                    esac
                done
                ;;
            5)
                cert_status
                ;;
            6)
                docker_menu
                ;;
            7)
                health_check
                ;;
            8)
                print_info "备份功能开发中..."
                echo "  暂未实现自动备份。"
                echo "  项目数据位于 /home/docker/<project>/backups/"
                echo "  可手动执行: docker exec <container> ... "
                ;;
            9)
                tools_menu
                ;;
            10)
                firewall_menu
                ;;
            11)
                bench_menu
                ;;
            12)
                ops_menu
                ;;
            13)
                cluster_menu
                ;;
            14)
                while true; do
                    show_advanced_menu
                    read -p "  tt/advanced> " achoice
                    case "$achoice" in
                        1) cert_install ;;
                        2) cert_deploy_hook ;;
                        3) print_info "更新 tt 系统..."
                           tt_update_system
                           ;;
                        4) 
                           print_info "清理日志 ..."
                           find "${TT_HOME}/logs/" -name "*.log" -mtime +30 -delete 2>/dev/null
                           print_success "日志已清理"
                           ;;
                        5)
                           deps_doctor || true
                           confirm "是否安装缺失推荐依赖？" && deps_install recommended
                           ;;
                        0) break ;;
                        *) echo -e "  ${RED}无效选项${NC}" ;;
                    esac
                done
                ;;
            0)
                echo ""
                echo -e "  ${GREEN}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "  ${RED}无效选项，请重新选择${NC}"
                ;;
        esac
    done
}

# --- 命令行模式 ---
run_command() {
    local cmd="$1"; shift
    case "$cmd" in
        jc) cmd="doctor" ;;
        zt) cmd="health" ;;
        hx) cmd="profile" ;;
        zs) cmd="cert" ;;
        wg) cmd="nginx" ;;
        bs) cmd="deploy" ;;
        sc) cmd="remove" ;;
        xm) cmd="list" ;;
        bf) cmd="backup" ;;
        hf) cmd="restore" ;;
        rq) cmd="docker" ;;
        rj) cmd="logs" ;;
        dk) cmd="ports" ;;
        gx) cmd="update" ;;
        yl) cmd="deps" ;;
        yilai) cmd="deps" ;;
        gj) cmd="tools" ;;
        yw) cmd="ops" ;;
        fh) cmd="firewall" ;;
        cs) cmd="selftest" ;;
        jq) cmd="cluster" ;;
        fg) cmd="coverage" ;;
        测试|测速|cesu) cmd="bench" ;;
    esac
    
    case "$cmd" in
        health)
            health_check
            ;;
        detect|check)
            detect_all
            ;;
        doctor)
            doctor_check
            ;;
        profile|画像)
            profile_show
            ;;
        cert)
            case "${1:-status}" in
                status)   cert_status ;;
                obtain)
                    cert_obtain "$2" "$3"
                    ;;
                sync)     cert_sync "$2" ;;
                renew)    cert_renew ;;
                hook)     cert_deploy_hook ;;
                install)  cert_install ;;
                *)        echo "用法: tt cert [status|obtain <domain>|sync <domain>|renew|hook|install]" ;;
            esac
            ;;
        nginx)
            case "${1:-status}" in
                list)    nginx_list_sites ;;
                test)    nginx_test ;;
                reload)  nginx_reload ;;
                add)
                    nginx_render_site "$2" "$3"
                    ;;
                remove)
                    nginx_remove_site "$2"
                    nginx_reload
                    ;;
                *)       echo "用法: tt nginx [list|test|reload|add <domain> <port>|remove <domain>]" ;;
            esac
            ;;
        deploy)
            local plan_only="false"
            if [ "${1:-}" = "--plan" ] || [ "${1:-}" = "plan" ]; then
                plan_only="true"
                shift
            fi
            local project_name="${1:?请指定项目名称}"
            project_name="$(preset_normalize_name "$project_name")"
            preset_validate_project_name "$project_name" || die "项目名称不合法：只能使用小写字母、数字、中划线"
            local project_type="${2:-$(preset_default_type "$project_name")}" 
            local project_domain="${3:-$(preset_default_domain "$project_name")}" 
            [ "$project_domain" = "none" ] && project_domain=""
            project_domain="$(normalize_domain "$project_domain")"
            if [ -n "$project_domain" ]; then
                validate_domain "$project_domain" || die "域名不合法：${project_domain}"
            fi
            local port_group
            port_group="$(preset_port_group "$project_name" "$project_type")"
            local project_port="${4:-}"
            if [ -z "$project_port" ]; then
                project_port="$(preset_default_port "$project_name" "$project_type")" || return 1
            fi
            validate_port "$project_port" || die "端口不合法：${project_port}"
            local plan_json
            plan_json="$(preset_build_plan_json "$project_name" "$project_type" "$project_domain" "$project_port")"
            if [ "$plan_only" = "true" ]; then
                print_header "部署计划"
                preset_show_plan "$plan_json"
                return 0
            fi
            local plan_project_dir
            plan_project_dir="$(preset_plan_get "$plan_json" "project_dir")"
            secret_warn_missing_local_config "$project_type" "$plan_project_dir" || return 1
            project_deploy "$project_name" "$project_type" "$project_domain" "$project_port" "$plan_project_dir"
            ;;
        remove|delete)
            local project_name="${1:?请指定项目名称}"
            project_remove "$project_name"
            ;;
        list|ls)
            project_list
            ;;
        backup)
            case "${1:-list}" in
                create|add)
                    backup_project "${2:?请指定项目}"
                    ;;
                list|ls)
                    backup_list "${2:-}"
                    ;;
                root)
                    backup_root_info
                    ;;
                *)
                    echo "用法: tt backup [create <project>|list [project]|root]"
                    ;;
            esac
            ;;
        restore)
            case "${1:-plan}" in
                plan|check) backup_restore_plan "${2:-}" ;;
                stage|extract) backup_restore_stage "${2:-}" "${3:-}" ;;
                *) echo "用法: tt restore [plan|stage] <backup.tar.gz> [target-dir]" ;;
            esac
            ;;
        coverage|cover)
            coverage_report
            ;;
        configure|config)
            secret_configure_blueprint "${1:?请指定 blueprint 名称}" "${2:-}"
            ;;
        ports)
            case "${1:-list}" in
                list|ls) ports_list ;;
                alloc)
                    ports_allocate "${2:?请指定项目}" "${3:-future}" "${4:-main}"
                    ;;
                release)
                    ports_release_project "${2:?请指定项目}"
                    ;;
                *) echo "用法: tt ports [list|alloc <project> [group] [key]|release <project>]" ;;
            esac
            ;;
        logs)
            docker_logs "${PROJECTS_BASE}/${1:?请指定项目}" "${2:-50}"
            ;;
        docker)
            case "${1:-menu}" in
                menu)
                    docker_menu
                    ;;
                up)
                    docker_up "${PROJECTS_BASE}/${2:?请指定项目}"
                    ;;
                down)
                    docker_down "${PROJECTS_BASE}/${2:?请指定项目}"
                    ;;
                restart)
                    docker_restart "${PROJECTS_BASE}/${2:?请指定项目}"
                    ;;
                logs)
                    docker_logs "${PROJECTS_BASE}/${2:?请指定项目}" "${3:-50}"
                    ;;
                ps|projects|list)
                    docker_list_projects
                    ;;
                containers|container|ls)
                    docker_list_containers
                    ;;
                overview|resource|resources|df|stats)
                    docker_overview
                    ;;
                images|image)
                    docker_list_images
                    ;;
                storage|volumes|networks)
                    docker_list_storage
                    ;;
                check|config)
                    docker_compose_check "${2:-}"
                    ;;
                daemon|source|mirror|mirrors|ipv6)
                    docker_daemon_config
                    ;;
                audit|safe|safety)
                    docker_safety_audit
                    ;;
                *)
                    echo "用法: tt docker [overview|containers|images|storage|check [project]|daemon|audit|up|down|restart|logs <project>|ps]"
                    ;;
            esac
            ;;
        cluster|nodes)
            case "${1:-status}" in
                status|list|ls) cluster_status ;;
                menu) cluster_menu ;;
                *) echo "用法: tt cluster [status|menu]" ;;
            esac
            ;;
        deps|dependency|dependencies)
            case "${1:-doctor}" in
                doctor|check) deps_doctor ;;
                install) deps_install "${2:-recommended}" ;;
                versions|version) deps_versions ;;
                *) echo "用法: tt deps [doctor|install [required|recommended|all]|versions]" ;;
            esac
            ;;
        tools|tool)
            case "${1:-menu}" in
                menu) tools_menu ;;
                resource|resources|info) tools_resource ;;
                ports|port) tools_ports ;;
                network|net) tools_network ;;
                logs) tools_logs_recent "${2:-80}" ;;
                clean|cleanup) tools_clean_cache ;;
                update|upgrade) tools_system_update ;;
                install) tools_install "${2:-}" ;;
                swap)
                    case "${2:-status}" in
                        status|show) tools_swap_status ;;
                        add|set) tools_swap_add "${3:-}" ;;
                        *) echo "用法: tt tools swap [status|add <MB>]" ;;
                    esac
                    ;;
                *) echo "用法: tt tools [resource|ports|network|logs|clean|update|install|swap]" ;;
            esac
            ;;
        ops|op|yunwei)
            case "${1:-menu}" in
                menu) ops_menu ;;
                ssh) ops_ssh_status ;;
                dns) ops_dns_status ;;
                cron|timer|timers) ops_cron_status ;;
                bbr|tcp) ops_bbr_status ;;
                process|proc|ps) ops_process_status ;;
                disk|du|df) ops_disk_status ;;
                services|service|svc) ops_services_status ;;
                tmux|workspace|work) ops_tmux_status ;;
                *) echo "用法: tt ops [ssh|dns|cron|bbr|process|disk|services|tmux|menu]" ;;
            esac
            ;;
        firewall|fw)
            case "${1:-status}" in
                status|show) firewall_status ;;
                ports) tools_ports ;;
                menu) firewall_menu ;;
                *) echo "用法: tt firewall [status|ports|menu]" ;;
            esac
            ;;
        bench|benchmark|testnet)
            case "${1:-menu}" in
                menu) bench_menu ;;
                ip) bench_ip ;;
                dns) bench_dns ;;
                ping) bench_ping ;;
                http) bench_http ;;
                all|safe)
                    bench_ip
                    bench_dns
                    bench_ping
                    bench_http
                    ;;
                *) echo "用法: tt bench [ip|dns|ping|http|all|menu]" ;;
            esac
            ;;
        swap)
            tools_swap_add "${1:-}"
            ;;
        selftest|test)
            selftest_safe
            ;;
        upstream)
            case "${1:-report}" in
                sync|update) upstream_sync_kejilion ;;
                report) upstream_report_kejilion "${2:-}" ;;
                guard|check) upstream_guard_check ;;
                *) echo "用法: tt upstream [sync|report|guard]" ;;
            esac
            ;;
        update|upgrade)
            tt_update_system
            ;;
        install)
            install_tt
            deps_doctor || true
            cert_install
            cert_deploy_hook
            print_success "TianTian Ops 初始化完成"
            ;;
        version|--version|-v)
            echo "TianTian Ops v${TT_VERSION}"
            ;;
        help|--help|-h|"")
            echo "TianTian Ops v${TT_VERSION}"
            echo ""
            echo "用法: tt [command] [args...]"
            echo ""
            echo "命令:"
            echo "  health              系统巡检"
            echo "  detect              服务器检测"
            echo "  profile             服务器画像"
            echo "  cert status         证书状态"
            echo "  cert obtain <domain>  申请证书"
            echo "  nginx list          列出站点"
            echo "  nginx reload        重载 nginx"
            echo "  nginx add <d> <p>   添加站点"
            echo "  deploy <name> [type] [domain|none] [port] 部署项目"
            echo "  deploy --plan <name>  仅生成预设部署计划"
            echo "  configure <blueprint> [dir]  交互生成本地 .env 配置"
            echo "  remove <name>       备份后删除项目"
            echo "  backup create <name> 备份项目"
            echo "  backup list [name]  列出备份"
            echo "  restore plan <tar>  恢复预案"
            echo "  restore stage <tar> 解包到 staging"
            echo "  ports               查看端口池"
            echo "  list                列出项目"
            echo "  docker ps           Docker 项目列表"
            echo "  docker overview     Docker 资源概览"
            echo "  docker containers   全部容器列表"
            echo "  docker images       镜像列表"
            echo "  docker storage      卷/网络列表"
            echo "  docker check [name] 校验 compose 配置"
            echo "  docker daemon       Docker 配置/镜像源/IPv6"
            echo "  docker audit        Docker 安全巡检"
            echo "  docker logs <name>  查看日志"
            echo "  tools               系统工具菜单"
            echo "  tools resource      资源概览"
            echo "  tools ports         端口监听"
            echo "  tools clean         清理缓存"
            echo "  ops ssh|dns|cron|bbr|process|disk|services|tmux 常用运维只读检查"
            echo "  firewall status    防火墙/规则/端口状态"
            echo "  bench all          轻量网络测试合集"
            echo "  bench ip|dns|ping|http  单项网络测试"
            echo "  cluster status     集群节点只读状态"
            echo "  coverage           Kejilion 覆盖矩阵"
            echo "  swap <MB>           设置 swap"
            echo "  deps doctor         检查依赖"
            echo "  deps install        安装缺失依赖"
            echo "  upstream sync       同步 kejilion 参考脚本"
            echo "  upstream guard      检查 TT stream/SNI 网关保护"
            echo "  selftest            运行安全自测"
            echo "  update              拉取更新 TT 系统"
            echo "  install             初始化安装"
            echo "  version             版本信息"
            echo "  help                帮助信息"
            echo ""
            echo "拼音快捷命令:"
            echo "  jc=检测  zt=状态  bs=部署  sc=删除  bf=备份  hf=恢复"
            echo "  xm=项目  rq=容器  rj=日志  zs=证书  wg=网关  dk=端口"
            echo "  yl=依赖  gj=工具  yw=运维  fh=防火墙  jq=集群  fg=覆盖  cs=测试  cesu=网络测试"
            echo ""
            echo "不带参数运行进入交互菜单。"
            ;;
        *)
            echo "未知命令: $cmd"
            echo "运行 tt help 查看帮助"
            exit 1
            ;;
    esac
}

# --- 入口 ---
if [ $# -eq 0 ]; then
    # 交互模式
    main_loop
else
    # 命令行模式
    run_command "$@"
fi
