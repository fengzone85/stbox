#!/usr/bin/env bash
# 模块：实用工具（磁盘挂载、常用软件、探针/面板/节点/代理脚本入口）

sst_register_module tools "实用工具" "磁盘 工具 探针 面板 代理"
SST_MODULE_ITEMS[tools]=$'disk_mount|磁盘挂载与 fstab\ngit|安装/升级 Git\nrclone|安装 Rclone\nfclone|Fclone 安装\nscripts|第三方工具脚本\naria2|Aria2 安装管理\nipt|IPTables 工具\nchangesource|第三方换源脚本\nprobes|监控探针（Nezha/Komari/Diting）\npanels|面板安装脚本\nnodes|节点搭建脚本合集\nproxy|代理与转发脚本\nkernel|内核与 BBR 脚本\nbbr3|BBR3/tcpx 管理\nbbrmanage|BBR 一键管理\nbbrkernel|BBR 内核（CentOS）\nwarp|WARP 管理（ChatGPT/Netflix）\nmtp|MTP&TLS 代理\nnezha|哪吒探针\nkomari|Komari 探针\nditing|Diting 探针\nbaota|宝塔面板\noracle|甲骨文云脚本\nreinstall|DD/重装脚本\nnat|NAT 小鸡管理'

tools_disk_mount() {
  require_root
  section "块设备"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID 2>/dev/null || die "lsblk 不可用，请安装 util-linux"
  hr

  local device
  device=$(ask "要挂载的设备（如 /dev/vdb1，留空取消）" "")
  [[ -n $device ]] || return 0
  [[ -b $device ]] || die "不是块设备：$device"

  local mounted
  mounted=$(lsblk -no MOUNTPOINT "$device" 2>/dev/null | head -n 1)
  [[ -z $mounted ]] || die "$device 已挂载或正在使用（$mounted）"

  local dev_type
  dev_type=$(lsblk -ndo TYPE "$device" 2>/dev/null | head -n 1)
  if [[ $dev_type == disk ]]; then
    local children
    children=$(lsblk -no NAME "$device" 2>/dev/null | wc -l)
    if (( children > 1 )); then
      die "该磁盘已有分区，请直接选择分区设备（如 ${device}1）"
    fi
  fi

  # 避免误操作系统盘
  local root_src root_parent dev_parent
  root_src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
  root_parent=''
  [[ -n $root_src ]] && root_parent=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n 1)
  dev_parent=$(lsblk -no PKNAME "$device" 2>/dev/null | head -n 1)
  if [[ -n $dev_parent && $dev_parent == "$root_parent" ]]; then
    die "$device 属于系统盘（$root_parent），已拒绝操作"
  fi

  local fstype
  fstype=$(lsblk -no FSTYPE "$device" 2>/dev/null | head -n 1)
  [[ $fstype != swap ]] || die "$device 是 SWAP 分区，已拒绝挂载"
  if [[ -z $fstype ]]; then
    warn "设备没有文件系统，继续将格式化 $device 并清空其数据"
    local phrase
    read -r -p "输入 FORMAT 确认格式化: " phrase || return 1
    [[ $phrase == FORMAT ]] || { warn "已取消"; return 0; }
    mkfs.ext4 "$device" || die "格式化失败"
    fstype=ext4
  else
    info "设备已有文件系统：$fstype，跳过格式化"
  fi

  local mountpoint
  mountpoint=$(ask "挂载点" "/mnt/data")
  [[ $mountpoint == /* ]] || die "挂载点必须是绝对路径"
  if findmnt -n "$mountpoint" >/dev/null 2>&1; then
    die "$mountpoint 已被占用"
  fi
  mkdir -p "$mountpoint" || die "无法创建挂载点"
  mount "$device" "$mountpoint" || die "挂载失败"
  ok "已挂载 $device → $mountpoint"

  local uuid entry
  uuid=$(blkid -s UUID -o value "$device" 2>/dev/null || true)
  if [[ -n $uuid ]]; then
    entry="UUID=$uuid $mountpoint $fstype defaults,nofail 0 2"
  else
    entry="$device $mountpoint $fstype defaults,nofail 0 2"
  fi

  backup_config_file /etc/fstab fstab >/dev/null 2>&1 || true
  if awk -v m="$mountpoint" '$2 == m {found=1} END {exit !found}' /etc/fstab; then
    info "/etc/fstab 已存在该挂载点，未重复写入"
  else
    printf '%s\n' "$entry" >>/etc/fstab
    ok "已写入 /etc/fstab：$entry"
  fi

  df -hT "$mountpoint" 2>/dev/null || true
  info "如需卸载：umount $mountpoint，并从 /etc/fstab 删除对应行"
}

tools_git() {
  require_root
  if have git; then
    info "当前版本：$(git --version)"
  fi
  confirm "通过系统包管理器安装/升级 Git？" || return 0
  pkg_update || die "软件源更新失败"
  pkg_install git || die "Git 安装失败"
  git --version
}

tools_rclone() {
  require_root
  if have rclone; then
    info "当前版本：$(rclone version 2>/dev/null | head -n 1)"
    confirm "重新安装/升级 Rclone？" || return 0
  else
    confirm "安装 Rclone？" || return 0
  fi

  if confirm "优先使用系统包管理器安装？"; then
    pkg_update >/dev/null 2>&1 || true
    if pkg_install rclone; then
      rclone version 2>/dev/null | head -n 1
      ok "Rclone 安装完成"
      return 0
    fi
    warn "包管理器安装失败，尝试官方脚本"
  fi

  confirm "下载并执行 Rclone 官方安装脚本（rclone.org）？" || return 0
  local tmp
  tmp=$(mktemp)
  curl -fsSL --connect-timeout 10 --max-time 120 -o "$tmp" https://rclone.org/install.sh \
    || { rm -f "$tmp"; die "下载官方安装脚本失败"; }
  bash "$tmp"
  local rc=$?
  rm -f "$tmp"
  (( rc == 0 )) || die "Rclone 官方脚本执行失败"
  have rclone && rclone version | head -n 1
  ok "Rclone 安装完成"
}

tools_fclone() {
  require_root
  [[ $ARCH == x86_64 ]] || die "Fclone 二进制仅提供 x86_64 版本，当前为 $ARCH"
  if have fclone; then
    info "已安装：$(fclone version 2>/dev/null | head -n 1)"
    confirm "重新下载/覆盖安装 Fclone？" || return 0
  else
    confirm "下载 Fclone 到 /usr/local/bin/fclone？" || return 0
  fi
  local tmp
  tmp=$(mktemp)
  if ! download_with_fallback https://raw.githubusercontent.com/BlueSkyXN/RcloneX/master/fclone "$tmp" 90; then
    rm -f "$tmp"
    die "Fclone 下载失败"
  fi
  install -m 0755 "$tmp" /usr/local/bin/fclone || { rm -f "$tmp"; die "安装失败"; }
  rm -f "$tmp"
  ok "Fclone 已安装：/usr/local/bin/fclone"
  fclone version 2>/dev/null | head -n 1 || true
}

tools_scripts() { scripts_menu 工具; }
tools_warp() { scripts_run warp; }
tools_bbr3() { scripts_run bbr3; }
tools_probes() { scripts_menu 探针; }
tools_nodes() { scripts_menu 节点; }
tools_panels() { scripts_menu 面板; }
tools_proxy() { scripts_menu 代理; }
tools_kernel() { scripts_menu 内核; }
tools_oracle() { scripts_menu 甲骨文; }
tools_reinstall() { scripts_menu 重装; }
tools_nat() { scripts_menu NAT; }
