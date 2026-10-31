#!/usr/bin/env bash
# 模块：开荒向导（预检 / 磁盘 / 基础信息 / 账户 / SSH / 防火墙 / 报告）

sst_register_module init "开荒向导" "预检 磁盘 账户 SSH 防火墙"
SST_MODULE_ITEMS[init]=$'wizard|开始/继续开荒\npreflight|服务器预检\ndisk|磁盘检测与挂载\nbasics|基础信息设置\naccounts|账户设置\nssh|SSH 安全\nfirewall|防火墙与防护\nhardening|系统加固\nstatus|查看进度\nreport|生成报告\nreset|重置向导'

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
  local ssh_ports root_login pass_auth bbr tz syncookie
  cpu=$(get_cpu_model)
  [[ -n $cpu ]] || cpu="未知"
  cores=$(nproc 2>/dev/null || echo 未知)
  read -r mem_total mem_used mem_avail <<<"$(get_mem_info)"
  disk=$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s 已用 %s (%s)", $2, $3, $5}')
  if have free; then
    swap_state=$(free -m 2>/dev/null | awk 'NR==3 {if ($2 == 0) print "未启用"; else printf "%d/%d MB (%d%%)", $3, $2, $3 * 100 / $2}')
  else
    swap_state=$(awk '/SwapTotal/ {t=$2} /SwapFree/ {f=$2} END {if (t == 0) print "未启用"; else printf "%d/%d MB", t/1024-f/1024, t/1024}' /proc/meminfo 2>/dev/null)
  fi
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
  syncookie=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || true)
  [[ -n $syncookie && $syncookie != 1 ]] && warn "TCP syncookies 未启用"
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

# ---------- P2：账户 ----------

init_admin_ready() {
  local user home
  user=$(wizard_get ADMIN_USER)
  [[ -n $user ]] || return 1
  getent passwd "$user" >/dev/null 2>&1 || return 1
  home=$(getent passwd "$user" | cut -d: -f6)
  [[ -n $home && -s "$home/.ssh/authorized_keys" ]] || return 1
  sudo -l -U "$user" >/dev/null 2>&1 || return 1
  return 0
}

init_key_ready() {
  local user home
  user=$(wizard_get ADMIN_USER)
  if [[ -n $user ]]; then
    home=$(getent passwd "$user" | cut -d: -f6)
    [[ -n $home && -s "$home/.ssh/authorized_keys" ]] && return 0
  fi
  [[ -s /root/.ssh/authorized_keys ]]
}

init_set_user_password() {
  local user=$1 pass=$2
  if have chpasswd; then
    printf '%s:%s\n' "$user" "$pass" | chpasswd
  elif have passwd; then
    printf '%s\n' "$pass" | passwd --stdin "$user"
  else
    return 1
  fi
}

