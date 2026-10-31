#!/usr/bin/env bash
# 应用插件框架：扫描 apps/ 与 plugins/apps/，注册元数据并提供 Compose 运行助手。
# 插件目录结构：<name>/app.conf + <name>/app.sh
# app.sh 需提供 app_<name>_install / app_<name>_remove（status 可选）。

declare -A SST_APP_TITLE=() SST_APP_DESC=() SST_APP_CATEGORY=()
declare -A SST_APP_PORT=() SST_APP_URL=() SST_APP_DIR=()
SST_APP_ORDER=()

sst_load_apps() {
  SST_APP_ORDER=()
  SST_APP_TITLE=() SST_APP_DESC=() SST_APP_CATEGORY=()
  SST_APP_PORT=() SST_APP_URL=() SST_APP_DIR=()

  local root dir name
  for root in "$SST_HOME/apps" "$SST_HOME/plugins/apps"; do
    [[ -d $root ]] || continue
    for dir in "$root"/*/; do
      [[ -f ${dir}app.conf ]] || continue
      name=$(basename "$dir")
      [[ -n ${SST_APP_TITLE[$name]:-} ]] && continue

      APP_TITLE='' APP_DESC='' APP_CATEGORY='' APP_PORT='' APP_URL=''
      # shellcheck disable=SC1090
      source "${dir}app.conf" || { warn "应用配置加载失败：${dir}app.conf"; continue; }

      SST_APP_TITLE[$name]=${APP_TITLE:-$name}
      SST_APP_DESC[$name]=${APP_DESC:-}
      SST_APP_CATEGORY[$name]=${APP_CATEGORY:-其他}
      SST_APP_PORT[$name]=${APP_PORT:-}
      SST_APP_URL[$name]=${APP_URL:-}
      SST_APP_DIR[$name]=$dir
      SST_APP_ORDER+=("$name")

      if [[ -f ${dir}app.sh ]]; then
        # shellcheck disable=SC1090
        source "${dir}app.sh" || warn "应用脚本加载失败：${dir}app.sh"
      fi
    done
  done
}

app_exists() {
  [[ -n ${SST_APP_TITLE[${1:-}]:-} ]]
}

app_call() {
  local name=$1 action=$2
  shift 2
  local safe=${name//-/_}
  local fn="app_${safe}_${action}"
  declare -F "$fn" >/dev/null 2>&1 || die "应用 $name 不支持操作：$action"
  "$fn" "$@"
}

app_data_dir() { printf '%s/apps/%s' "$SST_DATA_DIR" "$1"; }

app_installed() {
  [[ -f "$(app_data_dir "${1:-}")/docker-compose.yml" ]]
}

compose_run() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif have docker-compose; then
    docker-compose "$@"
  else
    return 1
  fi
}

# 从标准输入读取 Compose 内容并启动
app_compose_up() {
  local name=$1 dir
  dir=$(app_data_dir "$name")
  mkdir -p "$dir" || return 1
  cat >"$dir/docker-compose.yml"
  compose_run -f "$dir/docker-compose.yml" up -d
}

app_compose_down() {
  local name=$1 dir
  dir=$(app_data_dir "$name")
  [[ -f $dir/docker-compose.yml ]] || return 0
  compose_run -f "$dir/docker-compose.yml" down --remove-orphans || return 1
  rm -f "$dir/docker-compose.yml"
}

app_compose_ps() {
  local name=$1 dir
  dir=$(app_data_dir "$name")
  [[ -f $dir/docker-compose.yml ]] || { info "应用 $name 未部署"; return 0; }
  compose_run -f "$dir/docker-compose.yml" ps
}

app_access_url() {
  local name=$1 url=${SST_APP_URL[${1:-}]:-}
  [[ -n $url ]] || return 0
  printf '%s\n' "${url//IP/$(get_public_ip)}"
}

# Web IDE 类应用的安全提示（code-server / OpenVSCode 等）
app_webide_notice() {
  local port=$1
  warn "Web IDE 以 HTTP 暴露 $port 端口，直接对公网开放存在被接管风险。"
  info "建议用 SSH 隧道访问：ssh -L $port:127.0.0.1:$port 用户@服务器"
  info "如需公网访问，请通过 Nginx/Caddy 反向代理并启用 HTTPS 与访问认证。"
}
