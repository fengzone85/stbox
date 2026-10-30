#!/usr/bin/env bash
# 模块：安全与优化

sst_register_module security "安全与优化" "防火墙 SSH BBR Fail2ban"
SST_MODULE_ITEMS[security]=$'status|安全状况\nfirewall_status|防火墙状态\nfirewall_allow|开放端口\nfirewall_enable|启用防火墙\nfirewall_disable|关闭防火墙\nssh_status|SSH 配置\nssh_port|修改 SSH 端口\nssh_password|禁用密码登录\nssh_password_on|开启 root 密码登录\nssh_root|限制 root 登录\nbbr_status|BBR 状态\nbbr_on|开启 BBR\nbbr_off|关闭 BBR\nfail2ban_status|Fail2ban 状态\nfail2ban_install|安装 Fail2ban'

ssh_service_name() {
  if [[ ${INIT:-sysv} == systemd ]]; then
    if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
      printf 'ssh'
    else
      printf 'sshd'
    fi
  else
    printf 'sshd'
  fi
}

sshd_config_file() { printf '/etc/ssh/sshd_config'; }

ssh_cfg_get() {
  local key=$1 v='' cfg
  cfg=$(sshd_config_file)
  if have sshd && [[ ${EUID:-1} -eq 0 ]]; then
    v=$(sshd -T 2>/dev/null | awk -v k="${key,,}" '$1 == k {print $2; exit}')
  fi
  [[ -n $v ]] || v=$(awk -v k="$key" 'tolower($1) == tolower(k) && $1 !~ /^#/ {v = $2} END {print v}' "$cfg" 2>/dev/null)
  printf '%s' "${v:-未知}"
}

ssh_current_port() {
  local port
  port=$(ssh_cfg_get Port)
  port=$(printf '%s' "$port" | awk '{print $1}')
  [[ $port =~ ^[0-9]+$ ]] || port=22
  printf '%s' "$port"
}

ssh_all_ports() {
  local ports=''
  if have sshd && [[ ${EUID:-1} -eq 0 ]]; then
    ports=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | sort -u | paste -sd, -)
  fi
  if [[ -z $ports ]]; then
    ports=$(awk 'tolower($1) == "port" && $1 !~ /^#/ {print $2}' \
      "$(sshd_config_file)" 2>/dev/null | sort -u | paste -sd, -)
  fi
  printf '%s' "${ports:-22}"
}

svc_state_text() {
  if svc_active "$1"; then printf '运行中'; else printf '未运行'; fi
}

_fw_installed() {
  if have ufw; then printf 'ufw'
  elif have firewall-cmd; then printf 'firewalld'
  elif have nft; then printf 'nftables'
  elif have iptables; then printf 'iptables'
  else printf 'none'
  fi
}

_ufw_state() {
  local state
  state=$(ufw status 2>/dev/null | head -n 1 | awk '{print $2}')
  printf '%s' "${state:-需 root 查看}"
}

backup_config_file() {
  local src=$1 tag=${2:-$(basename "$1")} dir ts dest
  dir="$SST_DATA_DIR/backups/config"
  mkdir -p "$dir" || return 1
  ts=$(date +%Y%m%d-%H%M%S)
  dest="$dir/${tag}.${ts}"
  cp -a "$src" "$dest" || return 1
  chmod 600 "$dest" 2>/dev/null || true
  printf '%s\n' "$dest"
}

# 替换或追加单个 sshd 指令，写入前做语法校验
ssh_set_option() {
  local key=$1 value=$2 cfg tmp backup
  cfg=$(sshd_config_file)
  [[ -f $cfg ]] || die "找不到 $cfg"
  backup=$(backup_config_file "$cfg" sshd_config) || die "备份 sshd_config 失败"
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
  ' "$cfg" >"$tmp"

  if have sshd && ! sshd -t -f "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die "新配置校验失败，原配置未改动（备份：$backup）"
  fi
  cat "$tmp" >"$cfg"
  rm -f "$tmp"
  info "已设置 $key $value（备份：$backup）"
}