init_set_root_password() {
  local p1 p2
  read -r -s -p "新的 root 密码: " p1 || return 1
  printf '\n'
  read -r -s -p "再次输入: " p2 || return 1
  printf '\n'
  [[ -n $p1 && $p1 == "$p2" ]] || die "两次密码不一致或为空"
  (( ${#p1} >= 8 )) || die "密码至少需要 8 位"
  [[ $p1 != *:* ]] || die "密码不能包含冒号"
  init_set_user_password root "$p1" || die "root 密码修改失败"
  wizard_set ROOT_PASSWORD changed
  ok "root 密码已修改"
}

init_generate_root_password() {
  local p
  p=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
  [[ -n $p ]] || die "密码生成失败"
  init_set_user_password root "$p" || die "root 密码修改失败"
  wizard_set ROOT_PASSWORD changed
  ok "root 密码已更新：$p"
  warn "请立即保存该密码，之后不再显示"
}

init_create_admin_user() {
  local username=$1 mode=$2 shell home group=''
  [[ $username =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || die "用户名格式无效"
  [[ $username != root ]] || die "不能使用 root 作为管理用户名"

  if ! getent passwd "$username" >/dev/null 2>&1; then
    shell=/bin/sh
    have bash && shell=/bin/bash
    if have useradd; then
      useradd -m -s "$shell" "$username" || die "创建用户失败"
    else
      adduser -D -s "$shell" "$username" || die "创建用户失败"
    fi
  else
    info "用户 $username 已存在，继续配置"
  fi

  if getent group sudo >/dev/null 2>&1; then
    group=sudo
  elif getent group wheel >/dev/null 2>&1; then
    group=wheel
  fi
  if [[ -n $group ]]; then
    if have usermod; then
      usermod -aG "$group" "$username" 2>/dev/null || warn "加入 $group 组失败"
    else
      adduser "$username" "$group" 2>/dev/null || warn "加入 $group 组失败"
    fi
  else
    warn "未找到 sudo/wheel 组，请手动配置 sudo 权限"
  fi

  home=$(getent passwd "$username" | cut -d: -f6)
  [[ -n $home ]] || die "无法读取用户 home 目录"

  case $mode in
    key)
      [[ -s /root/.ssh/authorized_keys ]] || die "root 没有可用密钥，无法复制到管理用户"
      mkdir -p "$home/.ssh"
      cp /root/.ssh/authorized_keys "$home/.ssh/authorized_keys"
      chown -R "$username":"$(id -gn "$username")" "$home/.ssh"
      chmod 700 "$home/.ssh"
      chmod 600 "$home/.ssh/authorized_keys"
      ;;
    password)
      local p1 p2
      read -r -s -p "管理用户密码: " p1 || return 1
      printf '\n'
      read -r -s -p "再次输入: " p2 || return 1
      printf '\n'
      [[ -n $p1 && $p1 == "$p2" ]] || die "两次密码不一致或为空"
      (( ${#p1} >= 8 )) || die "密码至少需要 8 位"
      [[ $p1 != *:* ]] || die "密码不能包含冒号"
      init_set_user_password "$username" "$p1" || die "设置用户密码失败"
      ;;
    *) die "未知认证方式：$mode" ;;
  esac

  getent passwd "$username" >/dev/null 2>&1 || die "用户创建校验失败"
  if [[ $mode == key ]] && [[ ! -s "$home/.ssh/authorized_keys" ]]; then
    die "管理用户密钥写入失败"
  fi
  if have sudo; then
    sudo -l -U "$username" >/dev/null 2>&1 || warn "sudo 权限验证失败，请手动检查"
  fi
  wizard_set ADMIN_USER "$username"
  wizard_set ADMIN_AUTH "$mode"
  ok "管理用户已配置：$username（$mode）"
}

init_accounts() {
  wizard_init
  require_root
  [[ -t 0 ]] || die "账户设置需要在交互终端运行"
  local choice user
  section "账户设置"

  section "[1/2] root 密码"
  printf '  1) 保持当前密码（确认已足够强）\n  2) 自定义新密码\n  3) 生成随机强密码（推荐）\n  4) 跳过\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) wizard_set ROOT_PASSWORD kept ;;
    2) init_set_root_password ;;
    3) init_generate_root_password ;;
    4) ;;
    0|q|back) return 0 ;;
    *) warn "无效选项" ;;
  esac

  section "[2/2] 管理用户"
  printf '  1) 不创建，仅使用 root（简单场景）\n  2) 创建管理用户并复制 root 密钥（推荐）\n  3) 创建管理用户并设置密码\n  4) 使用已有用户\n  5) 跳过\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1|5) ;;
    2)
      user=$(ask "管理用户名" "admin")
      init_create_admin_user "$user" key
      ;;
    3)
      user=$(ask "管理用户名" "admin")
      init_create_admin_user "$user" password
      ;;
    4)
      user=$(ask "已有用户名" "feng")
      getent passwd "$user" >/dev/null 2>&1 || die "用户不存在：$user"
      wizard_set ADMIN_USER "$user"
      wizard_set ADMIN_AUTH existing
      if have sudo; then
        sudo -l -U "$user" >/dev/null 2>&1 || warn "该用户 sudo 验证失败"
      fi
      ok "已记录管理用户：$user"
      ;;
    0|q|back) return 0 ;;
    *) warn "无效选项" ;;
  esac

  wizard_mark accounts done
  ok "账户设置步骤完成"
}

# ---------- P2：SSH ----------

init_ssh_snapshot() {
  local ts file
  local -a paths=(etc/ssh/sshd_config)
  [[ -d /etc/ssh/sshd_config.d ]] && paths+=(etc/ssh/sshd_config.d)
  ts=$(date +%Y%m%d-%H%M%S)
  file="$SST_WIZARD_DIR/ssh-backup-$ts.tar.gz"
  tar -czf "$file" -C / "${paths[@]}" || return 1
  chmod 600 "$file"
  wizard_set SSH_BACKUP "$file"
  printf '%s\n' "$file"
}

init_ssh_restore_config() {
  local backup service
  backup=$(wizard_get SSH_BACKUP)
  [[ -f $backup ]] || { err "SSH 备份不存在，无法回滚"; return 1; }
  rm -f /etc/ssh/sshd_config.d/00-stbox-port.conf /etc/ssh/sshd_config.d/00-stbox-auth.conf 2>/dev/null || true
  tar -xzf "$backup" -C / || { err "SSH 配置恢复失败"; return 1; }
  service=$(ssh_service_name)
  svc_restart "$service" || { err "SSH 服务重启失败"; return 1; }
  ok "SSH 配置已恢复"
}

init_ssh_dropin_set() {
  local file=$1 key=$2 value=$3 tmp
  mkdir -p /etc/ssh/sshd_config.d
  touch "$file"
  tmp=$(mktemp)
  awk -v k="$key" -v v="$value" '
    BEGIN { IGNORECASE = 1; done = 0 }
    {
      if (tolower($1) == tolower(k)) {
        if (!done) { print k " " v; done = 1 } else { print "#" $0 }
      } else {
        print $0
      }
    }
    END { if (!done) print k " " v }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
  chmod 644 "$file"
}

init_ssh_apply_port() {
  local new=$1 old_ports p f
  old_ports=$(ssh_all_ports | tr ',' ' ')
  if grep -qE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' /etc/ssh/sshd_config 2>/dev/null; then
    f=/etc/ssh/sshd_config.d/00-stbox-port.conf
    {
      printf '# managed by stbox\n'
      for p in $old_ports $new; do printf 'Port %s\n' "$p"; done
    } >"$f"
    chmod 644 "$f"
  else
    for p in $old_ports $new; do
      ssh_add_port "$p" >/dev/null || return 1
    done
  fi
}

