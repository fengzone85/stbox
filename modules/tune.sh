#!/usr/bin/env bash
# 模块：系统调优（网络参数、SWAP、IP 优先级、软件源）
# 使用独立配置文件，提供应用与还原能力。

sst_register_module tune "系统优化" "网络参数 SWAP 双栈 换源"
SST_MODULE_ITEMS[tune]=$'status|优化项概览\nsysctl|网络参数优化\nswap|SWAP 管理\nipv6|IPv4/IPv6 优先级\nmirror|apt 软件源切换'

TUNE_SYSCTL_FILE=/etc/sysctl.d/99-sst-tune.conf
TUNE_LIMIT_FILE=/etc/security/limits.d/99-sst.conf
TUNE_SWAP_FILE=/swapfile

tune_status() {
  local swap_state='未启用' apt_hosts bbr
  if have swapon; then
    swap_state=$(swapon --show --noheadings 2>/dev/null | awk '{printf "%s(%s) ", $1, $3}')
    [[ -n $swap_state ]] || swap_state='未启用'
  fi
  apt_hosts=$(tune_apt_hosts)
  bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)

  section "优化项概览"
  kv "网络参数" "$([[ -f $TUNE_SYSCTL_FILE ]] && echo 已应用 || echo 未应用)"
  kv "文件句柄限制" "$([[ -f $TUNE_LIMIT_FILE ]] && echo 已配置 || echo 默认)（当前 shell：$(ulimit -n)）"
  kv "SWAP" "$swap_state"
  kv "IPv4 优先" "$(grep -qE '^precedence ::ffff:0:0/96 +100' /etc/gai.conf 2>/dev/null && echo 已设置 || echo 默认（IPv6 优先）)"
  kv "apt 源" "${apt_hosts:-非 apt 系统}"
  kv "TCP 算法" "$bbr"
  kv "BBR 开关" "st security bbr_on / bbr_off"
  printf '\n'
  info "网络参数文件：$TUNE_SYSCTL_FILE"
  info "句柄限制文件：$TUNE_LIMIT_FILE"
}

tune_apt_hosts() {
  local -a files=()
  [[ -f /etc/apt/sources.list ]] && files+=("/etc/apt/sources.list")
  if [[ -d /etc/apt/sources.list.d ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(
      find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) 2>/dev/null
    )
  fi
  (( ${#files[@]} )) || return 0
  grep -hoE 'https?://[^/[:space:]]+' "${files[@]}" 2>/dev/null | sort -u | paste -sd, -
}

# ---------- 网络参数 ----------
tune_sysctl() {
  local action=${1:-}
  if [[ -z $action ]]; then
    tune_sysctl_status
    printf '  %s1%s) 应用网络优化\n' "$C_GREEN" "$C_RESET"
    printf '  %s2%s) 还原优化配置\n' "$C_GREEN" "$C_RESET"
    printf '  %s0%s) 返回\n\n' "$C_GREEN" "$C_RESET"
    local choice
    read -r -p "请选择: " choice || return 0
    case $choice in
      1) action=on ;;
      2) action=off ;;
      0|q|back) return 0 ;;
      *) warn "无效选项"; return 0 ;;
    esac
  fi
  case $action in
    status) tune_sysctl_status ;;
    on|apply) tune_sysctl_on ;;
    off|revert) tune_sysctl_off ;;
    *) die "用法：st tune sysctl [status|on|off]" ;;
  esac
}

tune_sysctl_status() {
  section "网络参数状态"
  kv "配置文件" "$([[ -f $TUNE_SYSCTL_FILE ]] && echo 已应用 || echo 未应用)"
  local key
  for key in net.core.somaxconn net.core.netdev_max_backlog net.ipv4.tcp_fastopen \
    net.ipv4.tcp_tw_reuse net.ipv4.ip_local_port_range net.ipv4.tcp_max_syn_backlog \
    fs.file-max net.ipv4.tcp_slow_start_after_idle; do
    kv "$key" "$(sysctl -n "$key" 2>/dev/null || echo 未知)"
  done
  kv "nofile 限制" "$([[ -f $TUNE_LIMIT_FILE ]] && echo 已配置 || echo 默认)（当前 $(ulimit -n)）"
  warn "tcp_timestamps 保持开启，避免 NAT/PAWS 兼容问题（与部分一键脚本不同）"
}

