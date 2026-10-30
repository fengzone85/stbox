#!/usr/bin/env bash
# 模块：开荒向导（P1：预检 / 磁盘检测与已有文件系统挂载 / 基础信息 / 报告）

sst_register_module init "开荒向导" "预检 磁盘 基础信息"
SST_MODULE_ITEMS[init]=$'wizard|开始/继续开荒\npreflight|服务器预检\ndisk|磁盘检测与挂载\nbasics|基础信息设置\nstatus|查看进度\nreport|生成报告\nreset|重置向导'

init_status() {
  require_root
  wizard_init
  wizard_status_table
  if [[ $(wizard_step_status preflight) == pending ]]; then
    info "运行 st init 开始，或 st init preflight 单独执行预检"
  fi
}

init_preflight_show() {
  local mem_total mem_used mem_avail cpu cores disk swap_state ip keys ufw docker_ver
  local ssh_ports root_login pass_auth bbr tz
  cpu=$(get_cpu_model)
  [[ -n $cpu ]] || cpu="未知"
  cores=$(nproc 2>/dev/null || echo 未知)
  read -r mem_total mem_used mem_avail <<<"$(get_mem_info)"
  disk=$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s 已用 %s (%s)", $2, $3, $5}')
  swap_state=$(free -m 2>/dev/null | awk 'NR==3 {if ($2 == 0) print "未启用"; else printf "%d/%d MB (%d%%)", $3, $2, $3 * 100 / $2}')
  ip=$(get_public_ip)
  keys=$(find /root /home -maxdepth 4 -name authorized_keys -type f -size +0c 2>/dev/null | wc -l)
  ufw=$(_fw_installed)
  docker_ver="未安装"
  have docker && docker_ver=$(docker --version 2>/dev/null | sed 's/^Docker version //;s/,.*//')
  ssh_ports=$(ssh_all_ports)
  root_login=$(ssh_cfg_get PermitRootLogin)
  pass_auth=$(ssh_cfg_get PasswordAuthentication)
  bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)
  if have timedatectl; then
    tz=$(timedatectl show -p Timezone --value 2>/dev/null || date +%Z)
  else
    tz=$(date +%Z)
  fi

  section "服务器预检"
  kv "主机名" "$(hostname)"
  kv "系统" "$OS_NAME"
  kv "内核" "$(uname -r)"
  kv "架构" "$ARCH"
  kv "虚拟化" "$VIRT"
  kv "CPU" "$cpu（${cores} 核）"
  kv "内存" "${mem_used}/${mem_total} MB（可用 ${mem_avail} MB）"
  kv "磁盘 /" "$disk"
  kv "SWAP" "$swap_state"
  kv "公网 IP" "$ip"
  kv "时区" "$tz"
  kv "DNS" "$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
  hr
  kv "SSH 端口" "$ssh_ports"
  kv "root 登录" "$root_login"
  kv "密码登录" "$pass_auth"
  kv "SSH 密钥" "${keys} 个用户含 authorized_keys"
  kv "防火墙" "$ufw / $(_ufw_state)"
  kv "Docker" "$docker_ver"
  kv "TCP 算法" "$bbr"

  section "预检提示"
  (( keys > 0 )) || warn "未发现 authorized_keys，暂不建议关闭密码登录"
  [[ $pass_auth == yes ]] && warn "当前允许密码登录，完成密钥验证后建议关闭"
  [[ $root_login == yes ]] && warn "当前允许 root 密码登录，安全基线建议收紧"
  [[ $ufw == ufw && $(_ufw_state) == inactive ]] && warn "UFW 未启用，安全基线建议启用"
  have docker && warn "已安装 Docker：UFW 不能完全保护 Docker 发布的端口"
  sysctl -n net.ipv4.tcp_syncookies 2>/dev/null | grep -qx 1 || warn "TCP syncookies 未启用"
}

init_preflight() {
  require_root
  wizard_init
  init_preflight_show
  confirm "预检完成，标记为已完成？" || return 0
  wizard_mark preflight done
  ok "预检已记录"
}

