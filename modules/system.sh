#!/usr/bin/env bash
# 模块：系统信息与基础维护

sst_register_module system "系统维护" "信息 更新 清理 DNS 定时"
SST_MODULE_ITEMS[system]=$'info|系统概览\nenv|系统环境\nload|资源负载\ndisk|磁盘占用\nclean|清理系统垃圾\nupdate|系统更新\nclean_deep|深度清理\ndns|DNS 设置\ntimezone|时区设置\nhostname|主机名\nrootpass|修改 root 密码\nportscan|端口扫描\ncron|定时任务\nshortcut|快捷命令'

system_info() {
  local cpu cores mem_total mem_used mem_avail mem_pct load disk rx tx ip
  cpu=$(get_cpu_model)
  [[ -n $cpu ]] || cpu="未知"
  cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 未知)
  read -r mem_total mem_used mem_avail <<<"$(get_mem_info)"
  mem_pct="未知"
  if [[ $mem_total =~ ^[0-9]+$ ]] && (( mem_total > 0 )); then
    mem_pct=$(( mem_used * 100 / mem_total ))
  fi
  load=$(get_load)
  disk=$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s 已用 %s (%s)", $2, $3, $5}')
  read -r rx tx <<<"$(get_rx_tx)"
  ip=$(get_public_ip)

  section "系统概览"
  kv "主机名" "$(hostname)"
  kv "系统" "$OS_NAME"
  kv "内核" "$(uname -r)"
  kv "架构" "$ARCH"
  kv "虚拟化" "$VIRT"
  kv "运行时长" "$(get_uptime_human)"
  hr
  kv "CPU" "$cpu（${cores} 核）"
  kv "CPU 使用率" "$(top -bn1 2>/dev/null | awk '/Cpu\(s\)/ {printf "%.2f%%", $2 + $4}' || echo "未知")"
  kv "负载" "$load"
  kv "内存" "${mem_used}/${mem_total} MB（${mem_pct}%，可用 ${mem_avail} MB）"
  kv "SWAP" "$(free -m 2>/dev/null | awk 'NR==3 {if ($2 == 0) print "未启用"; else printf "%d/%d MB (%d%%)", $3, $2, $3 * 100 / $2}')"
  kv "磁盘 /" "$disk"
  kv "公网 IP" "$ip"
  kv "累计流量" "接收 $(bytes_h "${rx:-0}") / 发送 $(bytes_h "${tx:-0}")"
}

system_env() {
  local tz bbr dns shell_ver docker_ver
  if have timedatectl; then
    tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  fi
  [[ -n ${tz:-} ]] || tz=$(readlink -f /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
  [[ -n ${tz:-} ]] || tz=$(date +%Z)

  bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
  dns=$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)
  docker_ver="未安装"
  if have docker; then
    docker_ver=$(docker --version 2>/dev/null | sed 's/^Docker version //;s/,.*//')
  fi

  section "系统环境"
  kv "发行版" "$OS_NAME"
  kv "版本号" "${OS_VER:-未知}"
  kv "内核" "$(uname -r)"
  kv "架构" "$ARCH"
  kv "虚拟化" "$VIRT"
  kv "包管理器" "$PKG"
  kv "服务管理" "$INIT"
  kv "时区" "$tz"
  kv "Shell" "$(basename "${SHELL:-bash}") ${BASH_VERSION%(*}"
  kv "DNS" "${dns:-未知}"
  kv "TCP 算法" "$bbr"
  kv "Docker" "$docker_ver"
  kv "公网 IP" "$(get_public_ip)"
}

system_load() {
  section "资源负载"
  kv "负载（1/5/15 分钟）" "$(get_load)"
  kv "CPU 核心" "$(nproc 2>/dev/null || echo 未知)"
  printf '\n'
  uptime 2>/dev/null || true

  section "CPU 占用前 5"
  ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -n 6 || warn "当前系统不支持 ps 排序"

  section "内存占用前 5"
  ps -eo pid,pcpu,pmem,comm --sort=-pmem 2>/dev/null | head -n 6 || true
}