tune_sysctl_on() {
  require_root
  section "将应用以下优化"
  cat <<'EOF'
  net.core.somaxconn = 32768
  net.core.netdev_max_backlog = 32768
  net.ipv4.tcp_fastopen = 3
  net.ipv4.tcp_tw_reuse = 1
  net.ipv4.tcp_fin_timeout = 30
  net.ipv4.tcp_slow_start_after_idle = 0
  net.ipv4.tcp_retries2 = 8
  net.ipv4.tcp_max_syn_backlog = 16384
  net.ipv4.ip_local_port_range = 1024 65000
  fs.file-max = 1000000
  fs.inotify.max_user_instances = 8192
  nofile soft/hard = 1000000
EOF
  confirm "写入独立配置文件并立即生效（不覆盖现有 sysctl.conf/limits.conf）？" || return 0

  local bak=''
  if [[ -f $TUNE_SYSCTL_FILE ]]; then
    bak=$(mktemp)
    cp "$TUNE_SYSCTL_FILE" "$bak"
  fi

  cat >"$TUNE_SYSCTL_FILE" <<'EOF'
# managed by stbox
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65000
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
EOF

  if ! sysctl --system >/dev/null 2>&1; then
    if [[ -n $bak ]]; then cp "$bak" "$TUNE_SYSCTL_FILE"; else rm -f "$TUNE_SYSCTL_FILE"; fi
    rm -f "$bak"
    die "sysctl 应用失败，已还原配置"
  fi
  [[ -n $bak ]] && rm -f "$bak"

  mkdir -p /etc/security/limits.d
  cat >"$TUNE_LIMIT_FILE" <<'EOF'
# managed by stbox
* soft nofile 1000000
* hard nofile 1000000
EOF

  ulimit -SHn 1000000 2>/dev/null || warn "当前 shell 无法提升 nofile，重新登录后生效"
  tune_sysctl_status
  ok "网络参数优化已应用；文件句柄限制对新登录会话生效"
}

tune_sysctl_off() {
  require_root
  confirm "移除本工具写入的网络参数与句柄限制配置？" || return 0
  rm -f "$TUNE_SYSCTL_FILE" "$TUNE_LIMIT_FILE"
  sysctl --system >/dev/null 2>&1 || true
  warn "配置已移除，已运行的内核参数与 ulimit 会在重启后恢复默认值"
  tune_sysctl_status
}

# ---------- SWAP ----------
tune_swap() {
  local action=${1:-}
  if [[ -z $action ]]; then
    tune_swap_status
    printf '  %s1%s) 创建/调整 SWAP\n' "$C_GREEN" "$C_RESET"
    printf '  %s2%s) 移除 SWAP\n' "$C_GREEN" "$C_RESET"
    printf '  %s0%s) 返回\n\n' "$C_GREEN" "$C_RESET"
    local choice
    read -r -p "请选择: " choice || return 0
    case $choice in
      1) action=create ;;
      2) action=remove ;;
      0|q|back) return 0 ;;
      *) warn "无效选项"; return 0 ;;
    esac
  fi
  case $action in
    status) tune_swap_status ;;
    create|on) tune_swap_create ;;
    remove|off) tune_swap_remove ;;
    *) die "用法：st tune swap [status|create|remove]" ;;
  esac
}

tune_swap_status() {
  section "SWAP 状态"
  if have swapon; then
    swapon --show 2>/dev/null || true
  fi
  free -m 2>/dev/null | awk 'NR<=3'
  kv "swappiness" "$(sysctl -n vm.swappiness 2>/dev/null || echo 未知)"
  if [[ -f /proc/swaps ]] && grep -q "$TUNE_SWAP_FILE" /proc/swaps 2>/dev/null; then
    kv "本工具 SWAP 文件" "$TUNE_SWAP_FILE"
  fi
}