init_disk_scan() {
  section "磁盘扫描"
  info "只读扫描，不会格式化或删除任何数据"
  if have lsblk; then
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID,MODEL,ROTA 2>/dev/null
  else
    warn "lsblk 不可用，请安装 util-linux"
  fi
  hr
  df -hT 2>/dev/null || df -h
  hr
  local root_src chain c
  root_src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
  if [[ -n $root_src ]]; then
    mapfile -t chain < <(lsblk -s -no NAME "$root_src" 2>/dev/null)
    kv "根分区" "$root_src"
    kv "系统盘链路" "$(printf '%s' "${chain[*]}")"
  else
    warn "无法识别根分区来源（可能是 overlay/容器）"
  fi
  if have swapon; then
    printf '\n'
    swapon --show 2>/dev/null || true
  fi
  warn "带文件系统的未挂载分区可在下一步“挂载已有文件系统”，向导不提供格式化"
}

init_disk_is_system() {
  local device=$1 root_src chain c parent name
  root_src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
  [[ -n $root_src ]] || return 2
  name=$(basename "$device")
  parent=$(lsblk -no PKNAME "$device" 2>/dev/null | head -n 1)
  mapfile -t chain < <(lsblk -s -no NAME "$root_src" 2>/dev/null)
  for c in "${chain[@]}"; do
    [[ $c == "$name" ]] && return 0
    [[ -n $parent && $c == "$parent" ]] && return 0
  done
  return 1
}

init_disk_details() {
  local device
  device=$(ask "设备路径（如 /dev/sdb1）" "")
  [[ -n $device ]] || return 0
  [[ -b $device ]] || die "不是块设备：$device"
  section "设备详情：$device"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID,MODEL,SERIAL,ROTA "$device" 2>/dev/null
  hr
  blkid "$device" 2>/dev/null || true
  if have smartctl; then
    smartctl -H "$device" 2>/dev/null || warn "SMART 状态不可读"
  else
    info "安装 smartmontools 可查看 SMART 健康状态"
  fi
}

