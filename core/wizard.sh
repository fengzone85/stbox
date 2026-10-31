#!/usr/bin/env bash
# 开荒向导状态与报告

SST_WIZARD_DIR="$SST_DATA_DIR/init"
SST_WIZARD_STATE="$SST_WIZARD_DIR/state.conf"
SST_WIZARD_STEPS=(preflight disk basics accounts ssh firewall hardening report)

wizard_init() {
  mkdir -p "$SST_WIZARD_DIR" 2>/dev/null || true
  chmod 700 "$SST_WIZARD_DIR" 2>/dev/null || true
  if [[ ! -f $SST_WIZARD_STATE ]]; then
    {
      printf 'VERSION=2\n'
      printf 'STARTED_AT=%s\n' "$(date '+%F %T')"
      for s in "${SST_WIZARD_STEPS[@]}"; do
        printf 'STEP_%s=pending\n' "$s"
      done
    } >"$SST_WIZARD_STATE"
    chmod 600 "$SST_WIZARD_STATE" 2>/dev/null || true
  else
    local s
    for s in "${SST_WIZARD_STEPS[@]}"; do
      grep -qE "^STEP_${s}=" "$SST_WIZARD_STATE" 2>/dev/null || printf 'STEP_%s=pending\n' "$s" >>"$SST_WIZARD_STATE"
    done
    grep -qE '^VERSION=' "$SST_WIZARD_STATE" || printf 'VERSION=2\n' >>"$SST_WIZARD_STATE"
  fi
}

wizard_get() {
  local key=$1 default=${2:-}
  [[ -r $SST_WIZARD_STATE ]] || { printf '%s\n' "$default"; return 0; }
  local value
  value=$(grep -E "^${key}=" "$SST_WIZARD_STATE" 2>/dev/null | tail -n 1 | cut -d= -f2-)
  printf '%s\n' "${value:-$default}"
}

wizard_set() {
  local key=$1 value=$2 tmp
  [[ $key =~ ^[A-Za-z0-9_]+$ ]] || return 1
  wizard_init
  tmp=$(mktemp)
  grep -vE "^${key}=" "$SST_WIZARD_STATE" >"$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv "$tmp" "$SST_WIZARD_STATE"
  chmod 600 "$SST_WIZARD_STATE" 2>/dev/null || true
}

wizard_mark() {
  local step=$1 status=${2:-done}
  wizard_set "STEP_${step}" "$status"
  wizard_set "STEP_${step}_AT" "$(date '+%F %T')"
}

wizard_step_status() {
  wizard_get "STEP_${1}" pending
}

wizard_step_label() {
  case $1 in
    preflight) printf '服务器预检' ;;
    disk) printf '磁盘检测与挂载' ;;
    basics) printf '基础信息' ;;
    accounts) printf '账户设置' ;;
    ssh) printf 'SSH 安全' ;;
    firewall) printf '防火墙与防护' ;;
    hardening) printf '系统加固' ;;
    report) printf '验收报告' ;;
    *) printf '%s' "$1" ;;
  esac
}

wizard_step_short() {
  case $1 in
    preflight) printf '预检' ;;
    disk) printf '磁盘' ;;
    basics) printf '基础' ;;
    accounts) printf '账户' ;;
    ssh) printf 'SSH' ;;
    firewall) printf '防火墙' ;;
    hardening) printf '加固' ;;
    report) printf '报告' ;;
    *) printf '%s' "$1" ;;
  esac
}

wizard_step_state_text() {
  case $1 in
    done) printf '已完成' ;;
    skipped) printf '已跳过' ;;
    in_progress) printf '进行中' ;;
    *) printf '待执行' ;;
  esac
}

wizard_done_count() {
  local s count=0
  for s in "${SST_WIZARD_STEPS[@]}"; do
    [[ $(wizard_step_status "$s") == done ]] && count=$((count + 1))
  done
  printf '%d' "$count"
}

wizard_next_step() {
  local s status
  for s in "${SST_WIZARD_STEPS[@]}"; do
    status=$(wizard_step_status "$s")
    [[ $status == done || $status == skipped ]] && continue
    printf '%s' "$s"
    return 0
  done
}