tune_swap_create() {
  require_root
  local size num unit mb avail_mb swappiness
  size=$(ask "SWAP 大小（如 1G、512M）" "1G")
  [[ $size =~ ^([0-9]+)([GgMm])$ ]] || die "大小格式错误，示例：1G / 512M"
  num=${BASH_REMATCH[1]}
  unit=${BASH_REMATCH[2]^^}
  if [[ $unit == G ]]; then
    mb=$((num * 1024))
  else
    mb=$num
  fi
  (( mb >= 128 && mb <= 16384 )) || die "SWAP 大小需在 128M - 16G 之间"

  if [[ -e $TUNE_SWAP_FILE ]] || grep -q "$TUNE_SWAP_FILE" /proc/swaps 2>/dev/null; then
    die "$TUNE_SWAP_FILE 已存在或已启用，请先执行移除"
  fi

  avail_mb=$(df -Pm / | awk 'NR==2 {print $4}')
  if [[ $avail_mb =~ ^[0-9]+$ ]] && (( avail_mb < mb * 2 )); then
    warn "根分区可用 ${avail_mb} MB，创建 ${mb} MB SWAP 后空间会非常紧张"
    confirm "仍然继续？" || return 0
  fi

  swappiness=$(ask "vm.swappiness（0-100）" "10")
  [[ $swappiness =~ ^[0-9]+$ ]] && (( swappiness >= 0 && swappiness <= 100 )) || die "swappiness 必须在 0-100"

  confirm "在 $TUNE_SWAP_FILE 创建 ${num}${unit} SWAP 并写入 /etc/fstab？" || return 0

  info "分配文件…"
  if ! fallocate -l "${num}${unit}" "$TUNE_SWAP_FILE" 2>/dev/null; then
    info "fallocate 不可用，改用 dd 写入…"
    dd if=/dev/zero of="$TUNE_SWAP_FILE" bs=1M count="$mb" status=progress 2>&1 | tail -n 2 \
      || die "创建 SWAP 文件失败"
  fi
  chmod 600 "$TUNE_SWAP_FILE"
  mkswap "$TUNE_SWAP_FILE" >/dev/null || die "mkswap 失败"
  swapon "$TUNE_SWAP_FILE" || die "swapon 失败"

  backup_config_file /etc/fstab fstab >/dev/null 2>&1 || true
  if ! awk -v f="$TUNE_SWAP_FILE" '$1 == f {found=1} END {exit !found}' /etc/fstab; then
    printf '%s none swap sw 0 0\n' "$TUNE_SWAP_FILE" >>/etc/fstab
  fi

  cat >/etc/sysctl.d/99-sst-swap.conf <<EOF
# managed by stbox
vm.swappiness = $swappiness
EOF
  sysctl --system >/dev/null 2>&1 || warn "swappiness 应用失败"

  tune_swap_status
  ok "SWAP 已启用：${num}${unit}（swappiness=$swappiness）"
}

tune_swap_remove() {
  require_root
  if [[ ! -e $TUNE_SWAP_FILE ]] && ! grep -q "$TUNE_SWAP_FILE" /proc/swaps 2>/dev/null; then
    info "未发现本工具创建的 $TUNE_SWAP_FILE"
    return 0
  fi
  confirm "关闭并删除 $TUNE_SWAP_FILE，同时清理 /etc/fstab 与 swappiness 配置？" || return 0

  if ! swapoff "$TUNE_SWAP_FILE" 2>/dev/null; then
    die "swapoff 失败，$TUNE_SWAP_FILE 可能仍在使用，已中止"
  fi
  backup_config_file /etc/fstab fstab >/dev/null 2>&1 || true
  local tmp
  tmp=$(mktemp)
  awk -v f="$TUNE_SWAP_FILE" '$1 != f' /etc/fstab >"$tmp" && cat "$tmp" >/etc/fstab
  rm -f "$tmp"
  rm -f "$TUNE_SWAP_FILE" /etc/sysctl.d/99-sst-swap.conf
  sysctl --system >/dev/null 2>&1 || true
  ok "SWAP 已移除"
  tune_swap_status
}