init_disk_mount_existing() {
  local device mounted dev_type children fstype mountpoint uuid entry fstab_backup old
  section "挂载已有文件系统"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID,MODEL 2>/dev/null
  printf '\n'
  device=$(ask "要挂载的设备（如 /dev/sdb1，留空取消）" "")
  [[ -n $device ]] || return 0
  [[ -b $device ]] || die "不是块设备：$device"

  mounted=$(lsblk -no MOUNTPOINT "$device" 2>/dev/null | head -n 1)
  [[ -z $mounted ]] || die "$device 已挂载或正在使用（$mounted）"

  dev_type=$(lsblk -ndo TYPE "$device" 2>/dev/null | head -n 1)
  if [[ $dev_type == disk ]]; then
    children=$(lsblk -no NAME "$device" 2>/dev/null | wc -l)
    (( children <= 1 )) || die "该磁盘已有分区，请选择分区设备（如 ${device}1）"
  fi

  fstype=$(lsblk -no FSTYPE "$device" 2>/dev/null | head -n 1)
  if [[ -z $fstype ]]; then
    die "$device 没有文件系统；向导不执行格式化，请先手动创建文件系统"
  fi
  case $fstype in
    swap|LVM2_member|crypto_LUKS|linux_raid_member)
      die "$device 类型为 $fstype，已拒绝自动挂载" ;;
    ntfs|vfat)
      warn "文件系统 $fstype 需要额外驱动或权限，建议手动挂载" ;;
  esac

  init_disk_is_system "$device"
  case $? in
    0) die "$device 属于系统盘，已拒绝操作" ;;
    2) die "无法确认系统盘来源，已拒绝自动挂载" ;;
  esac

  mountpoint=$(ask "挂载点" "/data")
  [[ $mountpoint == /* ]] || die "挂载点必须是绝对路径"
  findmnt -n "$mountpoint" >/dev/null 2>&1 && die "$mountpoint 已被占用"

  uuid=$(blkid -s UUID -o value "$device" 2>/dev/null || true)
  if [[ -n $uuid ]]; then
    entry="UUID=$uuid $mountpoint $fstype defaults,nofail 0 0"
  else
    warn "无法读取 UUID，将使用设备路径；设备名变化时可能挂载失败"
    entry="$device $mountpoint $fstype defaults,nofail 0 0"
  fi

  fstab_backup=$(backup_config_file /etc/fstab fstab) || die "备份 /etc/fstab 失败"
  if awk -v m="$mountpoint" '$2 == m {found=1} END {exit !found}' /etc/fstab; then
    info "/etc/fstab 已存在 $mountpoint，跳过写入"
  else
    printf '%s\n' "$entry" >>/etc/fstab
    info "已写入 /etc/fstab：$entry"
  fi

  mkdir -p "$mountpoint" || { cp "$fstab_backup" /etc/fstab; die "无法创建挂载点"; }
  if ! mount "$device" "$mountpoint"; then
    cp "$fstab_backup" /etc/fstab
    rmdir "$mountpoint" 2>/dev/null || true
    die "挂载失败，/etc/fstab 已恢复"
  fi
  if ! findmnt -n "$mountpoint" >/dev/null 2>&1; then
    umount "$mountpoint" 2>/dev/null || true
    cp "$fstab_backup" /etc/fstab
    rmdir "$mountpoint" 2>/dev/null || true
    die "挂载校验失败，/etc/fstab 已恢复"
  fi

  old=$(wizard_get DATA_DISKS)
  [[ -n $old ]] && old="${old},"
  wizard_set DATA_DISKS "${old}${device}:${mountpoint}"
  df -hT "$mountpoint" 2>/dev/null || true
  ok "已挂载 $device → $mountpoint，并写入 fstab（nofail）"
  info "如需卸载：umount $mountpoint，并从 /etc/fstab 删除对应行"
}

init_disk() {
  wizard_init
  if [[ ${1:-} == scan ]]; then
    init_disk_scan
    return 0
  fi
  require_root
  [[ -t 0 ]] || die "非交互环境请使用：st init disk scan"
  init_disk_scan
  local choice
  while true; do
    printf '\n  1) 挂载已有文件系统（不格式化，推荐）\n'
    printf '  2) 查看设备详情 / SMART\n'
    printf '  3) 扫描完成，跳过挂载\n'
    printf '  0) 保存并退出\n\n'
    read -r -p "请选择: " choice || return 0
    case $choice in
      1) init_disk_mount_existing ;;
      2) init_disk_details; pause ;;
      3) wizard_mark disk done; break ;;
      0|q|back) return 0 ;;
      *) warn "无效选项：$choice" ;;
    esac
  done
  ok "磁盘步骤完成"
}

init_apply_timezone() {
  local tz=$1
  [[ -f /usr/share/zoneinfo/$tz ]] || die "无效时区：$tz"
  if have timedatectl; then
    timedatectl set-timezone "$tz" || die "时区设置失败"
  else
    ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime || die "时区设置失败"
    printf '%s\n' "$tz" >/etc/timezone
  fi
  wizard_set TIMEZONE "$tz"
  ok "时区已设置为 $tz"
}

init_apply_hostname() {
  local name=$1
  [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "主机名只能包含字母、数字、点和短横线"
  if have hostnamectl; then
    hostnamectl set-hostname "$name" || die "主机名修改失败"
  else
    hostname "$name" || die "主机名修改失败"
    printf '%s\n' "$name" >/etc/hostname
  fi
  if grep -q '^127\.0\.1\.1' /etc/hosts 2>/dev/null; then
    backup_config_file /etc/hosts hosts >/dev/null 2>&1 || true
    local tmp
    tmp=$(mktemp)
    awk -v h="$name" '/^127\.0\.1\.1/ {print "127.0.1.1 " h; next} {print}' /etc/hosts >"$tmp"
    cat "$tmp" >/etc/hosts
    rm -f "$tmp"
  fi
  wizard_set HOSTNAME "$name"
  ok "主机名已设置为 $name"
}

init_enable_timesyncd() {
  if [[ ${INIT:-sysv} == systemd ]] && have systemctl; then
    case ${PKG:-unknown} in
      apt) pkg_install systemd-timesyncd || true ;;
    esac
    timedatectl set-ntp true 2>/dev/null || true
    svc_enable systemd-timesyncd || warn "systemd-timesyncd 启动失败"
    wizard_set TIMESYNC timesyncd
  else
    init_enable_chrony
  fi
}

init_enable_chrony() {
  pkg_update || die "软件源更新失败"
  pkg_install chrony || die "chrony 安装失败"
  if [[ ${INIT:-sysv} == systemd ]] && have systemctl; then
    systemctl disable --now systemd-timesyncd >/dev/null 2>&1 || true
  fi
  svc_enable chrony || svc_enable chronyd || warn "chrony 服务启动失败"
  wizard_set TIMESYNC chrony
  ok "chrony 已启用"
}

init_apply_dns() {
  local -a servers=("$@")
  [[ ${#servers[@]} -gt 0 ]] || die "未提供 DNS 服务器"
  local ip
  for ip in "${servers[@]}"; do
    [[ $ip =~ ^[0-9A-Fa-f:.]+$ ]] || die "DNS 地址格式无效：$ip"
  done
  if have systemctl && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    local dir=/etc/systemd/resolved.conf.d
    mkdir -p "$dir"
    [[ -f $dir/99-sst-dns.conf ]] && backup_config_file "$dir/99-sst-dns.conf" resolved-dns >/dev/null 2>&1 || true
    {
      printf '[Resolve]\n'
      printf 'DNS=%s\n' "${servers[*]}"
      printf 'FallbackDNS=8.8.8.8 1.0.0.1\n'
    } >"$dir/99-sst-dns.conf"
    systemctl restart systemd-resolved || die "systemd-resolved 重启失败"
    have resolvectl && resolvectl flush-caches >/dev/null 2>&1 || true
  else
    backup_config_file /etc/resolv.conf resolv.conf >/dev/null 2>&1 || true
    {
      printf '# managed by stbox\n'
      for ip in "${servers[@]}"; do printf 'nameserver %s\n' "$ip"; done
    } >/etc/resolv.conf
  fi
  wizard_set DNS "${servers[*]}"
  if getent hosts github.com >/dev/null 2>&1; then
    ok "DNS 已设置并解析正常：${servers[*]}"
  else
    warn "DNS 已写入，但解析测试失败，请检查网络或稍后重试"
  fi
}

init_update_check() {
  pkg_update || die "软件源更新失败"
  case ${PKG:-unknown} in
    apt)
      local n
      n=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
      if (( n > 0 )); then
        info "可用更新：$n 个"
        apt list --upgradable 2>/dev/null | head -n 15
      else
        ok "当前没有可用更新"
      fi
      ;;
    dnf|yum)
      "$PKG" check-update -q 2>&1 | head -n 20 || true
      info "dnf/yum check-update 退出码 100 表示有可用更新，0 表示无更新"
      ;;
    apk)
      apk version -l '<' 2>/dev/null | head -n 20 || true
      ;;
    pacman)
      pacman -Qu 2>/dev/null | head -n 20 || info "当前没有可用更新"
      ;;
    zypper)
      zypper -q list-updates 2>/dev/null | head -n 20 || true
      ;;
    *) warn "当前包管理器不支持检查更新" ;;
  esac
}

init_update_install() {
  confirm "安装全部可用更新？可能升级内核或服务，完成后建议重启" || return 0
  pkg_update || die "软件源更新失败"
  pkg_upgrade || die "系统更新失败"
  wizard_set UPDATES installed
  ok "系统更新完成"
  [[ -f /var/run/reboot-required ]] && warn "系统提示需要重启"
}

init_auto_updates() {
  case ${PKG:-unknown} in
    apt)
      pkg_install unattended-upgrades || die "unattended-upgrades 安装失败"
      backup_config_file /etc/apt/apt.conf.d/20auto-upgrades auto-upgrades >/dev/null 2>&1 || true
      cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
      if [[ ${INIT:-sysv} == systemd ]]; then
        systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
      fi
      wizard_set AUTO_UPDATES apt
      ok "已启用 unattended-upgrades（不自动重启）"
      ;;
    dnf|yum)
      pkg_install dnf-automatic || die "dnf-automatic 安装失败"
      local conf=/etc/dnf/automatic.conf
      [[ -f $conf ]] && backup_config_file "$conf" automatic.conf >/dev/null 2>&1 || true
      [[ -f $conf ]] && sed -i 's/^apply_updates.*/apply_updates = yes/' "$conf"
      svc_enable dnf-automatic.timer || warn "dnf-automatic.timer 启动失败"
      wizard_set AUTO_UPDATES dnf
      ok "已启用 dnf-automatic（不自动重启）"
      ;;
    *) die "当前发行版暂不支持一键启用自动安全更新" ;;
  esac
}

