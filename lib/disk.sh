#!/bin/bash
# =============================================================================
# TianTian Ops - disk.sh
# Disk, partition, mount and filesystem planning helpers. Defaults are read-only.
# =============================================================================

_disk_has_lsblk_json() {
    lsblk --help 2>/dev/null | grep -q -- '--json'
}

disk_overview() {
    print_header "磁盘 / 分区总览"
    print_title "块设备"
    if has_cmd lsblk; then
        lsblk -o NAME,TYPE,SIZE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS,MODEL,TRAN 2>/dev/null || lsblk
    else
        print_warn "缺少 lsblk"
    fi
    echo ""

    print_title "文件系统使用"
    df -hT -x overlay -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | sed -n '1,30p' || df -hT 2>/dev/null | sed -n '1,30p' || true
    echo ""

    print_title "inode 使用"
    df -ih -x overlay -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | sed -n '1,30p' || df -ih 2>/dev/null | sed -n '1,30p' || true
}

disk_mounts() {
    print_header "挂载状态"
    print_title "findmnt"
    if has_cmd findmnt; then
        findmnt -rno TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | awk '$3 != "overlay" && $3 != "nsfs" {print}' | sed -n '1,80p'
    else
        mount | grep -Ev ' type (overlay|nsfs) ' | sed -n '1,80p'
    fi
    echo ""

    print_title "/etc/fstab"
    if [ -f /etc/fstab ]; then
        sed -n '1,120p' /etc/fstab
    else
        print_warn "未找到 /etc/fstab"
    fi
}

disk_candidates() {
    print_header "未挂载候选分区"
    if ! has_cmd lsblk; then
        print_fail "缺少 lsblk"
        return 1
    fi
    lsblk -prno NAME,TYPE,SIZE,FSTYPE,UUID,MOUNTPOINTS 2>/dev/null | awk '
        $2 == "part" && ($6 == "" || $6 == "-") {
            printf "%-24s %-8s %-10s %-36s %s\n", $1, $3, ($4==""?"no-fs":$4), ($5==""?"no-uuid":$5), "未挂载"
        }
    ' || true
    echo ""
    print_warn "只列候选，不代表可安全格式化；执行任何写入前必须确认数据用途和备份。"
}

disk_health() {
    print_header "磁盘健康 / 工具状态"
    print_title "SMART 工具"
    if has_cmd smartctl; then
        smartctl --version 2>/dev/null | sed -n '1,2p'
        echo ""
        print_title "设备 SMART 摘要"
        if has_cmd lsblk; then
            lsblk -dnpo NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}' | while read -r dev; do
                [ -n "$dev" ] || continue
                echo "-- $dev"
                smartctl -H "$dev" 2>/dev/null | grep -E 'SMART overall-health|SMART Health Status|overall-health|PASSED|OK|FAILED' || print_warn "无法读取 SMART（云盘/NVMe/虚拟盘可能不支持）"
            done
        fi
    else
        print_warn "smartctl 未安装；可用: tt tools install smartmontools"
    fi
    echo ""

    print_title "文件系统工具"
    for cmd in mkfs.ext4 mkfs.xfs blkid findmnt lsblk; do
        if has_cmd "$cmd"; then
            printf '%-12s %s\n' "$cmd" "$(command -v "$cmd")"
        else
            printf '%-12s %s\n' "$cmd" "missing"
        fi
    done
}