# 新增端口（保留旧端口，避免改端口后无法连接）
ssh_add_port() {
  local port=$1 cfg tmp backup
  cfg=$(sshd_config_file)
  backup=$(backup_config_file "$cfg" sshd_config) || die "备份 sshd_config 失败"
  tmp=$(mktemp)
  cat "$cfg" >"$tmp"
  printf '\n# added by stbox\nPort %s\n' "$port" >>"$tmp"
  if have sshd && ! sshd -t -f "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die "新配置校验失败，原配置未改动（备份：$backup）"
  fi
  cat "$tmp" >"$cfg"
  rm -f "$tmp"
  info "已新增 SSH 端口 $port（旧端口保留，备份：$backup）"
}

security_status() {
  local fw root_login pass_auth
  root_login=$(ssh_cfg_get PermitRootLogin)
  pass_auth=$(ssh_cfg_get PasswordAuthentication)
  if [[ ${EUID:-1} -ne 0 ]]; then
    [[ $root_login == 未知 ]] && root_login="需 root 查看"
    [[ $pass_auth == 未知 ]] && pass_auth="需 root 查看"
  fi
  section "SSH"
  kv "端口" "$(ssh_current_port)"
  kv "root 登录" "$root_login"
  kv "密码登录" "$pass_auth"
  kv "服务状态" "$(svc_state_text "$(ssh_service_name)")"

  section "防火墙"
  fw=$(_fw_installed)
  kv "类型" "$fw"
  case $fw in
    ufw) kv "状态" "$(_ufw_state)" ;;
    firewalld) kv "状态" "$(svc_state_text firewalld)" ;;
    nftables) kv "状态" "$(nft list ruleset 2>/dev/null | grep -c . ) 条规则" ;;
    iptables) kv "状态" "$(iptables -S 2>/dev/null | grep -c .) 条规则" ;;
    *) kv "状态" "未安装" ;;
  esac

  section "内核与防护"
  kv "TCP 算法" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)"
  kv "BBR" "$(bbr_available && echo 可用 || echo 不可用)"
  kv "Fail2ban" "$(have fail2ban-client && svc_state_text fail2ban || echo 未安装)"
}

bbr_available() {
  sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr
}

security_bbr_status() {
  section "BBR 状态"
  kv "当前算法" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)"
  kv "队列规则" "$(sysctl -n net.core.default_qdisc 2>/dev/null || echo 未知)"
  kv "内核支持" "$(bbr_available && echo 是 || echo 否)"
  if [[ -f /etc/sysctl.d/99-sst-bbr.conf ]]; then
    kv "配置文件" "/etc/sysctl.d/99-sst-bbr.conf"
  fi
}

security_bbr_on() {
  require_root
  if ! bbr_available; then
    warn "当前内核不支持 BBR（通常需要 4.9+ 内核），请先升级内核"
    return 1
  fi
  confirm "启用 BBR（fq 队列 + bbr 拥塞控制）？" || return 0
  cat >/etc/sysctl.d/99-sst-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  if ! sysctl --system >/dev/null 2>&1; then
    sysctl -p /etc/sysctl.d/99-sst-bbr.conf >/dev/null 2>&1 || {
      rm -f /etc/sysctl.d/99-sst-bbr.conf
      die "BBR 配置应用失败，已回滚"
    }
  fi
  security_bbr_status
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) == bbr ]]; then
    ok "BBR 已启用"
  else
    warn "配置已写入，但当前算法未切换为 bbr，重启后可能生效"
  fi
}

security_bbr_off() {
  require_root
  confirm "关闭 BBR 并恢复 cubic 拥塞控制？" || return 0
  rm -f /etc/sysctl.d/99-sst-bbr.conf
  sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
  sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || true
  ok "已移除 BBR 配置"
  security_bbr_status
}

security_firewall_status() {
  local fw
  fw=$(_fw_installed)
  section "防火墙状态"
  kv "类型" "$fw"
  case $fw in
    ufw) ufw status verbose 2>/dev/null || warn "需要 root 权限查看 UFW 状态" ;;
    firewalld) firewall-cmd --list-all 2>/dev/null || warn "firewalld 未运行" ;;
    nftables) nft list ruleset 2>/dev/null | head -n 40 ;;
    iptables) iptables -S 2>/dev/null | head -n 40 ;;
    *) warn "未检测到防火墙工具，可安装 ufw 统一管理" ;;
  esac
}

