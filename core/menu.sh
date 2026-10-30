#!/usr/bin/env bash
# 菜单层：模块注册、主菜单、子菜单与 CLI 分发

declare -A SST_MODULE_TITLE=() SST_MODULE_DESC=() SST_MODULE_ITEMS=()
SST_MODULE_ORDER=()

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
  local -a preferred=(init system network tune bench docker apps site tools components security backup settings)
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

sst_print_banner() {
  printf '\n%s%s%s\n' "$C_BOLD$C_CYAN" "  STBOX · SSH Tool Box · 服务器工具箱" "$C_RESET"
  printf '  %s版本 %s · %s · 内核 %s%s\n' "$C_DIM" "$SST_VERSION" "$OS_NAME" "$(uname -r)" "$C_RESET"
}

sst_module_help() {
  local module=$1 action label
  section "${SST_MODULE_TITLE[$module]}"
  printf '%s\n' "${SST_MODULE_DESC[$module]}"
  hr
  printf '用法：st %s <操作> [参数]\n\n' "$module"
  while IFS='|' read -r action label; do
    [[ -n $action ]] || continue
    printf '  %-18s %s\n' "$action" "$label"
  done <<<"${SST_MODULE_ITEMS[$module]}"
  printf '\n  不带参数执行 st 可进入交互菜单\n'
}

sst_help() {
  section "STBOX 使用说明"
  cat <<'EOF'
用法：st [--yes] [--no-color] <模块> <操作> [参数...]

模块与常用命令：
  init      开荒向导      st init | preflight | disk scan | basics | status | report
  system    系统维护      st system info | update | clean_deep | dns | timezone | hostname | rootpass | portscan | cron | shortcut
  network   网络测试      st network info | ip | speed [MB] | ping [host] | route [host] | dns | port
  tune      系统优化      st tune status | sysctl on/off | swap create/remove | ipv6 4/6 | mirror aliyun
  bench     性能测试      st bench memtest | diskbench [MB] | cpu | scripts | superbench
  docker    Docker 管理   st docker status | install | ps | exec | images | networks | volumes | prune | uninstall
  apps      应用市场      st apps list | menu | install <名称> | remove <名称> | status <名称>
  site     建站环境      st site install | status | add | wordpress | proxy | ssl | list | remove | backup | uninstall
  tools     实用工具      st tools disk_mount | git | rclone | fclone | warp | bbr3 | nodes | panels | oracle | nat
  components 组件环境     st components list | install | install_all | remove | python | nodejs | golang | java | workspace
  security  安全与优化    st security status | firewall_status | firewall_allow <端口>
            BBR/SSH/Fail2ban：st security bbr_on | ssh_status | fail2ban_install
  backup    备份与迁移    st backup list | create [路径...] | restore | schedule | remote
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
  4. 直接执行 st 进入交互菜单；--no-color 关闭彩色输出。
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
      printf '  %2d) %s\n' "$((i + 1))" "${names[$i]}"
    done
    printf '\n'
  } >&2
  read -r -p "选择容器编号: " sel || return 1
  if [[ ! $sel =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#names[@]} )); then
    warn "无效编号"
    return 1
  fi
  printf '%s\n' "${names[$((sel - 1))]}"
}

sst_module_menu() {
  local module=$1 title=${SST_MODULE_TITLE[$1]}
  local choice idx action label i
  local -a actions=() labels=()

  while true; do
    section "$title"
    actions=() labels=()
    while IFS='|' read -r action label; do
      [[ -n $action ]] || continue
      actions+=("$action")
      labels+=("$label")
    done <<<"${SST_MODULE_ITEMS[$module]}"

    for i in "${!actions[@]}"; do
      printf '  %s%2d%s) %s\n' "$C_GREEN" "$((i + 1))" "$C_RESET" "${labels[$i]}"
    done
    printf '  %s 0%s) 返回\n\n' "$C_GREEN" "$C_RESET"

    read -r -p "请选择: " choice || break
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
  local choice idx module
  local -a mods=()

  while true; do
    sst_print_banner
    section "主菜单"
    mods=("${SST_MODULE_ORDER[@]}")
    for idx in "${!mods[@]}"; do
      module=${mods[$idx]}
      printf '  %s%2d%s) %-8s %s%s%s\n' \
        "$C_GREEN" "$((idx + 1))" "$C_RESET" \
        "${SST_MODULE_TITLE[$module]}" \
        "$C_DIM" "${SST_MODULE_DESC[$module]}" "$C_RESET"
    done
    printf '  %s 0%s) 退出\n  %s h%s) 帮助\n\n' "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET"

    read -r -p "请输入编号或模块名: " choice || break
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