# ---------- IPv4/IPv6 优先级 ----------
tune_ipv6() {
  local action=${1:-}
  if [[ -z $action ]]; then
    tune_ipv6_status
    printf '  %s1%s) 优先 IPv4\n' "$C_GREEN" "$C_RESET"
    printf '  %s2%s) 优先 IPv6（恢复默认）\n' "$C_GREEN" "$C_RESET"
    printf '  %s0%s) 返回\n\n' "$C_GREEN" "$C_RESET"
    local choice
    read -r -p "请选择: " choice || return 0
    case $choice in
      1) action=4 ;;
      2) action=6 ;;
      0|q|back) return 0 ;;
      *) warn "无效选项"; return 0 ;;
    esac
  fi
  case $action in
    status) tune_ipv6_status ;;
    4|prefer4|on) tune_ipv6_prefer4 ;;
    6|prefer6|default|off) tune_ipv6_prefer6 ;;
    *) die "用法：st tune ipv6 [status|4|6]" ;;
  esac
}

tune_ipv6_status() {
  section "IPv4/IPv6 优先级"
  kv "gai.conf" "$(grep -qE '^precedence ::ffff:0:0/96 +100' /etc/gai.conf 2>/dev/null && echo IPv4 优先 || echo 默认（IPv6 优先）)"
  local v6
  v6=$(ip -6 addr show scope global 2>/dev/null | grep -c 'inet6' || true)
  kv "本机 IPv6 地址" "${v6:-0} 个"
  kv "公网 IPv4" "$(get_public_ip)"
}

tune_ipv6_prefer4() {
  require_root
  confirm "设置 IPv4 优先（写入 /etc/gai.conf，对新启动的程序生效）？" || return 0
  backup_config_file /etc/gai.conf gai.conf >/dev/null 2>&1 || true
  touch /etc/gai.conf
  if grep -qE '^precedence ::ffff:0:0/96 +100' /etc/gai.conf; then
    info "IPv4 优先已存在"
  else
    printf '\n# managed by stbox\nprecedence ::ffff:0:0/96 100\n' >>/etc/gai.conf
  fi
  ok "已设置 IPv4 优先；已运行的程序需重启后生效"
}

tune_ipv6_prefer6() {
  require_root
  if ! grep -qE '^precedence ::ffff:0:0/96 +100' /etc/gai.conf 2>/dev/null; then
    info "当前已是 IPv6 优先（gai.conf 默认）"
    return 0
  fi
  confirm "移除 IPv4 优先规则，恢复 IPv6 优先？" || return 0
  backup_config_file /etc/gai.conf gai.conf >/dev/null 2>&1 || true
  local tmp
  tmp=$(mktemp)
  grep -vE '^precedence ::ffff:0:0/96 +100' /etc/gai.conf >"$tmp"
  cat "$tmp" >/etc/gai.conf
  rm -f "$tmp"
  ok "已恢复 IPv6 优先"
}