security_firewall_allow() {
  local port=${1:-} proto=${2:-tcp} fw
  [[ -n $port ]] || port=$(ask "开放端口（如 8080 或 22/tcp）" "22")
  if [[ $port == */* ]]; then
    proto=${port#*/}
    port=${port%%/*}
  fi
  valid_port "$port" || die "端口无效：$port"
  [[ $proto == tcp || $proto == udp ]] || die "协议仅支持 tcp/udp"

  require_root
  fw=$(_fw_installed)
  case $fw in
    ufw)
      ufw allow "$port/$proto" || die "UFW 规则添加失败"
      ok "已放行 $port/$proto"
      ufw status 2>/dev/null | head -n 1
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="$port/$proto" >/dev/null || die "firewalld 规则添加失败"
      firewall-cmd --reload >/dev/null || die "firewalld 重载失败"
      ok "已放行 $port/$proto（firewalld）"
      ;;
    *)
      warn "当前防火墙类型为 $fw，脚本未自动持久化规则"
      warn "建议安装 ufw 后由脚本统一管理：apt install ufw"
      return 1
      ;;
  esac
}

security_firewall_enable() {
  require_root
  local fw ssh_port
  fw=$(_fw_installed)
  if [[ $fw != ufw && $fw != firewalld ]]; then
    warn "当前防火墙类型为 $fw，建议使用 ufw 统一管理"
    confirm "现在安装 ufw？" || return 0
    pkg_install ufw || die "ufw 安装失败"
    fw=ufw
  fi

  ssh_port=$(ssh_current_port)
  if [[ $fw == ufw ]]; then
    confirm "启用 UFW（默认拒绝入站，将先放行 SSH $ssh_port/tcp）？" || return 0
    ufw allow "$ssh_port/tcp" >/dev/null || die "放行 SSH 端口失败"
    ufw --force enable || die "UFW 启用失败"
    ufw status verbose
  else
    confirm "启用 firewalld（默认放行 SSH 服务）？" || return 0
    svc_enable firewalld || die "firewalld 启动失败"
    firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    firewall-cmd --list-all
  fi
  ok "防火墙已启用，SSH 端口 $ssh_port 已放行"
}

security_firewall_disable() {
  require_root
  local fw
  fw=$(_fw_installed)
  confirm "关闭防火墙会使所有端口直接暴露，确认关闭？" || return 0
  case $fw in
    ufw) ufw --force disable; ok "UFW 已关闭" ;;
    firewalld) systemctl disable --now firewalld 2>/dev/null || true; ok "firewalld 已关闭" ;;
    *) warn "当前没有可关闭的 ufw/firewalld 防火墙" ;;
  esac
}

security_ssh_status() {
  local cfg root_login pass_auth pubkey
  cfg=$(sshd_config_file)
  root_login=$(ssh_cfg_get PermitRootLogin)
  pass_auth=$(ssh_cfg_get PasswordAuthentication)
  pubkey=$(ssh_cfg_get PubkeyAuthentication)
  if [[ ${EUID:-1} -ne 0 ]]; then
    [[ $root_login == 未知 ]] && root_login="需 root 查看"
    [[ $pass_auth == 未知 ]] && pass_auth="需 root 查看"
    [[ $pubkey == 未知 ]] && pubkey="需 root 查看"
  fi
  section "SSH 配置"
  kv "配置文件" "$cfg"
  kv "服务名称" "$(ssh_service_name)"
  kv "服务状态" "$(svc_state_text "$(ssh_service_name)")"
  kv "端口" "$(ssh_current_port)"
  kv "PermitRootLogin" "$root_login"
  kv "PasswordAuthentication" "$pass_auth"
  kv "PubkeyAuthentication" "$pubkey"
  printf '\n'
  warn "修改前请保持当前 SSH 会话不要关闭，并新开终端验证"
}

security_ssh_port() {
  require_root
  local old new svc
  old=$(ssh_current_port)
  new=${1:-}
  [[ -n $new ]] || new=$(ask "新的 SSH 端口" "22")
  valid_port "$new" || die "端口无效：$new"
  if [[ $new == "$old" ]]; then
    info "端口未变化（当前 $old）"
    return 0
  fi
  if have ss && ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":$new$"; then
    confirm "端口 $new 已有服务监听，仍要继续？" || return 0
  fi

  ssh_add_port "$new"
  svc=$(ssh_service_name)
  if ! svc_restart "$svc"; then
    err "SSH 服务重启失败，请检查配置备份：$SST_DATA_DIR/backups/config"
    return 1
  fi

  if [[ $(_fw_installed) == ufw ]] && ufw status 2>/dev/null | grep -q "Status: active"; then
    if confirm "在 UFW 中同时放行新端口 $new/tcp？"; then
      ufw allow "$new/tcp" >/dev/null || warn "UFW 放行失败"
    fi
  fi
  ok "SSH 已监听新端口 $new，旧端口 $old 保留（确认新端口可用后再手动清理）"
  info "测试命令：ssh -p $new root@$(get_public_ip)"
}

security_ssh_password() {
  require_root
  local keys
  if [[ $(ssh_cfg_get PasswordAuthentication) == no ]]; then
    info "密码登录已处于禁用状态"
    return 0
  fi
  keys=$(find /root /home -maxdepth 4 -name authorized_keys -type f -size +0c 2>/dev/null | wc -l)
  if (( keys == 0 )); then
    die "未发现非空的 authorized_keys，禁用密码登录会导致无法登录，已中止"
  fi
  confirm "禁用密码登录？请保持当前会话，并先用密钥登录验证" || return 0
  ssh_set_option PasswordAuthentication no
  svc_restart "$(ssh_service_name)" || { err "重启 SSH 失败，请检查配置备份"; return 1; }
  ok "已禁用密码登录，请新开终端验证密钥登录后再关闭当前会话"
}

security_ssh_password_on() {
  require_root
  warn "开启 root 密码登录会降低 SSH 安全性，请确保密码强度并配合 Fail2ban/防火墙"
  confirm "同时开启 PasswordAuthentication 与 PermitRootLogin yes？" || return 0
  ssh_set_option PasswordAuthentication yes
  ssh_set_option PermitRootLogin yes
  svc_restart "$(ssh_service_name)" || { err "重启 SSH 失败，请检查配置备份"; return 1; }
  ok "已开启 root 密码登录，请新开终端验证"
}

security_ssh_root() {
  require_root
  if [[ $(ssh_cfg_get PermitRootLogin) == "prohibit-password" ]]; then
    info "root 登录已限制为仅密钥模式"
    return 0
  fi
  confirm "将 PermitRootLogin 设为 prohibit-password（root 仅允许密钥登录）？" || return 0
  ssh_set_option PermitRootLogin prohibit-password
  svc_restart "$(ssh_service_name)" || { err "重启 SSH 失败，请检查配置备份"; return 1; }
  ok "已限制 root 登录方式，请新开终端验证"
}

security_fail2ban_status() {
  section "Fail2ban 状态"
  if ! have fail2ban-client; then
    warn "未安装 Fail2ban，可执行：st security fail2ban_install"
    return 1
  fi
  kv "服务状态" "$(svc_state_text fail2ban)"
  fail2ban-client status 2>/dev/null || true
  printf '\n'
  fail2ban-client status sshd 2>/dev/null || warn "sshd jail 未启用"
}

security_fail2ban_install() {
  require_root
  confirm "安装 Fail2ban 并启用 sshd 防护（5 次失败封禁 1 小时）？" || return 0
  pkg_update || die "软件源更新失败"
  pkg_install fail2ban || die "Fail2ban 安装失败"

  local port backend
  port=$(ssh_current_port)
  [[ $port =~ ^[0-9]+$ ]] || port=22
  backend="auto"
  [[ ${INIT:-sysv} == systemd ]] && backend="systemd"

  mkdir -p /etc/fail2ban/jail.d
  cat >/etc/fail2ban/jail.d/sst-sshd.conf <<EOF
[DEFAULT]
backend = $backend
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = $port
EOF

  svc_enable fail2ban || die "Fail2ban 服务启动失败"
  svc_restart fail2ban || true
  sleep 1
  ok "Fail2ban 已安装并启用"
  fail2ban-client status sshd 2>/dev/null || warn "jail 状态暂不可读，请稍后重试"
}
