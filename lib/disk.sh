#!/bin/bash
# =============================================================================
# TianTian Ops - disk.sh
# Disk, partition, mount and filesystem helpers. Destructive actions require --yes.
# =============================================================================

_disk_need_yes() {
    local yes_flag="${1:-}"
    [ "$yes_flag" = "--yes" ] && return 0
    print_warn "高风险写入操作未执行。确认了解风险后追加 --yes。"
    return 1
}

_disk_backup_fstab() {
    local stamp backup
    stamp="$(date +%Y%m%d_%H%M%S_%N 2>/dev/null || date +%Y%m%d_%H%M%S)"
    backup="/etc/fstab.bak.tt.${stamp}.$$"
    if [ -f /etc/fstab ]; then
        cp /etc/fstab "$backup" || return 1
        echo "$backup"
    fi
}

_disk_device_fstype() {
    blkid -s TYPE -o value "$1" 2>/dev/null || true
}

_disk_device_uuid() {
    blkid -s UUID -o value "$1" 2>/dev/null || true
}

_disk_device_mounts() {
    lsblk -nrpo MOUNTPOINTS "$1" 2>/dev/null | sed '/^$/d' | paste -sd ',' -
}

_disk_validate_device() {
    local device="$1"
    [ -n "$device" ] || { print_fail "请指定设备"; return 1; }
    [ -b "$device" ] || { print_fail "设备不存在或不是块设备: $device"; return 1; }
}