# ---------- apt 换源 ----------
tune_mirror() {
  local target=${1:-}
  if [[ -z $target ]]; then
    tune_mirror_status
    printf '  %s1%s) 阿里云镜像\n' "$C_GREEN" "$C_RESET"
    printf '  %s2%s) 清华 TUNA\n' "$C_GREEN" "$C_RESET"
    printf '  %s3%s) 中科大 USTC\n' "$C_GREEN" "$C_RESET"
    printf '  %s4%s) 网易 163\n' "$C_GREEN" "$C_RESET"
    printf '  %s5%s) 恢复备份\n' "$C_GREEN" "$C_RESET"
    printf '  %s0%s) 返回\n\n' "$C_GREEN" "$C_RESET"
    local choice
    read -r -p "请选择: " choice || return 0
    case $choice in
      1) target=aliyun ;;
      2) target=tuna ;;
      3) target=ustc ;;
      4) target=163 ;;
      5) target=restore ;;
      0|q|back) return 0 ;;
      *) warn "无效选项"; return 0 ;;
    esac
  fi

  if [[ $target == status ]]; then
    tune_mirror_status
    return 0
  fi
  [[ ${PKG:-unknown} == apt ]] || die "apt 换源仅支持 Debian/Ubuntu；RHEL 系请使用 st tools changesource"

  if [[ $target != restore && ${OS_ID:-} != debian && ${OS_ID:-} != ubuntu ]]; then
    die "当前发行版为 $OS_ID，使用自有软件源；自动换源仅支持 Debian/Ubuntu，避免破坏系统源"
  fi
  require_root

  local backup_dir="$SST_DATA_DIR/backups/config"
  mkdir -p "$backup_dir"

  if [[ $target == restore ]]; then
    local latest
    latest=$(ls -1t "$backup_dir"/apt-sources-*.tar.gz 2>/dev/null | head -n 1)
    [[ -n $latest ]] || die "没有可用的 apt 源备份"
    kv "备份文件" "$latest"
    confirm "用该备份覆盖当前 apt 源配置？" || return 0
    tar -xzf "$latest" -C / || die "恢复失败"
    ok "apt 源配置已恢复"
    tune_mirror_status
    return 0
  fi

  local host
  case $target in
    aliyun) host=mirrors.aliyun.com ;;
    tuna) host=mirrors.tuna.tsinghua.edu.cn ;;
    ustc) host=mirrors.ustc.edu.cn ;;
    163) host=mirrors.163.com ;;
    *) die "未知镜像：$target" ;;
  esac

  local -a files=()
  [[ -f /etc/apt/sources.list ]] && files+=("/etc/apt/sources.list")
  if [[ -d /etc/apt/sources.list.d ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(
      find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) 2>/dev/null
    )
  fi
  (( ${#files[@]} )) || die "未找到 apt 源文件"

  confirm "将 apt 源切换到 $host（会先备份当前配置）？" || return 0
  local ts backup
  ts=$(date +%Y%m%d-%H%M%S)
  backup="$backup_dir/apt-sources-$ts.tar.gz"
  local -a paths=()
  [[ -e /etc/apt/sources.list ]] && paths+=("etc/apt/sources.list")
  [[ -d /etc/apt/sources.list.d ]] && paths+=("etc/apt/sources.list.d")
  tar -czf "$backup" -C / "${paths[@]}" || die "备份 apt 源失败"

  local f changed=0 before after
  for f in "${files[@]}"; do
    before=$(md5sum "$f" | awk '{print $1}')
    sed -i -E "s#https?://(deb\.debian\.org|security\.debian\.org|archive\.ubuntu\.com|security\.ubuntu\.com|ports\.ubuntu\.com|mirrors\.aliyun\.com|mirrors\.tuna\.tsinghua\.edu\.cn|mirrors\.ustc\.edu\.cn|mirrors\.163\.com|mirrors\.tencent\.com|mirrors\.cloud\.tencent\.com|mirrors\.huaweicloud\.com|repo\.huaweicloud\.com|mirrors\.bfsu\.edu\.cn|mirrors\.nju\.edu\.cn)#https://${host}#g" "$f"
    after=$(md5sum "$f" | awk '{print $1}')
    [[ $before != "$after" ]] && changed=1
  done
  if (( changed == 0 )); then
    warn "未匹配到可替换的公共镜像地址，当前可能为发行版自有源，未做修改"
    return 0
  fi
  ok "已切换到 $host（备份：$backup）"
  tune_mirror_status

  if confirm "立即执行 apt-get update 验证新源？"; then
    if apt-get update; then
      ok "apt 源工作正常"
    else
      warn "apt-get update 失败，可执行 st tune mirror restore 回滚"
    fi
  fi
}

tune_mirror_status() {
  section "apt 软件源"
  kv "镜像地址" "$(tune_apt_hosts)"
  local -a files=()
  [[ -f /etc/apt/sources.list ]] && files+=("/etc/apt/sources.list")
  [[ -d /etc/apt/sources.list.d ]] && while IFS= read -r f; do files+=("$f"); done < <(
    find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) 2>/dev/null
  )
  if (( ${#files[@]} )); then
    hr
    grep -hE '^(deb|URIs|Suites|Components)' "${files[@]}" 2>/dev/null | head -n 20
  fi
}