wizard_progress_meta() {
  local total done next
  total=${#SST_WIZARD_STEPS[@]}
  done=$(wizard_done_count)
  next=$(wizard_next_step)
  if (( done >= total )); then
    printf '全部完成 · 可生成报告'
  elif [[ -n $next ]]; then
    printf '%d/%d 完成 · 下一步：%s' "$done" "$total" "$(wizard_step_label "$next")"
  else
    printf '%d/%d 完成 · 可生成报告' "$done" "$total"
  fi
}

wizard_status_table() {
  local s status symbol color text
  section "开荒进度"
  for s in "${SST_WIZARD_STEPS[@]}"; do
    status=$(wizard_step_status "$s")
    case $status in
      done) symbol=$UI_SYM_OK color=$C_OK ;;
      skipped) symbol=$UI_SYM_WARN color=$C_WARN ;;
      in_progress) symbol=$UI_SYM_ARROW color=$C_ACCENT ;;
      *) symbol=$UI_SYM_BULLET color=$C_DIM ;;
    esac
    text=$(wizard_step_state_text "$status")
    printf '  %s%s%s %s%s%s\n' "$color" "$symbol" "$C_RESET" \
      "$(ui_pad "$(wizard_step_label "$s")" 18)" "$C_DIM" "$text$C_RESET"
  done
  [[ -n $(wizard_get HOSTNAME) ]] && kv "主机名" "$(wizard_get HOSTNAME)"
  [[ -n $(wizard_get TIMEZONE) ]] && kv "时区" "$(wizard_get TIMEZONE)"
  [[ -n $(wizard_get DNS) ]] && kv "DNS" "$(wizard_get DNS)"
  [[ -n $(wizard_get DATA_DISKS) ]] && kv "数据盘" "$(wizard_get DATA_DISKS)"
  [[ -n $(wizard_get ADMIN_USER) ]] && kv "管理用户" "$(wizard_get ADMIN_USER)"
  [[ -n $(wizard_get SSH_NEW_PORT) ]] && kv "SSH 新端口" "$(wizard_get SSH_NEW_PORT)"
  [[ -n $(wizard_get SSH_STATUS) ]] && kv "SSH 状态" "$(wizard_get SSH_STATUS)"
  [[ -n $(wizard_get FIREWALL) ]] && kv "防火墙" "$(wizard_get FIREWALL)"
  [[ -n $(wizard_get SECURITY_SYSCTL) ]] && kv "安全参数" "$(wizard_get SECURITY_SYSCTL)"
  [[ -n $(wizard_get SWAP) ]] && kv "SWAP" "$(wizard_get SWAP)"
  [[ -n $(wizard_get BBR) ]] && kv "BBR" "$(wizard_get BBR)"
  return 0
}

wizard_report_write() {
  require_root
  wizard_init
  local file ts
  ts=$(date +%Y%m%d-%H%M%S)
  file="$SST_WIZARD_DIR/report-$ts.md"
  mkdir -p "$SST_WIZARD_DIR"
  {
    printf '# STBOX 开荒报告\n\n'
    printf '%s\n' "- 生成时间：$(date '+%F %T')"
    printf '%s\n' "- 主机名：$(hostname)"
    printf '%s\n' "- 系统：$OS_NAME"
    printf '%s\n' "- 内核：$(uname -r)"
    printf '%s\n' "- 架构：$ARCH"
    printf '%s\n\n' "- 公网 IP：$(get_public_ip)"
    printf '## 向导进度\n\n'
    printf '| 步骤 | 状态 |\n|---|---|\n'
    local s
    for s in "${SST_WIZARD_STEPS[@]}"; do
      printf '| %s | %s |\n' "$(wizard_step_label "$s")" "$(wizard_step_status "$s")"
    done
    printf '\n## 当前配置\n\n'
    printf '| 项目 | 值 |\n|---|---|\n'
    printf '| 时区 | %s |\n' "$(timedatectl show -p Timezone --value 2>/dev/null || date +%Z)"
    printf '| DNS | %s |\n' "$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
    printf '| SSH 端口 | %s |\n' "$(ssh_all_ports 2>/dev/null || ssh_current_port 2>/dev/null || echo 22)"
    printf '| root 登录 | %s |\n' "$(ssh_cfg_get PermitRootLogin 2>/dev/null || echo 未知)"
    printf '| 密码登录 | %s |\n' "$(ssh_cfg_get PasswordAuthentication 2>/dev/null || echo 未知)"
    printf '| 管理用户 | %s |\n' "$(wizard_get ADMIN_USER 未创建)"
    printf '| 防火墙 | %s |\n' "$(_fw_installed 2>/dev/null || echo 未知)"
    printf '| Fail2ban | %s |\n' "$(have fail2ban-client && svc_state_text fail2ban || echo 未安装)"
    printf '| 安全参数 | %s |\n' "$(wizard_get SECURITY_SYSCTL 未应用)"
    printf '| SWAP | %s |\n' "$(wizard_get SWAP 未创建)"
    printf '| BBR | %s |\n' "$(wizard_get BBR $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知))"
    printf '| TCP 算法 | %s |\n' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)"
    printf '| 数据盘 | %s |\n' "$(wizard_get DATA_DISKS 未挂载)"
    printf '\n## 后续建议\n\n'
    if [[ -n $(wizard_get SSH_NEW_PORT) ]]; then
      printf '1. 用新终端验证：ssh -p %s 用户@%s\n' "$(wizard_get SSH_NEW_PORT)" "$(get_public_ip)"
      printf '2. 确认可登录后执行：st init ssh keep\n'
    else
      printf '1. 用新终端验证 SSH 可登录后再关闭旧端口或会话。\n'
    fi
    printf '3. 按需执行：st security ssh_status / st security firewall_status。\n'
    printf '4. 定期运行：st backup create /etc /var/www。\n'
  } >"$file"
  chmod 600 "$file"
  printf '%s\n' "$file"
}