_disk_validate_mountpoint() {
    local mountpoint="$1"
    [ -n "$mountpoint" ] || { print_fail "请指定挂载点"; return 1; }
    case "$mountpoint" in
        /|/boot|/boot/*|/etc|/etc/*|/bin|/bin/*|/sbin|/sbin/*|/usr|/usr/*|/var|/var/lib|/var/lib/docker|/proc|/sys|/dev|/run)
            print_fail "挂载点过于危险: $mountpoint"
            return 1
            ;;
    esac
}

_disk_validate_fstype() {
    case "$1" in
        ext4|xfs) return 0 ;;
        *) print_fail "当前仅支持 ext4/xfs"; return 1 ;;
    esac
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
    for cmd in mkfs.ext4 mkfs.xfs blkid findmnt lsblk mount umount; do
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
    _disk_validate_device "$device" || return 1
    _disk_validate_mountpoint "$mountpoint" || return 1
    local uuid detected_fs
    uuid="$(_disk_device_uuid "$device")"
    detected_fs="$(_disk_device_fstype "$device")"
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
    print_warn "真实执行: tt disk mount-write $device $mountpoint ${fstype} --yes"
}

disk_format_plan() {
    local device="$1" fstype="${2:-ext4}" label="${3:-}" existing_fs existing_mounts
    print_header "格式化预案"
    [ -n "$device" ] || { echo "用法: tt disk format-plan <device> [ext4|xfs] [label]"; return 1; }
    _disk_validate_device "$device" || return 1
    _disk_validate_fstype "$fstype" || return 1
    existing_fs="$(_disk_device_fstype "$device")"
    existing_mounts="$(_disk_device_mounts "$device")"
    echo "设备: $device"
    echo "现有文件系统: ${existing_fs:-无/未知}"
    echo "当前挂载: ${existing_mounts:-未挂载}"
    echo "目标文件系统: $fstype"
    [ -n "$label" ] && echo "标签: $label"
    echo ""
    echo "高风险步骤（未执行）:"
    echo "  cp /etc/fstab /etc/fstab.bak.tt.$(date +%Y%m%d_%H%M%S)"
    echo "  umount '$device'  # 如已挂载，先确认没有业务占用"
    case "$fstype" in
        ext4)
            if [ -n "$label" ]; then
                echo "  mkfs.ext4 -F -L '$label' '$device'"
            else
                echo "  mkfs.ext4 -F '$device'"
            fi
            ;;
        xfs)
            if [ -n "$label" ]; then
                echo "  mkfs.xfs -f -L '$label' '$device'"
            else
                echo "  mkfs.xfs -f '$device'"
            fi
            ;;
    esac
    echo "  blkid '$device'"
    echo ""
    print_warn "真实执行: tt disk format-write $device $fstype ${label:-''} --yes"
}

disk_format_write() {
    local device="$1" fstype="${2:-ext4}" label="${3:-}" yes_flag="${4:-}"
    print_header "真实格式化"
    echo "设备: $device"
    echo "目标文件系统: $fstype"
    [ -n "$label" ] && echo "标签: $label"
    print_warn "将清空目标设备数据。"
    _disk_validate_device "$device" || return 1
    _disk_validate_fstype "$fstype" || return 1
    _disk_need_yes "$yes_flag" || return 1
    local mounts backup
    mounts="$(_disk_device_mounts "$device")"
    if [ -n "$mounts" ]; then
        print_fail "设备仍在挂载中: $mounts；请先 tt disk unmount-write $device --yes"
        return 1
    fi
    backup="$(_disk_backup_fstab)" || { print_fail "备份 /etc/fstab 失败"; return 1; }
    [ -n "$backup" ] && print_success "已备份 /etc/fstab: $backup"
    case "$fstype" in
        ext4)
            if [ -n "$label" ]; then
                mkfs.ext4 -F -L "$label" "$device"
            else
                mkfs.ext4 -F "$device"
            fi
            ;;
        xfs)
            has_cmd mkfs.xfs || { print_fail "缺少 mkfs.xfs"; return 1; }
            if [ -n "$label" ]; then
                mkfs.xfs -f -L "$label" "$device"
            else
                mkfs.xfs -f "$device"
            fi
            ;;
    esac
    print_success "格式化完成"
    blkid "$device" || true
}

disk_mount_write() {
    local device="$1" mountpoint="$2" fstype="${3:-}" yes_flag="${4:-}" uuid source backup entry
    print_header "真实挂载"
    echo "设备: $device"
    echo "挂载点: $mountpoint"
    _disk_validate_device "$device" || return 1
    _disk_validate_mountpoint "$mountpoint" || return 1
    _disk_need_yes "$yes_flag" || return 1
    uuid="$(_disk_device_uuid "$device")"
    fstype="${fstype:-$(_disk_device_fstype "$device")}"
    [ -n "$fstype" ] || { print_fail "无法检测文件系统，请指定 fstype"; return 1; }
    mkdir -p "$mountpoint"
    mount "$device" "$mountpoint" || return 1
    source="$device"
    if [ -n "$uuid" ]; then
        source="UUID=$uuid"
    fi
    entry="$source $mountpoint $fstype defaults,nofail 0 2"
    if ! grep -Fqs " $mountpoint " /etc/fstab 2>/dev/null && ! grep -Fqs "$source " /etc/fstab 2>/dev/null; then
        backup="$(_disk_backup_fstab)" || { print_fail "备份 /etc/fstab 失败"; return 1; }
        [ -n "$backup" ] && print_success "已备份 /etc/fstab: $backup"
        printf '%s\n' "$entry" >> /etc/fstab
        print_success "已写入 /etc/fstab: $entry"
    else
        print_warn "/etc/fstab 已存在同设备或同挂载点条目，未重复写入"
    fi
    findmnt "$mountpoint" && df -hT "$mountpoint"
}

disk_unmount_write() {
    local target="$1" yes_flag="${2:-}" backup
    print_header "真实卸载"
    [ -n "$target" ] || { echo "用法: tt disk unmount-write <device|mountpoint> --yes"; return 1; }
    print_warn "将卸载目标并尝试移除 /etc/fstab 中匹配设备/挂载点条目。"
    _disk_need_yes "$yes_flag" || return 1
    if findmnt "$target" >/dev/null 2>&1 || mountpoint -q "$target" 2>/dev/null; then
        umount "$target" || return 1
    elif [ -b "$target" ]; then
        umount "$target" || true
    else
        print_warn "目标当前未挂载: $target"
    fi
    if [ -f /etc/fstab ]; then
        backup="$(_disk_backup_fstab)" || { print_fail "备份 /etc/fstab 失败"; return 1; }
        [ -n "$backup" ] && print_success "已备份 /etc/fstab: $backup"
        awk -v target="$target" 'BEGIN{changed=0} $0 ~ /^[[:space:]]*#/ || NF < 2 {print; next} $1 == target || $2 == target {changed=1; next} {print} END{}' /etc/fstab > /etc/fstab.tt.tmp
        cat /etc/fstab.tt.tmp > /etc/fstab
        rm -f /etc/fstab.tt.tmp
        print_success "已清理 /etc/fstab 中匹配 $target 的条目（如存在）"
    fi
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
        echo "  7) 真实格式化 ⚠️"
        echo "  8) 真实挂载并写 fstab ⚠️"
        echo "  9) 真实卸载并清理 fstab ⚠️"
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
            7)
                read -r -p "  设备: " device
                read -r -p "  文件系统 ext4/xfs [ext4]: " fstype
                read -r -p "  标签（可空）: " label
                disk_format_write "$device" "${fstype:-ext4}" "$label" --yes
                ;;
            8)
                read -r -p "  设备: " device
                read -r -p "  挂载点: " mountpoint
                read -r -p "  文件系统（可空自动检测）: " fstype
                disk_mount_write "$device" "$mountpoint" "$fstype" --yes
                ;;
            9)
                read -r -p "  设备或挂载点: " target
                disk_unmount_write "$target" --yes
                ;;
            0) break ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
    done
}