init_basics() {
  wizard_init
  require_root
  [[ -t 0 ]] || die "基础信息设置需要在交互终端运行"
  local choice tz name
  section "基础信息设置"

  section "[1/5] 时区"
  kv "当前时区" "$(timedatectl show -p Timezone --value 2>/dev/null || date +%Z)"
  printf '  1) 保持当前时区（推荐）\n  2) Asia/Shanghai\n  3) UTC\n  4) 自定义\n  5) 跳过\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) wizard_set TIMEZONE "$(timedatectl show -p Timezone --value 2>/dev/null || date +%Z)" ;;
    2) init_apply_timezone Asia/Shanghai ;;
    3) init_apply_timezone UTC ;;
    4) tz=$(ask "时区" "Asia/Shanghai"); init_apply_timezone "$tz" ;;
    5) ;;
    0|q|back) return 0 ;;
    *) warn "无效选项" ;;
  esac

  section "[2/5] 主机名"
  kv "当前主机名" "$(hostname)"
  printf '  1) 保持当前主机名（推荐）\n  2) web-01\n  3) db-01\n  4) proxy-01\n  5) 自定义\n  6) 随机 srv-xxxxxx\n  7) 跳过\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) wizard_set HOSTNAME "$(hostname)" ;;
    2) init_apply_hostname web-01 ;;
    3) init_apply_hostname db-01 ;;
    4) init_apply_hostname proxy-01 ;;
    5) name=$(ask "主机名" "$(hostname)"); init_apply_hostname "$name" ;;
    6) name="srv-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"; init_apply_hostname "$name" ;;
    7) ;;
    0|q|back) return 0 ;;
    *) warn "无效选项" ;;
  esac

  section "[3/5] 时间同步"
  kv "当前状态" "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo 未知)"
  printf '  1) 保持当前配置（推荐）\n  2) 启用 systemd-timesyncd\n  3) 安装并启用 chrony\n  4) 跳过\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) ;;
    2) init_enable_timesyncd ;;
    3) init_enable_chrony ;;
    4) ;;
    0|q|back) return 0 ;;
    *) warn "无效选项" ;;
  esac

  section "[4/5] DNS"
  kv "当前 DNS" "$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
  printf '  1) 保持当前 DNS（推荐）\n  2) 223.5.5.5 + 1.1.1.1\n  3) 1.1.1.1 + 8.8.8.8\n  4) 自定义\n  5) 跳过\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) wizard_set DNS "$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)" ;;
    2) init_apply_dns 223.5.5.5 1.1.1.1 ;;
    3) init_apply_dns 1.1.1.1 8.8.8.8 ;;
    4) local dns_input; local -a dns_arr=(); dns_input=$(ask "DNS（空格分隔）" "223.5.5.5 1.1.1.1"); read -r -a dns_arr <<<"$dns_input"; init_apply_dns "${dns_arr[@]}" ;;
    5) ;;
    0|q|back) return 0 ;;
    *) warn "无效选项" ;;
  esac

  section "[5/5] 更新策略"
  printf '  1) 跳过（推荐，稍后单独更新）\n  2) 只检查可用更新\n  3) 安装全部更新（可能较慢）\n  4) 启用自动安全更新（Debian/Ubuntu、RHEL 系）\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) ;;
    2) init_update_check ;;
    3) init_update_install ;;
    4) init_auto_updates ;;
    0|q|back) return 0 ;;
    *) warn "无效选项" ;;
  esac

  wizard_mark basics done
  ok "基础信息步骤完成"
}