disk_mount_plan() {
    local device="$1" mountpoint="$2" fstype="${3:-}"
    print_header "挂载预案"
    [ -n "$device" ] && [ -n "$mountpoint" ] || { echo "用法: tt disk mount-plan <device> <mountpoint> [fstype]"; return 1; }
    if [ ! -b "$device" ]; then
        print_fail "设备不存在或不是块设备: $device"
        return 1
    fi
    local uuid detected_fs
    uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
    detected_fs="$(blkid -s TYPE -o value "$device" 2>/dev/null || true)"
    fstype="${fstype:-$detected_fs}"
    [ -n "$fstype" ] || fstype="ext4"
    echo "设备: $device"
    echo "UUID: ${uuid:-未检测到}"
    echo "文件系统: $fstype"
    echo "挂载点: $mountpoint"
    echo ""
    echo "建议步骤:"
    echo "  mkdir -p '$mountpoint'"
    if [ -n "$uuid" ]; then
        echo "  mount UUID=$uuid '$mountpoint'"
        echo "  echo 'UUID=$uuid $mountpoint $fstype defaults,nofail 0 2' >> /etc/fstab"
    else
        echo "  mount '$device' '$mountpoint'"
        echo "  echo '$device $mountpoint $fstype defaults,nofail 0 2' >> /etc/fstab"
    fi
    echo "  findmnt '$mountpoint' && df -hT '$mountpoint'"
    echo ""
    print_warn "本命令不写入系统；真实挂载前请确认设备数据和 /etc/fstab 备份。"
}

disk_format_plan() {
    local device="$1" fstype="${2:-ext4}" label="${3:-}" existing_fs existing_mounts
    print_header "格式化预案"
    [ -n "$device" ] || { echo "用法: tt disk format-plan <device> [ext4|xfs] [label]"; return 1; }
    if [ ! -b "$device" ]; then
        print_fail "设备不存在或不是块设备: $device"
        return 1
    fi
    case "$fstype" in ext4|xfs) ;; *) print_fail "当前只生成 ext4/xfs 预案"; return 1 ;; esac
    existing_fs="$(blkid -s TYPE -o value "$device" 2>/dev/null || true)"
    existing_mounts="$(lsblk -nrpo MOUNTPOINTS "$device" 2>/dev/null | sed '/^$/d' | paste -sd ',' -)"
    echo "设备: $device"
    echo "现有文件系统: ${existing_fs:-无/未知}"
    echo "当前挂载: ${existing_mounts:-未挂载}"
    echo "目标文件系统: $fstype"
    [ -n "$label" ] && echo "标签: $label"
    echo ""
    echo "高风险步骤（未执行）:"
    echo "  cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    echo "  umount '$device'  # 如已挂载，先确认没有业务占用"
    case "$fstype" in
        ext4)
            if [ -n "$label" ]; then
                echo "  mkfs.ext4 -L '$label' '$device'"
            else
                echo "  mkfs.ext4 '$device'"
            fi
            ;;
        xfs)
            if [ -n "$label" ]; then
                echo "  mkfs.xfs -L '$label' '$device'"
            else
                echo "  mkfs.xfs '$device'"
            fi
            ;;
    esac
    echo "  blkid '$device'"
    echo ""
    print_warn "格式化会清空设备数据；TT 只生成预案，不自动执行。"
}

disk_menu() {
    while true; do
        echo ""
        print_title "磁盘 / 挂载管理"
        echo ""
        echo "  1) 磁盘分区总览 ✅"
        echo "  2) 挂载/fstab 状态 ✅"
        echo "  3) 未挂载候选分区 ✅"
        echo "  4) 磁盘健康/工具状态 ✅"
        echo "  5) 挂载预案 ✅"
        echo "  6) 格式化预案 ⚠️"
        echo "  0) 返回"
        echo ""
        read -r -p "  tt/disk> " choice
        case "$choice" in
            1) disk_overview ;;
            2) disk_mounts ;;
            3) disk_candidates ;;
            4) disk_health ;;
            5)
                read -r -p "  设备: " device
                read -r -p "  挂载点: " mountpoint
                read -r -p "  文件系统（可空自动检测）: " fstype
                disk_mount_plan "$device" "$mountpoint" "$fstype"
                ;;
            6)
                read -r -p "  设备: " device
                read -r -p "  文件系统 ext4/xfs [ext4]: " fstype
                read -r -p "  标签（可空）: " label
                disk_format_plan "$device" "${fstype:-ext4}" "$label"
                ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