init_ssh_apply_auth() {
  local pass=$1 root=$2
  [[ -n $pass || -n $root ]] || return 0
  if grep -qE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' /etc/ssh/sshd_config 2>/dev/null; then
    local f=/etc/ssh/sshd_config.d/00-stbox-auth.conf
    [[ -n $pass ]] && init_ssh_dropin_set "$f" PasswordAuthentication "$pass"
    [[ -n $root ]] && init_ssh_dropin_set "$f" PermitRootLogin "$root"
  else
    [[ -n $pass ]] && ssh_set_option PasswordAuthentication "$pass"
    [[ -n $root ]] && ssh_set_option PermitRootLogin "$root"
  fi
}

init_ssh_verify() {
  local new=$1 pass=$2 root=$3 ports p actual
  sshd -t || return 1
  if [[ -n $new ]]; then
    ports=$(ssh_all_ports | tr ',' ' ')
    for p in $ports; do [[ $p == "$new" ]] && break; done
    [[ $p == "$new" ]] || return 1
  fi
  if [[ -n $pass ]]; then
    actual=$(ssh_cfg_get PasswordAuthentication)
    [[ $actual == "$pass" ]] || return 1
  fi
  if [[ -n $root ]]; then
    actual=$(ssh_cfg_get PermitRootLogin)
    [[ $actual == "$root" || ($root == prohibit-password && $actual == without-password) ]] || return 1
  fi
  return 0
}

init_allow_ssh_port_now() {
  local port=$1 fw
  fw=$(_fw_installed)
  case $fw in
    ufw)
      if ufw status 2>/dev/null | grep -qi active; then
        ufw allow "$port/tcp" >/dev/null 2>&1 || warn "UFW 放行新 SSH 端口失败"
      fi
      ;;
    firewalld)
      if svc_active firewalld; then
        firewall-cmd --permanent --add-port="$port/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

init_ssh_cancel_timer() {
  local unit
  unit=$(wizard_get SSH_TIMER_UNIT)
  [[ -n $unit ]] || unit=stbox-ssh-rollback
  if have systemctl; then
    systemctl stop "$unit.timer" "$unit.service" >/dev/null 2>&1 || true
    systemctl reset-failed "$unit.timer" "$unit.service" >/dev/null 2>&1 || true
  fi
  wizard_set SSH_TIMER_UNIT ''
}

init_ssh_arm_timer() {
  local minutes=$1 unit=stbox-ssh-rollback
  (( minutes > 0 )) || return 0
  if [[ ${INIT:-sysv} != systemd ]] || ! have systemd-run; then
    warn "当前环境不支持 systemd 定时回滚，请手动验证并保留配置"
    return 0
  fi
  init_ssh_cancel_timer
  wizard_set SSH_KEEP 0
  wizard_set SSH_SERVICE "$(ssh_service_name)"
  wizard_set ROLLBACK_LOG "$SST_WIZARD_DIR/ssh-rollback.log"
  if systemd-run --collect --unit="$unit" --on-active="${minutes}m" \
    --timer-property=AccuracySec=1s /bin/bash "$SST_HOME/core/ssh-rollback.sh" "$SST_WIZARD_STATE"; then
    wizard_set SSH_TIMER_UNIT "$unit"
    wizard_set SSH_TIMER_MIN "$minutes"
    ok "已启用 ${minutes} 分钟自动回滚；确认可登录后执行 st init ssh keep"
  else
    warn "自动回滚定时器创建失败，请手动验证 SSH"
  fi
}

init_ssh_apply_changes() {
  require_root
  local new=$1 pass=$2 root=$3 minutes=$4 service
  [[ -n $new || -n $pass || -n $root ]] || return 0
  init_ssh_snapshot >/dev/null || die "备份 SSH 配置失败"
  wizard_set SSH_NEW_PORT "$new"
  wizard_set SSH_PASS_AUTH "$pass"
  wizard_set SSH_ROOT_LOGIN "$root"
  wizard_set SSH_STATUS applying
  service=$(ssh_service_name)
  wizard_set SSH_SERVICE "$service"

  if ! (
    [[ -n $new ]] && init_ssh_apply_port "$new"
    init_ssh_apply_auth "$pass" "$root"
    init_ssh_verify "$new" "$pass" "$root"
  ); then
    init_ssh_restore_config || true
    die "SSH 配置校验失败，已回滚"
  fi

  [[ -n $new ]] && init_allow_ssh_port_now "$new"
  init_ssh_arm_timer "$minutes"

  if ! svc_restart "$service"; then
    init_ssh_cancel_timer
    init_ssh_restore_config || true
    die "SSH 服务重启失败，已回滚"
  fi
  sleep 1
  if [[ -n $new ]] && ! ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":$new$"; then
    init_ssh_cancel_timer
    init_ssh_restore_config || true
    die "新端口 $new 未监听，已回滚"
  fi
  wizard_set SSH_STATUS applied
  ok "SSH 配置已应用"
}

init_ssh_keep() {
  require_root
  wizard_init
  if [[ $(wizard_get SSH_ROLLBACK) == done ]]; then
    die "SSH 配置已自动回滚，不能确认保留；请重新执行 st init ssh"
  fi
  init_ssh_cancel_timer
  wizard_set SSH_KEEP 1
  wizard_set SSH_STATUS kept
  wizard_mark ssh done
  ok "已确认保留 SSH 配置，自动回滚已取消"
  if [[ -f $SST_WIZARD_DIR/ssh-rollback.log ]]; then
    info "回滚日志：$SST_WIZARD_DIR/ssh-rollback.log"
  fi
}

