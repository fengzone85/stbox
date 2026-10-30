#!/usr/bin/env bash
# 模块：应用市场（基于 Docker Compose 的应用插件）

sst_register_module apps "应用市场" "一键部署常用应用"
SST_MODULE_ITEMS[apps]=$'list|应用清单\nmenu|安装与管理\nhelp|插件开发说明'

app_status_mark() {
  if app_installed "$1"; then printf '已部署'; else printf '未部署'; fi
}

apps_list() {
  section "应用清单"
  if [[ ${#SST_APP_ORDER[@]} -eq 0 ]]; then
    warn "未发现应用，检查 apps/ 与 plugins/apps/ 目录"
    return 1
  fi
  printf '  %-14s %-10s %-8s %-8s %s\n' "名称" "分类" "端口" "状态" "说明"
  hr
  local name
  for name in "${SST_APP_ORDER[@]}"; do
    printf '  %-14s %-10s %-8s %-8s %s\n' \
      "$name" "${SST_APP_CATEGORY[$name]}" "${SST_APP_PORT[$name]:--}" \
      "$(app_status_mark "$name")" "${SST_APP_DESC[$name]}"
  done
}

apps_status() {
  local name=${1:-}
  [[ -n $name ]] || die "用法：st app status <名称>"
  app_exists "$name" || die "未知应用：$name"
  section "${SST_APP_TITLE[$name]} 状态"
  if declare -F "app_${name}_status" >/dev/null 2>&1; then
    app_call "$name" status
  else
    app_compose_ps "$name"
  fi
}

apps_install() {
  local name=${1:-}
  if [[ -z $name ]]; then
    die "用法：st app install <名称>（可用：${SST_APP_ORDER[*]}）"
  fi
  app_exists "$name" || die "未知应用：$name"
  require_root
  docker_require || die "应用部署依赖 Docker，请先安装并启动 Docker"
  app_call "$name" install
}

apps_remove() {
  local name=${1:-}
  [[ -n $name ]] || die "用法：st app remove <名称>"
  app_exists "$name" || die "未知应用：$name"
  require_root
  confirm "停止并移除应用 $name 的容器（数据卷默认保留）？" || return 0
  app_call "$name" remove
  ok "已移除应用：$name"
}

apps_help() {
  section "应用插件开发说明"
  cat <<'EOF'
插件目录：apps/<名称>/ 或 plugins/apps/<名称>/
  app.conf  元数据（shell 变量）
    APP_TITLE="显示名称"
    APP_DESC="功能说明"
    APP_CATEGORY="分类"
    APP_PORT="端口"
    APP_URL="访问地址，IP 会被替换为公网 IP"
  app.sh    生命周期函数
    app_<名称>_install()  安装/重新部署，可调用 app_compose_up <名称> 读取 Compose YAML
    app_<名称>_remove()   停止并移除
    app_<名称>_status()   可选，缺省使用 docker compose ps

示例：
  app_compose_up demo <<'YAML'
  services:
    demo:
      image: nginx:alpine
      ports:
        - "8080:80"
  YAML

放入 plugins/apps/ 后无需修改框架，重新执行 st 即自动注册。
EOF
}

app_manage() {
  local name=$1 choice
  while true; do
    section "${SST_APP_TITLE[$name]}"
    kv "说明" "${SST_APP_DESC[$name]}"
    kv "分类" "${SST_APP_CATEGORY[$name]}"
    kv "端口" "${SST_APP_PORT[$name]:--}"
    kv "访问" "$(app_access_url "$name")"
    kv "状态" "$(app_status_mark "$name")"
    printf '\n'
    printf '  %s1%s) 安装 / 重新部署\n' "$C_GREEN" "$C_RESET"
    printf '  %s2%s) 停止并移除容器\n' "$C_GREEN" "$C_RESET"
    printf '  %s3%s) 查看运行状态\n' "$C_GREEN" "$C_RESET"
    printf '  %s0%s) 返回\n\n' "$C_GREEN" "$C_RESET"
    read -r -p "请选择: " choice || break
    case $choice in
      1) apps_install "$name"; pause ;;
      2) apps_remove "$name"; pause ;;
      3) apps_status "$name"; pause ;;
      0|q|back) break ;;
      *) warn "无效选项：$choice" ;;
    esac
  done
}

apps_menu() {
  local -a names=("${SST_APP_ORDER[@]}")
  local choice idx name title
  if [[ ${#names[@]} -eq 0 ]]; then
    warn "没有可用应用"
    return 1
  fi

  while true; do
    section "应用市场"
    for idx in "${!names[@]}"; do
      name=${names[$idx]}
      title=${SST_APP_TITLE[$name]}
      printf '  %s%2d%s) %-14s %-10s %-8s %s\n' \
        "$C_GREEN" "$((idx + 1))" "$C_RESET" \
        "$title" "${SST_APP_CATEGORY[$name]}" \
        "$(app_status_mark "$name")" "${SST_APP_DESC[$name]}"
    done
    printf '  %s 0%s) 返回\n\n' "$C_GREEN" "$C_RESET"
    read -r -p "请选择应用: " choice || break
    case $choice in
      0|q|back) break ;;
      [0-9]|[0-9][0-9])
        idx=$((choice - 1))
        if (( idx >= 0 && idx < ${#names[@]} )); then
          app_manage "${names[$idx]}"
        else
          warn "无效编号：$choice"
        fi
        ;;
      *)
        if app_exists "$choice"; then
          app_manage "$choice"
        else
          warn "未知应用：$choice"
        fi
        ;;
    esac
  done
}