system_disk() {
  section "文件系统占用"
  df -hT 2>/dev/null || df -h

  section "根目录一级目录占用"
  info "磁盘较大时统计可能耗时，请耐心等待…"
  if du -xhd1 / 2>/dev/null | sort -rh | head -n 12; then
    :
  else
    du -x -k / 2>/dev/null | sort -rn | head -n 12
  fi
}

system_clean() {
  require_root
  section "清理项目"
  printf '  - 系统包管理器缓存\n'
  printf '  - systemd journal 日志（保留最近 200M）\n'
  printf '  - /tmp 下 7 天未访问的文件\n'
  printf '  - /var/log 下 30 天前的 .gz 日志\n\n'
  confirm "确认执行清理？" || return 0

  local before after freed
  before=$(df -m / | awk 'NR==2 {print $4}')
  info "清理包管理器缓存…"
  pkg_clean || warn "包缓存清理未完成"

  if [[ ${INIT:-sysv} == systemd ]] && have journalctl; then
    info "清理 journal 日志…"
    journalctl --vacuum-size=200M 2>/dev/null | tail -n 1 || true
  fi

  info "清理 /tmp 过期文件…"
  find /tmp -mindepth 1 -mtime +7 -exec rm -rf -- {} + 2>/dev/null || true

  info "清理过期日志…"
  find /var/log -type f -name '*.gz' -mtime +30 -delete 2>/dev/null || true

  after=$(df -m / | awk 'NR==2 {print $4}')
  if [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]]; then
    freed=$(( after - before ))
    ok "清理完成，根分区可用空间变化约 ${freed} MB"
  else
    ok "清理完成"
  fi
}

system_update() {
  require_root
  confirm "更新系统软件包？升级内核或服务后可能需要重启，建议先备份重要数据" || return 0
  pkg_upgrade || die "系统更新失败"
  ok "系统更新完成"
  if [[ -f /var/run/reboot-required ]]; then
    warn "系统提示需要重启：/var/run/reboot-required"
  fi
  if have needrestart; then
    needrestart -b 2>/dev/null || true
  fi
}

system_clean_deep() {
  require_root
  section "深度清理项目"
  printf '  - 自动移除不再需要的依赖与残留配置\n'
  printf '  - 清理包管理器缓存\n'
  printf '  - journal 日志压缩到 50M\n'
  printf '  - /tmp 下 7 天未访问文件\n'
  printf '  - /var/log 下 30 天前的 .gz 日志\n'
  printf '  说明：不会自动删除旧内核，避免误删当前或回退内核\n\n'
  confirm "确认执行深度清理？" || return 0

  local before after freed
  before=$(df -m / | awk 'NR==2 {print $4}')

  case ${PKG:-unknown} in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y || warn "autoremove 未完成"
      DEBIAN_FRONTEND=noninteractive apt-get autoclean -y || true
      dpkg -l 2>/dev/null | awk '/^rc/ {print $2}' | xargs -r apt-get purge -y >/dev/null 2>&1 || true
      ;;
    dnf|yum) "$PKG" autoremove -y || true ;;
    apk) apk cache clean || true ;;
    pacman) pacman -Rns --noconfirm $(pacman -Qtdq 2>/dev/null) 2>/dev/null || true ;;
    *) warn "未知包管理器，跳过依赖清理" ;;
  esac
  pkg_clean || warn "包缓存清理未完成"

  if have journalctl; then
    journalctl --vacuum-size=50M 2>/dev/null | tail -n 1 || true
  fi
  find /tmp -mindepth 1 -mtime +7 -exec rm -rf -- {} + 2>/dev/null || true
  find /var/log -type f -name '*.gz' -mtime +30 -delete 2>/dev/null || true

  after=$(df -m / | awk 'NR==2 {print $4}')
  if [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]]; then
    freed=$(( after - before ))
    ok "深度清理完成，根分区可用空间变化约 ${freed} MB"
  else
    ok "深度清理完成"
  fi
}