init_ssh_rollback() {
  require_root
  wizard_init
  init_ssh_cancel_timer
  wizard_set SSH_KEEP 0
  bash "$SST_HOME/core/ssh-rollback.sh" "$SST_WIZARD_STATE" || die "SSH 回滚失败"
  wizard_set SSH_STATUS rolledback
  wizard_mark ssh skipped
  ok "SSH 配置已回滚"
}

init_ssh() {
  local action=${1:-}
  case $action in
    keep) init_ssh_keep; return 0 ;;
    rollback) init_ssh_rollback; return 0 ;;
    status)
      section "SSH 向导状态"
      kv "状态" "$(wizard_get SSH_STATUS 未执行)"
      kv "新端口" "$(wizard_get SSH_NEW_PORT 未设置)"
      kv "自动回滚" "$([[ -n $(wizard_get SSH_TIMER_MIN) ]] && echo "$(wizard_get SSH_TIMER_MIN) 分钟" || echo 未启用)"
      kv "回滚结果" "$(wizard_get SSH_ROLLBACK 未执行)"
      return 0
      ;;
  esac

  wizard_init
  require_root
  [[ -t 0 ]] || die "SSH 设置需要在交互终端运行"
  local old_ports new_port='' pass='' root='' minutes=10 choice login_user current_root
  old_ports=$(ssh_all_ports)
  current_root=$(ssh_cfg_get PermitRootLogin)
  section "SSH 安全设置"
  kv "当前端口" "$old_ports"
  kv "密码登录" "$(ssh_cfg_get PasswordAuthentication)"
  kv "root 登录" "$current_root"
  kv "管理用户" "$(wizard_get ADMIN_USER 未创建)"

  section "[1/4] SSH 端口"
  printf '  1) 新增随机高位端口，保留旧端口（推荐）\n  2) 新增 2222，保留旧端口\n  3) 自定义新端口，保留旧端口\n  4) 保持当前端口\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1)
      local i
      for i in 1 2 3 4 5; do
        new_port=$(shuf -i 20000-65000 -n 1 2>/dev/null || echo $((20000 + RANDOM % 45000)))
        ssh_all_ports | tr ',' '\n' | grep -qx "$new_port" && continue
        ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":$new_port$" || break
      done
      ;;
    2) new_port=2222 ;;
    3) new_port=$(ask "新 SSH 端口" "2222") ;;
    4) new_port='' ;;
    0|q|back) return 0 ;;
    *) warn "无效选项"; return 0 ;;
  esac
  if [[ -n $new_port ]]; then
    valid_port "$new_port" || die "端口无效：$new_port"
    ssh_all_ports | tr ',' '\n' | grep -qx "$new_port" && die "端口 $new_port 已存在"
    if ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":$new_port$"; then
      die "端口 $new_port 已被其他服务占用"
    fi
  fi

  section "[2/4] 密码登录"
  printf '  1) 禁用密码登录，仅允许密钥（有密钥时推荐）\n  2) 保持当前设置\n  3) 开启密码登录\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1)
      init_key_ready || die "未发现可用 authorized_keys，不能禁用密码登录"
      pass=no
      ;;
    2) pass='' ;;
    3) pass=yes ;;
    0|q|back) return 0 ;;
    *) warn "无效选项"; return 0 ;;
  esac

  section "[3/4] root 登录"
  if init_admin_ready; then
    info "管理用户已通过密钥/sudo 验证，推荐选择 2) 完全禁止 root SSH"
  else
    info "未验证管理用户，推荐选择 1) prohibit-password"
  fi
  printf '  1) prohibit-password，root 仅允许密钥（推荐）\n  2) no，完全禁止 root SSH（需管理用户可用）\n  3) 保持当前设置\n  4) yes，允许 root 密码登录（高风险）\n  0) 保存退出\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) root=prohibit-password ;;
    2)
      init_admin_ready || die "管理用户未通过密钥/sudo 验证，不能禁止 root SSH"
      root=no
      ;;
    3) root='' ;;
    4) root=yes; warn "允许 root 密码登录会降低安全性" ;;
    0|q|back) return 0 ;;
    *) warn "无效选项"; return 0 ;;
  esac

  if [[ ${INIT:-sysv} == systemd ]] && have systemd-run; then
    section "[4/4] 自动回滚"
    printf '  1) 10 分钟（推荐）\n  2) 5 分钟\n  3) 20 分钟\n  4) 不启用自动回滚\n  0) 保存退出\n'
    read -r -p "请选择: " choice || return 0
    case $choice in
      1) minutes=10 ;;
      2) minutes=5 ;;
      3) minutes=20 ;;
      4) minutes=0 ;;
      0|q|back) return 0 ;;
      *) minutes=10 ;;
    esac
  else
    minutes=0
    warn "当前环境不支持自动回滚定时器，请手动验证 SSH"
  fi

  section "即将应用"
  kv "SSH 端口" "${new_port:-保持 $old_ports}"
  kv "密码登录" "${pass:-保持}"
  kv "root 登录" "${root:-保持}"
  kv "自动回滚" "$([[ $minutes -gt 0 ]] && echo "${minutes} 分钟" || echo 未启用)"
  confirm "应用以上 SSH 设置？请保持当前会话不要关闭" || return 0

  if [[ -z $new_port && -z $pass && -z $root ]]; then
    wizard_mark ssh done
    info "SSH 设置未变化"
    return 0
  fi

  init_ssh_apply_changes "$new_port" "$pass" "$root" "$minutes"

  login_user=$(wizard_get ADMIN_USER)
  [[ -n $login_user ]] || login_user=root
  local port_show=${new_port:-$old_ports}
  info "请在新终端验证：ssh -p ${port_show} ${login_user}@$(get_public_ip)"
  printf '\n  1) 已验证，保留配置（推荐）\n  2) 未验证，立即回滚\n  3) 保留定时器，稍后执行 st init ssh keep\n  0) 保持当前选择并返回\n\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) init_ssh_keep ;;
    2) init_ssh_rollback ;;
    3)
      wizard_set SSH_KEEP 0
      if [[ $minutes -eq 0 ]]; then
        warn "未启用自动回滚，请尽快执行 st init ssh keep 或 rollback"
      fi
      ;;
    0|q|back) ;;
    *) warn "无效选项" ;;
  esac
}