init_report() {
  require_root
  local file
  file=$(wizard_report_write)
  wizard_mark report done
  ok "开荒报告已生成：$file"
  info "报告权限 600，包含主机名、IP 和配置摘要，请勿公开分享"
}

init_reset() {
  require_root
  confirm "清除向导进度？不会还原任何系统配置" || return 0
  rm -f "$SST_WIZARD_STATE"
  ok "向导进度已清除，历史报告保留在 $SST_WIZARD_DIR"
}

init_resume() { init_wizard; }

init_wizard() {
  require_root
  [[ -t 0 ]] || die "开荒向导需要在交互终端运行；预检可用 st init preflight"
  wizard_init
  sst_print_banner
  wizard_status_table
  confirm "开始/继续开荒向导？" || return 0

  if [[ $(wizard_step_status preflight) != done ]]; then
    init_preflight_show
    confirm "预检完成，继续磁盘检测？" || { warn "已保存进度，可执行 st init resume 继续"; return 0; }
    wizard_mark preflight done
  fi

  if [[ $(wizard_step_status disk) != done ]]; then
    init_disk
    if [[ $(wizard_step_status disk) != done ]]; then
      warn "磁盘步骤未完成，已保存进度"
      return 0
    fi
  fi

  if [[ $(wizard_step_status basics) != done ]]; then
    init_basics
    if [[ $(wizard_step_status basics) != done ]]; then
      warn "基础信息步骤未完成，已保存进度"
      return 0
    fi
  fi

  init_report
  wizard_status_table
  ok "P1 开荒流程完成：预检、磁盘、基础信息、报告"
  info "账户、SSH 端口、密码登录、防火墙将在下一阶段（P2）加入"
}