system_dns() {
  local -a servers=("$@") valid=()
  if [[ ${#servers[@]} -eq 0 ]]; then
    local input
    input=$(ask "DNS 服务器（空格分隔）" "223.5.5.5 1.1.1.1")
    read -r -a servers <<<"$input"
  fi
  [[ ${#servers[@]} -gt 0 ]] || die "未提供 DNS 服务器"
  local ip
  for ip in "${servers[@]}"; do
    [[ $ip =~ ^[0-9A-Fa-f:.]+$ ]] || die "DNS 地址格式无效：$ip"
    valid+=("$ip")
  done
  require_root
  confirm "将 DNS 设置为：${valid[*]}？" || return 0

  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    local dir=/etc/systemd/resolved.conf.d
    mkdir -p "$dir"
    {
      printf '[Resolve]\n'
      printf 'DNS=%s\n' "${valid[*]}"
      printf 'FallbackDNS=8.8.8.8 1.0.0.1\n'
    } >"$dir/99-sst-dns.conf"
    systemctl restart systemd-resolved || die "systemd-resolved 重启失败"
    have resolvectl && resolvectl flush-caches >/dev/null 2>&1 || true
    ok "已通过 systemd-resolved 应用 DNS：${valid[*]}"
  else
    backup_config_file /etc/resolv.conf resolv.conf >/dev/null 2>&1 || true
    {
      printf '# managed by stbox\n'
      for ip in "${valid[@]}"; do printf 'nameserver %s\n' "$ip"; done
    } >/etc/resolv.conf
    ok "已写入 /etc/resolv.conf：${valid[*]}"
  fi

  if getent hosts github.com >/dev/null 2>&1; then
    ok "DNS 解析测试通过"
  else
    warn "DNS 解析测试失败，请检查网络或更换 DNS"
  fi
}

system_timezone() {
  local tz=${1:-}
  [[ -n $tz ]] || tz=$(ask "时区（如 Asia/Shanghai）" "Asia/Shanghai")
  [[ -f /usr/share/zoneinfo/$tz ]] || die "无效时区：$tz"
  require_root
  confirm "将系统时区设置为 $tz？" || return 0
  if have timedatectl; then
    timedatectl set-timezone "$tz" || die "时区设置失败"
  else
    ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime || die "时区设置失败"
    printf '%s\n' "$tz" >/etc/timezone
  fi
  ok "时区已设置为 $tz（当前时间：$(date '+%F %T %Z')）"
}

system_hostname() {
  local new=${1:-}
  [[ -n $new ]] || new=$(ask "新主机名" "$(hostname)")
  [[ $new =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "主机名只能包含字母、数字、点和短横线"
  require_root
  confirm "将主机名从 $(hostname) 修改为 $new？" || return 0
  if have hostnamectl; then
    hostnamectl set-hostname "$new" || die "主机名修改失败"
  else
    hostname "$new" || die "主机名修改失败"
    printf '%s\n' "$new" >/etc/hostname
  fi
  ok "主机名已修改为 $new（SSH 提示符会在重新登录后更新）"
}

system_rootpass() {
  require_root
  local pass
  read -r -s -p "请输入新的 root 密码: " pass || return 1
  printf '\n'
  [[ -n $pass ]] || die "密码不能为空"
  confirm "确认修改 root 密码？" || return 0
  if printf 'root:%s\n' "$pass" | chpasswd; then
    ok "root 密码已修改"
  else
    die "root 密码修改失败"
  fi
}

system_portscan() {
  local target=${1:-} ports=${2:-200}
  [[ -n $target ]] || target=$(ask "扫描目标 IP/域名" "$(get_public_ip)")
  [[ $ports =~ ^[0-9]+$ ]] && (( ports >= 10 && ports <= 1000 )) \
    || die "扫描端口数需在 10-1000 之间"

  if ! have nmap; then
    confirm "安装 nmap 用于端口扫描？" || return 0
    pkg_update || die "软件源更新失败"
    pkg_install nmap || die "nmap 安装失败"
  fi
  warn "请仅扫描你有权限测试的服务器"
  info "使用 nmap 扫描 $target 的 TCP Top ${ports} 端口…"
  nmap -Pn --top-ports "$ports" "$target"
}

system_cron() {
  local action=${1:-}
  if [[ -z $action ]]; then
    system_cron list
    [[ -t 0 ]] || return 0
    printf '  %s1%s) 添加任务\n  %s2%s) 删除本工具任务\n  %s0%s) 返回\n\n' \
      "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET"
    local choice
    read -r -p "请选择: " choice || return 0
    case $choice in
      1) action=add ;;
      2) action=remove ;;
      0|q|back) return 0 ;;
      *) warn "无效选项"; return 0 ;;
    esac
  fi

  case $action in
    list)
      section "定时任务"
      info "当前用户 crontab："
      crontab -l 2>/dev/null || echo "  （空）"
      hr
      info "/etc/cron.d 下的任务文件："
      ls -1 /etc/cron.d 2>/dev/null || echo "  （无）"
      if compgen -G "/etc/cron.d/sst-*" >/dev/null 2>&1; then
        hr
        for f in /etc/cron.d/sst-*; do
          printf '%s\n' "--- $(basename "$f")"
          grep -vE '^(#|SHELL=|PATH=)' "$f" 2>/dev/null || true
        done
      fi
      ;;
    add)
      require_root
      local name schedule cmd file
      name=$(ask "任务名称（字母数字）" "mytask")
      [[ $name =~ ^[A-Za-z0-9_-]+$ ]] || die "任务名称仅支持字母、数字、下划线和短横线"
      schedule=$(ask "执行时间（分 时 日 月 周）" "0 3 * * *")
      local -a cron_fields=()
      read -r -a cron_fields <<<"$schedule"
      [[ ${#cron_fields[@]} -eq 5 ]] || die "cron 时间格式应为 5 段，如：0 3 * * *"
      cmd=$(ask "要执行的命令" "st backup create")
      [[ -n $cmd ]] || die "命令不能为空"
      file="/etc/cron.d/sst-$name"
      confirm "写入 $file：$schedule root $cmd ？" || return 0
      cat >"$file" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$schedule root $cmd
EOF
      chmod 644 "$file"
      ok "定时任务已添加：$file"
      ;;
    remove)
      require_root
      local -a files=()
      mapfile -t files < <(ls -1 /etc/cron.d/sst-* 2>/dev/null)
      [[ ${#files[@]} -gt 0 ]] || { info "没有本工具创建的定时任务"; return 0; }
      section "选择要删除的任务"
      local i
      for i in "${!files[@]}"; do
        printf '  %2d) %s\n' "$((i + 1))" "$(basename "${files[$i]}")"
      done
      local choice
      read -r -p "编号: " choice || return 1
      [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )) || die "无效编号"
      rm -f "${files[$((choice - 1))]}"
      ok "已删除 ${files[$((choice - 1))]}"
      ;;
    *) die "用法：st system cron [list|add|remove]" ;;
  esac
}

system_shortcut() {
  local alias=${1:-}
  [[ -n $alias ]] || alias=$(ask "快捷命令（单个字母）" "k")
  [[ $alias =~ ^[A-Za-z]$ ]] || die "快捷命令必须是单个字母"
  [[ $alias == "st" ]] && die "st 是默认命令，请换一个字母"
  require_root
  local target="/usr/local/bin/$alias"
  if [[ -e $target && ! -L $target ]]; then
    confirm "$target 已存在且不是软链接，覆盖它？" || return 0
  fi
  ln -sfn "$SST_ENTRY" "$target" || die "创建快捷命令失败"
  hash -r 2>/dev/null || true
  ok "已设置快捷命令：$alias → $SST_ENTRY"
}