init_firewall_apply_ufw() {
  local -a extra=("$@")
  local ports p
  require_root
  if ! have ufw; then
    pkg_update || die "软件源更新失败"
    pkg_install ufw || die "ufw 安装失败"
  fi
  if [[ -f /etc/default/ufw ]]; then
    backup_config_file /etc/default/ufw ufw-defaults >/dev/null 2>&1 || true
    if grep -q '^IPV6=' /etc/default/ufw; then
      sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
    else
      printf 'IPV6=yes\n' >>/etc/default/ufw
    fi
  fi
  ports=$(ssh_all_ports | tr ',' ' ')
  for p in $ports; do
    valid_port "$p" && ufw allow "$p/tcp" >/dev/null || warn "放行 SSH 端口 $p 失败"
  done
  for p in "${extra[@]}"; do
    [[ -n $p ]] || continue
    valid_port "$p" && ufw allow "$p/tcp" >/dev/null || warn "放行端口 $p 失败"
  done
  ufw --force enable || die "UFW 启用失败"
  ufw status verbose || true
  wizard_set FIREWALL "ufw"
  wizard_set FIREWALL_PORTS "$ports ${extra[*]}"
  ok "UFW 已启用，SSH 端口：$ports"
}

init_firewall_apply_firewalld() {
  local -a extra=("$@")
  local ports p
  require_root
  if ! have firewall-cmd; then
    pkg_update || die "软件源更新失败"
    pkg_install firewalld || die "firewalld 安装失败"
  fi
  svc_enable firewalld || die "firewalld 启动失败"
  firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
  ports=$(ssh_all_ports | tr ',' ' ')
  for p in $ports "${extra[@]}"; do
    [[ -n $p ]] || continue
    valid_port "$p" && firewall-cmd --permanent --add-port="$p/tcp" >/dev/null 2>&1 || true
  done
  firewall-cmd --reload >/dev/null || die "firewalld 重载失败"
  firewall-cmd --list-all 2>/dev/null || true
  wizard_set FIREWALL "firewalld"
  wizard_set FIREWALL_PORTS "$ports ${extra[*]}"
  ok "firewalld 已启用，SSH 端口：$ports"
}

init_firewall() {
  wizard_init
  require_root
  [[ -t 0 ]] || die "防火墙设置需要在交互终端运行"
  local fw state choice ports_input p
  local -a extra=()
  fw=$(_fw_installed)
  state=$(_ufw_state)
  section "防火墙与防护"
  kv "当前防火墙" "$fw / $state"
  kv "SSH 端口" "$(ssh_all_ports)"
  kv "Docker" "$(have docker && echo 已安装 || echo 未安装)"
  [[ $(have docker && echo yes) == yes ]] && warn "UFW 不能完全保护 Docker 发布的端口"

  printf '\n  1) 跳过，不修改防火墙\n  2) UFW：默认拒绝入站，只放行 SSH（推荐）\n  3) UFW：默认拒绝入站，放行 SSH + 80/443\n  4) UFW：默认拒绝入站，放行 SSH + 自定义端口\n  5) firewalld：放行 SSH + 自定义端口\n  6) 关闭现有防火墙（不推荐）\n  0) 保存退出\n\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) wizard_set FIREWALL skipped ;;
    2) init_firewall_apply_ufw ;;
    3) init_firewall_apply_ufw 80 443 ;;
    4)
      ports_input=$(ask "额外放行端口（空格/逗号分隔）" "80 443")
      ports_input=${ports_input//,/ }
      for p in $ports_input; do
        valid_port "$p" || die "端口无效：$p"
        extra+=("$p")
      done
      init_firewall_apply_ufw "${extra[@]}"
      ;;
    5)
      ports_input=$(ask "额外放行端口（空格/逗号分隔）" "80 443")
      ports_input=${ports_input//,/ }
      for p in $ports_input; do
        valid_port "$p" || die "端口无效：$p"
        extra+=("$p")
      done
      init_firewall_apply_firewalld "${extra[@]}"
      ;;
    6)
      confirm "关闭防火墙会使端口直接暴露，确认关闭？" || return 0
      if [[ $fw == ufw ]]; then
        ufw --force disable || die "UFW 关闭失败"
        wizard_set FIREWALL disabled
      elif [[ $fw == firewalld ]]; then
        systemctl disable --now firewalld >/dev/null 2>&1 || true
        wizard_set FIREWALL disabled
      else
        warn "没有可关闭的 ufw/firewalld"
      fi
      ;;
    0|q|back) return 0 ;;
    *) warn "无效选项"; return 0 ;;
  esac

  section "Fail2ban"
  printf '  1) 安装并启用 sshd 防护（推荐）\n  2) 跳过\n  3) 查看状态\n  0) 跳过\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1)
      if security_fail2ban_install --yes; then
        wizard_set FAIL2BAN installed
      else
        warn "Fail2ban 安装未完成"
      fi
      ;;
    2|0|q|back) ;;
    3) security_fail2ban_status ;;
    *) warn "无效选项" ;;
  esac

  wizard_mark firewall done
  ok "防火墙与防护步骤完成"
}

