#!/bin/bash
# =============================================================================
# TianTian Ops - 主入口
# tt 命令：一键运维管理
# 用法: tt [command] [args...]
# =============================================================================

set -e

TT_HOME="/opt/tiantian"
export TT_HOME

# 加载核心库
source "${TT_HOME}/lib/core.sh"
source "${TT_HOME}/lib/detect.sh"
source "${TT_HOME}/lib/profile.sh"
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
    echo -e "  ${GREEN}9${NC}) 高级操作"
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
    echo -e "  ${GREEN}0${NC}) 返回"
    echo ""
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
    echo -e "  ${GREEN}0${NC}) 返回"
    echo ""
}

# --- 部署交互流程 ---
deploy_interactive() {
    echo ""
    print_title "部署新项目"
    echo ""
    
    read -p "  项目名称 (如 wordpress): " project_name
    if [ -z "$project_name" ]; then
        print_fail "项目名称不能为空"
        return 1
    fi
    
    # 检查是否已存在
    if [ -f "${PROJECTS_BASE}/${project_name}/manifest.yaml" ]; then
        print_fail "项目 ${project_name} 已存在"
        return 1
    fi
    
    read -p "  项目类型 [wordpress/node/static]: " project_type
    project_type="${project_type:-wordpress}"
    
    read -p "  域名 (如 blog.example.com，留空跳过): " domain
    
    read -p "  容器端口 [8085]: " port
    port="${port:-8085}"
    
    echo ""
    print_info "部署配置确认："
    echo "  名称: ${project_name}"
    echo "  类型: ${project_type}"
    echo "  域名: ${domain:-无}"
    echo "  端口: ${port}"
    echo ""
    
    if ! confirm "确认部署？"; then
        print_info "取消部署"
        return 0
    fi
    
    # 设置 manifest
    local dir="${PROJECTS_BASE}/${project_name}"
    mkdir -p "${dir}"/{data,logs,backups}
    # manifest written by project_deploy
    
    # 部署
    project_deploy "$project_name" "$project_type" "$domain" "$port"
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
                # 容器管理子菜单
                while true; do
                    show_docker_menu
                    read -p "  tt/docker> " dchoice
                    case "$dchoice" in
                        1) docker_list_projects ;;
                        2)
                            read -p "  项目名称: " dname
                            [ -n "$dname" ] && docker_up "${PROJECTS_BASE}/${dname}"
                            ;;
                        3)
                            read -p "  项目名称: " dname
                            [ -n "$dname" ] && docker_down "${PROJECTS_BASE}/${dname}"
                            ;;
                        4)
                            read -p "  项目名称: " dname
                            [ -n "$dname" ] && docker_restart "${PROJECTS_BASE}/${dname}"
                            ;;
                        5)
                            read -p "  项目名称: " dname
                            [ -n "$dname" ] && docker_logs "${PROJECTS_BASE}/${dname}" 50
                            ;;
                        0) break ;;
                        *) echo -e "  ${RED}无效选项${NC}" ;;
                    esac
                done
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
                while true; do
                    show_advanced_menu
                    read -p "  tt/advanced> " achoice
                    case "$achoice" in
                        1) cert_install ;;
                        2) cert_deploy_hook ;;
                        3) print_info "更新 tt 系统..."
                           if [ -d "${TT_HOME}/.git" ]; then
                               (cd "$TT_HOME" && git pull) || print_warn "git pull 失败"
                           else
                               print_warn "未检测到 git 仓库，请手动更新"
                           fi
                           ;;
                        4) 
                           print_info "清理日志 ..."
                           find "${TT_HOME}/logs/" -name "*.log" -mtime +30 -delete 2>/dev/null
                           print_success "日志已清理"
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
        health)
            health_check
            ;;
        detect|check)
            detect_all
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
            local project_name="${1:?请指定项目名称}"
            local project_type="${2:-$project_name}"
            local project_domain="${3:-}"
            local project_port="${4:-8080}"
            project_deploy "$project_name" "$project_type" "$project_domain" "$project_port"
            ;;
        remove|delete)
            local project_name="${1:?请指定项目名称}"
            project_remove "$project_name"
            ;;
        list|ls)
            project_list
            ;;
        backup)
            print_info "备份功能开发中"
            ;;
        restore)
            print_info "恢复功能开发中"
            ;;
        docker)
            case "${1:-}" in
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
                ps|list)
                    docker_list_projects
                    ;;
                *)
                    echo "用法: tt docker [up|down|restart|logs <project>|ps]"
                    ;;
            esac
            ;;
        install)
            install_tt
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
            echo "  deploy <name> [type] 部署项目"
            echo "  remove <name>       删除项目"
            echo "  list                列出项目"
            echo "  docker ps           容器列表"
            echo "  docker logs <name>  查看日志"
            echo "  install             初始化安装"
            echo "  version             版本信息"
            echo "  help                帮助信息"
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
