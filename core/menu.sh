#!/usr/bin/env bash
# 菜单层：模块注册、主菜单、子菜单与 CLI 分发

declare -A SST_MODULE_TITLE=() SST_MODULE_DESC=() SST_MODULE_ITEMS=()
declare -A SST_MODULE_GROUP=(
  [init]=0
  [system]=1 [network]=1 [tune]=1 [bench]=1
  [docker]=2 [apps]=2 [site]=2 [ai]=2
  [security]=3 [backup]=3 [tools]=3 [components]=3
  [settings]=4
)
SST_MODULE_GROUPS=(开荒与初始化 系统与网络 应用与部署 安全与运维 设置)
SST_MODULE_ORDER=()
SST_BANNER_KERNEL=''

sst_register_module() {
  local name=$1 title=$2 desc=$3
  [[ -n ${SST_MODULE_TITLE[$name]:-} ]] && return 0
  SST_MODULE_TITLE[$name]=$title
  SST_MODULE_DESC[$name]=$desc
  SST_MODULE_ORDER+=("$name")
}

sst_load_modules() {
  local f
  for f in "$SST_HOME"/modules/*.sh; do
    [[ -f $f ]] || continue
    # shellcheck disable=SC1090
    source "$f" || warn "模块加载失败：$f"
  done
  sst_sort_modules
}

# 主菜单顺序；未列出的模块按注册顺序追加
sst_sort_modules() {
  local -a preferred=(init system network tune bench docker apps site ai security backup tools components settings)
  local -a sorted=()
  local name
  for name in "${preferred[@]}"; do
    [[ -n ${SST_MODULE_TITLE[$name]:-} ]] && sorted+=("$name")
  done
  for name in "${SST_MODULE_ORDER[@]}"; do
    [[ " ${sorted[*]:-} " == *" $name "* ]] || sorted+=("$name")
  done
  SST_MODULE_ORDER=("${sorted[@]}")
}

sst_module_run() {
  local module=$1 action=$2
  shift 2
  local fn="${module}_${action}"
  if declare -F "$fn" >/dev/null 2>&1; then
    "$fn" "$@"
    return $?
  fi
  # 菜单项直接指向脚本市场中的第三方脚本
  if script_exists "$action"; then
    scripts_run "$action" "$@"
    return $?
  fi
  die "模块 $module 不支持操作：$action"
}

sst_module_group() {
  local group=${SST_MODULE_GROUP[$1]:-99}
  printf '%s' "${SST_MODULE_GROUPS[$group]:-其他}"
}

sst_banner_status() {
  local fw fw_label bbr
  fw=$(_fw_installed 2>/dev/null || printf 'none')
  case $fw in
    ufw) fw_label="UFW $(_ufw_state 2>/dev/null || printf '未知')" ;;
    firewalld) fw_label="firewalld $(svc_state_text firewalld 2>/dev/null || printf '未知')" ;;
    nftables|iptables) fw_label="$fw 已安装" ;;
    *) fw_label='防火墙未安装' ;;
  esac
  bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '未知')
  printf '%s · SSH %s · %s · BBR %s' \
    "$(hostname 2>/dev/null || printf '未知')" \
    "$(ssh_all_ports 2>/dev/null || printf '22')" \
    "$fw_label" "$bbr"
}

sst_print_banner() {
  [[ -n $SST_BANNER_KERNEL ]] || SST_BANNER_KERNEL=$(uname -r 2>/dev/null || printf '未知')
  local inner line1 line2 line3
  inner=$(( $(ui_frame_width) - 4 ))
  line1=$(ui_fit "SSH Tool Box · ${OS_NAME} · 内核 ${SST_BANNER_KERNEL}" "$inner")
  line2=$(ui_fit "$(sst_banner_status)" "$inner")
  line3=$(ui_fit "开荒向导 $(wizard_progress_meta)" "$inner")
  ui_panel "STBOX ${SST_VERSION}" "$line1" "$line2" "$line3"
}

sst_module_help() {
  local module=$1 action label
  section "${SST_MODULE_TITLE[$module]}"
  printf '%s\n' "${SST_MODULE_DESC[$module]}"
  hr
  printf '用法：st %s <操作> [参数]\n\n' "$module"
  while IFS='|' read -r action label; do
    [[ -n $action ]] || continue
    printf '  %s%s%s  %s\n' "$C_ACCENT" "$(ui_pad "$action" 18)" "$C_RESET" "$label"
  done <<<"${SST_MODULE_ITEMS[$module]}"
  printf '\n  不带参数执行 st 可进入交互菜单\n'
}

sst_help() {
  section "STBOX 使用说明"
  cat <<'EOF'
用法：st [--yes] [--no-color] [--plain] <模块> <操作> [参数...]

模块与常用命令：

  开荒与初始化
    init      开荒向导      st init | preflight | disk scan | basics | accounts | ssh | firewall | hardening | report

  系统与网络
    system    系统维护      st system info | memory | update | clean_deep | dns | timezone | hostname | rootpass | portscan | cron | shortcut
    network   网络测试      st network info | ip | speed [MB] | ping [host] | route [host] | dns | port
    tune      系统优化      st tune status | sysctl on/off | swap create/remove | ipv6 4/6 | mirror aliyun
    bench     性能测试      st bench memtest | diskbench [MB] | cpu | nodequality | tcpquality | scripts

  应用与部署
    docker    Docker 管理   st docker status | install | ps | exec | images | networks | volumes | compose | prune | uninstall
    apps      应用市场      st apps list | menu | install <名称> | remove <名称> | status <名称>
    site     建站环境      st site install | status | add | wordpress | proxy | ssl | list | remove | backup | uninstall
    ai        AI 工具       st ai status | list | install [工具] | version | update [工具] | remove [工具]
                             快捷安装：st ai claude | codex | gemini | qoder | codebuddy | ccswitch

  安全与运维
    security  安全与优化    st security status | firewall_status | firewall_allow <端口>
                             BBR/SSH/Fail2ban：st security bbr_on | ssh_status | fail2ban_install
    backup    备份与迁移    st backup list | create [路径...] | restore | schedule | remote
    tools     实用工具      st tools disk_mount | git | rclone | probes | panels | nodes | proxy | kernel | oracle | nat
    components 组件环境     st components list | install | install_all | remove | python | nodejs | golang | java | workspace

  设置
    settings  脚本设置      st settings version | update | config | log

示例：
  st system update
  st network speed 100
  st tune swap create
  st bench superbench
  st site install
  st site wordpress
  st app install npm
  st tools warp
  st components workspace
  st backup create /etc /var/www

说明：
  1. 涉及系统变更的操作需要 root 权限，会自动通过 sudo 重新执行。
  2. 自动化场景使用 --yes 跳过确认；危险操作仍会打印影响范围。
  3. bench/tools 中的第三方脚本会显示来源与风险，确认后才下载执行。
  4. 直接执行 st 进入交互菜单；--no-color 关闭彩色，--plain 同时关闭彩色与 Unicode 边框。
EOF
}

# 容器选择器：菜单打印到 stderr，选中的容器名输出到 stdout
docker_pick() {
  local -a names=()
  mapfile -t names < <(docker ps -a --format '{{.Names}}' 2>/dev/null)
  if [[ ${#names[@]} -eq 0 ]]; then
    warn "当前没有容器"
    return 1
  fi
  local i sel
  {
    printf '\n可用容器：\n'
    for i in "${!names[@]}"; do
      ui_menu_item "$((i + 1))" "${names[$i]}"
    done
    ui_menu_footer "取消"
    ui_read_choice "选择容器编号" || return 1
  } >&2
  sel=$UI_CHOICE
  if [[ ! $sel =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#names[@]} )); then
    warn "无效编号"
    return 1
  fi
  printf '%s\n' "${names[$((sel - 1))]}"
}

sst_wizard_checklist() {
  local i step status symbol color cell next total columns
  total=${#SST_WIZARD_STEPS[@]}
  next=$(wizard_next_step)
  columns=4
  (( UI_WIDTH < 50 )) && columns=2
  (( UI_WIDTH < 26 )) && columns=1
  printf '\n  '
  for (( i = 0; i < total; i++ )); do
    step=${SST_WIZARD_STEPS[$i]}
    status=$(wizard_step_status "$step")
    case $status in
      done) symbol=$UI_SYM_OK color=$C_OK ;;
      skipped) symbol=$UI_SYM_WARN color=$C_WARN ;;
      in_progress) symbol=$UI_SYM_ARROW color=$C_ACCENT ;;
      *)
        if [[ $step == "$next" ]]; then
          symbol=$UI_SYM_ARROW color=$C_ACCENT
        else
          symbol=$UI_SYM_BULLET color=$C_DIM
        fi
        ;;
    esac
    cell=$(ui_pad "$symbol $(wizard_step_short "$step")" 9)
    printf '%s%s%s' "$color" "$cell" "$C_RESET"
    if (( (i + 1) % columns == 0 )); then
      printf '\n'
      (( i + 1 < total )) && printf '  '
    else
      printf '  '
    fi
  done
  (( total % columns != 0 )) && printf '\n'
}

sst_module_header() {
  local module=$1
  if [[ $module == init ]]; then
    sst_wizard_checklist
  else
    printf '  %s%s%s\n' "$C_DIM" "${SST_MODULE_DESC[$module]}" "$C_RESET"
  fi
}

sst_module_menu() {
  local module=$1 title=${SST_MODULE_TITLE[$1]}
  local choice idx action label i meta
  local -a actions=() labels=()

  while true; do
    meta=''
    [[ $module == init ]] && meta=$(wizard_progress_meta)
    section "$title" "$meta"
    sst_module_header "$module"
    hr
    actions=() labels=()
    while IFS='|' read -r action label; do
      [[ -n $action ]] || continue
      actions+=("$action")
      labels+=("$label")
    done <<<"${SST_MODULE_ITEMS[$module]}"

    for i in "${!actions[@]}"; do
      ui_menu_item "$((i + 1))" "${labels[$i]}"
    done
    if (( UI_WIDTH >= 48 )); then
      printf '\n  %s0%s 返回   %sh%s 帮助   %s输入操作名可直接执行%s\n\n' \
        "$C_ACCENT" "$C_RESET" "$C_ACCENT" "$C_RESET" "$C_DIM" "$C_RESET"
    else
      printf '\n  %s0%s 返回   %sh%s 帮助\n\n' \
        "$C_ACCENT" "$C_RESET" "$C_ACCENT" "$C_RESET"
    fi

    read -r -p "$(ui_prompt_text '请选择')" choice || break
    case $choice in
      0|q|back|exit) break ;;
      [0-9]|[0-9][0-9])
        idx=$((choice - 1))
        if (( idx >= 0 && idx < ${#actions[@]} )); then
          sst_module_run "$module" "${actions[$idx]}"
          pause
        else
          warn "无效编号：$choice"
        fi
        ;;
      *)
        if declare -F "${module}_${choice}" >/dev/null 2>&1; then
          sst_module_run "$module" "$choice"
          pause
        else
          warn "未知操作：$choice"
        fi
        ;;
    esac
  done
}

sst_main_menu() {
  local choice idx module group current_group
  local -a mods=()

  while true; do
    sst_print_banner
    section "主菜单"
    mods=("${SST_MODULE_ORDER[@]}")
    current_group=-1
    for idx in "${!mods[@]}"; do
      module=${mods[$idx]}
      group=${SST_MODULE_GROUP[$module]:-99}
      if (( group != current_group )); then
        ui_group "$(sst_module_group "$module")"
        current_group=$group
      fi
      ui_menu_item "$((idx + 1))" "${SST_MODULE_TITLE[$module]}" "${SST_MODULE_DESC[$module]}"
    done
    if (( UI_WIDTH >= 48 )); then
      printf '\n  %s0%s 退出   %sh%s 帮助   %s输入模块名可直接进入%s\n\n' \
        "$C_ACCENT" "$C_RESET" "$C_ACCENT" "$C_RESET" "$C_DIM" "$C_RESET"
    else
      printf '\n  %s0%s 退出   %sh%s 帮助\n\n' \
        "$C_ACCENT" "$C_RESET" "$C_ACCENT" "$C_RESET"
    fi

    read -r -p "$(ui_prompt_text '请选择')" choice || break
    case $choice in
      0|q|quit|exit) break ;;
      h|help) sst_help; pause ;;
      '') continue ;;
      [0-9]|[0-9][0-9])
        idx=$((choice - 1))
        if (( idx >= 0 && idx < ${#mods[@]} )); then
          sst_module_menu "${mods[$idx]}"
        else
          warn "无效编号：$choice"
        fi
        ;;
      *)
        if [[ -n ${SST_MODULE_TITLE[$choice]:-} ]]; then
          sst_module_menu "$choice"
        else
          warn "未知模块：$choice"
        fi
        ;;
    esac
  done
}

sst_dispatch() {
  SST_ARGS=("$@")

  if [[ $# -eq 0 ]]; then
    require_root
    sst_main_menu
    return 0
  fi

  local cmd=$1
  shift

  case $cmd in
    version|--version|-v) version_info; return 0 ;;
    help|--help|-h) sst_help; return 0 ;;
  esac

  case $cmd in
    app) cmd=apps ;;
    net) cmd=network ;;
    sec) cmd=security ;;
  esac

  [[ -n ${SST_MODULE_TITLE[$cmd]:-} ]] || die "未知模块：$cmd（执行 st help 查看用法）"
  if [[ $# -eq 0 ]]; then
    sst_module_help "$cmd"
    return 0
  fi

  local action=$1
  shift
  sst_module_run "$cmd" "$action" "$@"
}