# ---------- P3：系统加固 ----------

init_openrc_sysctl_loader() {
  [[ ${INIT:-} == systemd ]] && return 0
  mkdir -p /etc/local.d
  cat >/etc/local.d/99-stbox-sysctl.start <<'EOF'
#!/bin/sh
for f in /etc/sysctl.d/99-stbox-security.conf /etc/sysctl.d/99-stbox-swap.conf /etc/sysctl.d/99-sst-bbr.conf; do
  [ -f "$f" ] && sysctl -p "$f" >/dev/null 2>&1
done
EOF
  chmod +x /etc/local.d/99-stbox-sysctl.start
  if have rc-update; then
    rc-update add local default >/dev/null 2>&1 || true
  fi
}

init_security_sysctl_apply() {
  local strict=${1:-}
  local file=/etc/sysctl.d/99-stbox-security.conf backup=''
  local check key expected actual
  require_root
  if [[ -f $file ]]; then
    backup=$(mktemp)
    cp "$file" "$backup"
    backup_config_file "$file" stbox-security >/dev/null 2>&1 || true
  fi

  {
    printf '# managed by stbox\n'
    printf 'net.ipv4.tcp_syncookies = 1\n'
    printf 'net.ipv4.conf.all.accept_redirects = 0\n'
    printf 'net.ipv4.conf.default.accept_redirects = 0\n'
    printf 'net.ipv4.conf.all.send_redirects = 0\n'
    printf 'net.ipv4.conf.default.send_redirects = 0\n'
    printf 'net.ipv4.conf.all.accept_source_route = 0\n'
    printf 'net.ipv4.conf.default.accept_source_route = 0\n'
    printf 'net.ipv4.icmp_echo_ignore_broadcasts = 1\n'
    printf 'net.ipv4.icmp_ignore_bogus_error_responses = 1\n'
    printf 'net.ipv4.conf.all.log_martians = 1\n'
    printf 'net.ipv6.conf.all.accept_redirects = 0\n'
    printf 'net.ipv6.conf.all.accept_source_route = 0\n'
    printf 'fs.protected_hardlinks = 1\n'
    printf 'fs.protected_symlinks = 1\n'
    [[ -n $strict ]] && printf 'net.ipv4.conf.all.rp_filter = 1\nnet.ipv4.conf.default.rp_filter = 1\n'
  } >"$file"

  if ! sysctl -p "$file" >/dev/null 2>&1 && ! sysctl -e -p "$file" >/dev/null 2>&1; then
    if [[ -n $backup ]]; then cp "$backup" "$file"; else rm -f "$file"; fi
    sysctl --system >/dev/null 2>&1 || true
    rm -f "$backup"
    die "安全 sysctl 应用失败，已还原配置"
  fi

  local -a checks=(
    "net.ipv4.tcp_syncookies=1"
    "net.ipv4.conf.all.accept_redirects=0"
    "net.ipv4.conf.all.send_redirects=0"
    "net.ipv4.conf.all.accept_source_route=0"
    "net.ipv4.icmp_echo_ignore_broadcasts=1"
    "net.ipv4.icmp_ignore_bogus_error_responses=1"
    "fs.protected_hardlinks=1"
    "fs.protected_symlinks=1"
  )
  [[ -n $strict ]] && checks+=("net.ipv4.conf.all.rp_filter=1" "net.ipv4.conf.default.rp_filter=1")

  for check in "${checks[@]}"; do
    key=${check%=*}
    expected=${check#*=}
    actual=$(sysctl -n "$key" 2>/dev/null || true)
    [[ -z $actual ]] && continue
    if [[ $actual != "$expected" ]]; then
      if [[ -n $backup ]]; then cp "$backup" "$file"; else rm -f "$file"; fi
      sysctl --system >/dev/null 2>&1 || true
      rm -f "$backup"
      die "安全参数校验失败：$key=$actual，已还原"
    fi
  done
  rm -f "$backup"
  init_openrc_sysctl_loader
  wizard_set SECURITY_SYSCTL "$([[ -n $strict ]] && echo strict || echo safe)"
  ok "安全 sysctl 已应用：$file"
  [[ -n $strict ]] && warn "rp_filter 可能影响 VPN、多网卡或非对称路由，如有异常请移除"
}

init_security_sysctl_remove() {
  require_root
  rm -f /etc/sysctl.d/99-stbox-security.conf
  if [[ ! -f /etc/sysctl.d/99-stbox-swap.conf && ! -f /etc/sysctl.d/99-sst-bbr.conf ]]; then
    rm -f /etc/local.d/99-stbox-sysctl.start
  fi
  sysctl --system >/dev/null 2>&1 || true
  wizard_set SECURITY_SYSCTL removed
  warn "配置已移除；已运行的参数可能保持到重启"
  ok "安全 sysctl 配置已移除"
}

init_hardening_sysctl() {
  local choice
  section "安全 sysctl"
  kv "配置文件" "$([[ -f /etc/sysctl.d/99-stbox-security.conf ]] && echo 已应用 || echo 未应用)"
  kv "syncookies" "$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo 未知)"
  kv "rp_filter" "$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo 未知)"
  printf '\n  1) 跳过，保持当前配置（推荐）\n  2) 应用安全配置（推荐）\n  3) 安全配置 + 严格 rp_filter（可能影响 VPN/多网卡）\n  4) 移除本工具的安全配置\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) wizard_set SECURITY_SYSCTL kept ;;
    2) init_security_sysctl_apply ;;
    3) init_security_sysctl_apply strict ;;
    4) init_security_sysctl_remove ;;
    *) warn "无效选项" ;;
  esac
}

init_swap_create_mb() {
  local mb=$1 swappiness=10 rootfs avail
  require_root
  rootfs=$(findmnt -n -o FSTYPE / 2>/dev/null || stat -f -c %T / 2>/dev/null)
  case $rootfs in
    btrfs|zfs)
      die "根分区为 $rootfs，请使用系统专用方式创建 SWAP，本向导不自动处理" ;;
  esac
  [[ $mb =~ ^[0-9]+$ ]] && (( mb >= 128 && mb <= 16384 )) || die "SWAP 大小需在 128M - 16G"
  if [[ -e $TUNE_SWAP_FILE ]] || grep -q "$TUNE_SWAP_FILE" /proc/swaps 2>/dev/null; then
    die "$TUNE_SWAP_FILE 已存在或已启用"
  fi
  if swapon --show --noheadings 2>/dev/null | grep -q .; then
    warn "系统已有 SWAP，本次将新增一个 $TUNE_SWAP_FILE"
  fi
  avail=$(df -Pm / | awk 'NR==2 {print $4}')
  if [[ $avail =~ ^[0-9]+$ ]] && (( avail < mb * 2 )); then
    confirm "根分区可用 ${avail} MB，创建 ${mb} MB SWAP 后空间紧张，继续？" || return 0
  else
    confirm "创建 ${mb} MB SWAP 并写入 /etc/fstab？" || return 0
  fi

  if ! fallocate -l "${mb}M" "$TUNE_SWAP_FILE" 2>/dev/null; then
    dd if=/dev/zero of="$TUNE_SWAP_FILE" bs=1M count="$mb" status=none || die "创建 SWAP 文件失败"
  fi
  chmod 600 "$TUNE_SWAP_FILE"
  mkswap "$TUNE_SWAP_FILE" >/dev/null || { rm -f "$TUNE_SWAP_FILE"; die "mkswap 失败"; }
  if ! swapon "$TUNE_SWAP_FILE"; then
    rm -f "$TUNE_SWAP_FILE"
    die "swapon 失败"
  fi

  backup_config_file /etc/fstab fstab >/dev/null 2>&1 || true
  if ! awk -v f="$TUNE_SWAP_FILE" '$1 == f {found=1} END {exit !found}' /etc/fstab; then
    printf '%s none swap sw 0 0\n' "$TUNE_SWAP_FILE" >>/etc/fstab
  fi
  {
    printf '# managed by stbox\n'
    printf 'vm.swappiness = %s\n' "$swappiness"
  } >/etc/sysctl.d/99-stbox-swap.conf
  sysctl -p /etc/sysctl.d/99-stbox-swap.conf >/dev/null 2>&1 || warn "swappiness 应用失败"
  init_openrc_sysctl_loader
  wizard_set SWAP "file:${mb}MB"
  ok "SWAP 已创建：${mb}MB（swappiness=$swappiness）"
}

init_swap_remove_hardening() {
  require_root
  if [[ ! -e $TUNE_SWAP_FILE ]] && ! grep -q "$TUNE_SWAP_FILE" /proc/swaps 2>/dev/null; then
    info "未发现本工具创建的 $TUNE_SWAP_FILE"
    return 0
  fi
  confirm "关闭并删除 $TUNE_SWAP_FILE，同时清理 fstab 与 swappiness 配置？" || return 0
  swapoff "$TUNE_SWAP_FILE" >/dev/null 2>&1 || die "swapoff 失败"
  backup_config_file /etc/fstab fstab >/dev/null 2>&1 || true
  local tmp
  tmp=$(mktemp)
  awk -v f="$TUNE_SWAP_FILE" '$1 != f' /etc/fstab >"$tmp" && cat "$tmp" >/etc/fstab
  rm -f "$tmp"
  rm -f "$TUNE_SWAP_FILE" /etc/sysctl.d/99-stbox-swap.conf
  if [[ ! -f /etc/sysctl.d/99-stbox-security.conf && ! -f /etc/sysctl.d/99-sst-bbr.conf ]]; then
    rm -f /etc/local.d/99-stbox-sysctl.start
  fi
  sysctl --system >/dev/null 2>&1 || true
  wizard_set SWAP removed
  ok "SWAP 文件已移除"
}

init_hardening_swap() {
  local choice mem_mb mb size
  section "SWAP"
  tune_swap_status
  mem_mb=$(get_mem_info | awk '{print $1}')
  if [[ $mem_mb =~ ^[0-9]+$ ]]; then
    if (( mem_mb <= 4096 )); then
      info "内存 ${mem_mb} MB，推荐 SWAP 2G"
    else
      info "内存 ${mem_mb} MB，推荐 SWAP 4G"
    fi
  fi
  printf '\n  1) 跳过，保持当前 SWAP（推荐）\n  2) 按内存推荐创建/新增\n  3) 1G\n  4) 2G\n  5) 4G\n  6) 自定义\n  7) 移除本工具创建的 SWAP\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) wizard_set SWAP kept ;;
    2)
      if [[ $mem_mb =~ ^[0-9]+$ ]] && (( mem_mb <= 4096 )); then mb=2048; else mb=4096; fi
      init_swap_create_mb "$mb"
      ;;
    3) init_swap_create_mb 1024 ;;
    4) init_swap_create_mb 2048 ;;
    5) init_swap_create_mb 4096 ;;
    6)
      size=$(ask "SWAP 大小（如 512M、1G）" "1G")
      [[ $size =~ ^([0-9]+)([GgMm])$ ]] || die "大小格式错误"
      mb=${BASH_REMATCH[1]}
      [[ ${BASH_REMATCH[2]} == G || ${BASH_REMATCH[2]} == g ]] && mb=$((mb * 1024))
      init_swap_create_mb "$mb"
      ;;
    7) init_swap_remove_hardening ;;
    *) warn "无效选项" ;;
  esac
}

init_bbr_enable() {
  local file=/etc/sysctl.d/99-sst-bbr.conf backup=''
  require_root
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) == bbr ]]; then
    wizard_set BBR bbr
    info "BBR 已启用"
    return 0
  fi
  if ! bbr_available; then
    warn "当前内核不支持 BBR，请先升级内核"
    wizard_set BBR unsupported
    return 0
  fi
  confirm "启用 BBR（fq 队列 + bbr 拥塞控制）？" || return 0
  if [[ -f $file ]]; then
    backup=$(mktemp)
    cp "$file" "$backup"
    backup_config_file "$file" bbr >/dev/null 2>&1 || true
  fi
  {
    printf '# managed by stbox\n'
    printf 'net.core.default_qdisc = fq\n'
    printf 'net.ipv4.tcp_congestion_control = bbr\n'
  } >"$file"
  if ! sysctl -p "$file" >/dev/null 2>&1; then
    if [[ -n $backup ]]; then cp "$backup" "$file"; else rm -f "$file"; fi
    rm -f "$backup"
    die "BBR 配置应用失败，已还原"
  fi
  rm -f "$backup"
  init_openrc_sysctl_loader
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) == bbr ]]; then
    wizard_set BBR bbr
    ok "BBR 已启用"
  else
    warn "配置已写入，当前算法未切换，重启后可能生效"
  fi
}

init_bbr_disable() {
  require_root
  confirm "关闭 BBR 并恢复 cubic/fq_codel？" || return 0
  rm -f /etc/sysctl.d/99-sst-bbr.conf
  sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
  sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || true
  if [[ ! -f /etc/sysctl.d/99-stbox-security.conf && ! -f /etc/sysctl.d/99-stbox-swap.conf ]]; then
    rm -f /etc/local.d/99-stbox-sysctl.start
  fi
  wizard_set BBR cubic
  ok "BBR 已关闭"
}

init_hardening_bbr() {
  local choice
  section "BBR"
  kv "当前算法" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)"
  kv "内核支持" "$(bbr_available && echo 是 || echo 否)"
  printf '\n  1) 跳过，保持当前设置（推荐）\n  2) 启用 BBR\n  3) 关闭 BBR，恢复 cubic\n'
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) wizard_set BBR kept ;;
    2) init_bbr_enable ;;
    3) init_bbr_disable ;;
    *) warn "无效选项" ;;
  esac
}

init_hardening() {
  wizard_init
  require_root
  [[ -t 0 ]] || die "系统加固需要在交互终端运行"
  section "系统加固与可选优化"
  kv "根分区" "$(findmnt -n -o FSTYPE / 2>/dev/null || stat -f -c %T / 2>/dev/null || echo 未知)"
  kv "SWAP" "$(swapon --show --noheadings 2>/dev/null | awk '{printf "%s(%s) ", $1, $3}' | sed 's/^/ /' || echo 未启用)"
  kv "TCP 算法" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)"
  init_hardening_sysctl
  init_hardening_swap
  init_hardening_bbr
  wizard_mark hardening done
  ok "系统加固步骤完成"
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

  if [[ $(wizard_step_status accounts) != done ]]; then
    init_accounts
    if [[ $(wizard_step_status accounts) != done ]]; then
      warn "账户步骤未完成，已保存进度"
      return 0
    fi
  fi

  if [[ $(wizard_step_status ssh) != done ]]; then
    if [[ $(wizard_get SSH_STATUS) == applied ]]; then
      warn "SSH 配置正在等待验证：新开终端测试后执行 st init ssh keep 或 rollback"
      return 0
    fi
    init_ssh
    if [[ $(wizard_step_status ssh) != done ]]; then
      warn "SSH 步骤未完成，已保存进度"
      return 0
    fi
  fi

  if [[ $(wizard_step_status firewall) != done ]]; then
    init_firewall
    if [[ $(wizard_step_status firewall) != done ]]; then
      warn "防火墙步骤未完成，已保存进度"
      return 0
    fi
  fi

  if [[ $(wizard_step_status hardening) != done ]]; then
    init_hardening
    if [[ $(wizard_step_status hardening) != done ]]; then
      warn "系统加固步骤未完成，已保存进度"
      return 0
    fi
  fi

  init_report
  wizard_status_table
  ok "开荒流程完成：预检、磁盘、基础信息、账户、SSH、防火墙、系统加固、报告"
}
