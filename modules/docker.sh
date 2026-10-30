#!/usr/bin/env bash
# 模块：Docker 管理

sst_register_module docker "Docker" "安装 容器 日志 清理"
SST_MODULE_ITEMS[docker]=$'status|运行状态\ninstall|安装 Docker\nps|容器列表\nlogs|查看日志\nrestart|重启容器\nstart|启动容器\nstop|停止容器\nexec|进入容器\nimages|镜像管理\nnetworks|网络管理\nvolumes|卷管理\nprune|清理空间\ncompose|Compose 项目\nuninstall|卸载 Docker'

docker_require() {
  if ! have docker; then
    warn "未检测到 Docker"
    if [[ -t 0 ]] && confirm "是否现在安装 Docker？"; then
      docker_install || return 1
    else
      return 1
    fi
  fi
  if ! docker info >/dev/null 2>&1; then
    warn "Docker 守护进程未运行，尝试启动…"
    require_root
    svc_enable docker || true
    sleep 2
    if ! docker info >/dev/null 2>&1; then
      err "Docker 无法启动，请检查：systemctl status docker"
      return 1
    fi
  fi
  return 0
}

docker_install() {
  require_root
  if have docker; then
    info "已安装：$(docker --version 2>/dev/null)"
    confirm "重新安装/升级 Docker？" || return 0
  else
    confirm "将从 get.docker.com 拉取并执行官方安装脚本，继续？" || return 0
  fi

  ensure_tool curl curl || return 1
  local mirror='' installer
  if confirm "使用阿里云镜像源加速下载？"; then
    mirror="https://mirrors.aliyun.com/docker-ce"
  fi

  info "开始安装 Docker…"
  installer=$(mktemp)
  if ! curl -fsSL --connect-timeout 10 --max-time 300 -o "$installer" https://get.docker.com; then
    rm -f "$installer"
    die "下载 Docker 安装脚本失败"
  fi
  if [[ -n $mirror ]]; then
    ( export DOWNLOAD_URL="$mirror"; bash "$installer" ) || { rm -f "$installer"; die "Docker 安装失败"; }
  else
    bash "$installer" || { rm -f "$installer"; die "Docker 安装失败"; }
  fi
  rm -f "$installer"

  svc_enable docker || warn "Docker 服务启用失败，请手动检查"
  docker --version 2>/dev/null
  ok "Docker 安装完成"
  info "非 root 用户可使用：usermod -aG docker <用户名>"
}

docker_status() {
  section "Docker 状态"
  if ! have docker; then
    warn "未安装 Docker，可执行：st docker install"
    return 1
  fi
  kv "版本" "$(docker --version 2>/dev/null | sed 's/^Docker version //;s/,.*//')"
  if docker compose version >/dev/null 2>&1; then
    kv "Compose" "$(docker compose version --short 2>/dev/null)"
  elif have docker-compose; then
    kv "Compose" "$(docker-compose version --short 2>/dev/null || echo 已安装)"
  else
    kv "Compose" "未安装插件"
  fi
  kv "服务状态" "$(svc_active docker && echo 运行中 || echo 未运行)"

  if ! docker info >/dev/null 2>&1; then
    warn "Docker 守护进程不可用，运行状态信息跳过"
    return 1
  fi
  local running total images
  running=$(docker ps -q 2>/dev/null | wc -l)
  total=$(docker ps -aq 2>/dev/null | wc -l)
  images=$(docker images -q 2>/dev/null | wc -l)
  kv "容器" "运行 ${running} / 共 ${total}"
  kv "镜像" "$images"
  printf '\n'
  docker system df 2>/dev/null || true
}

docker_ps() {
  docker_require || return 1
  section "容器列表"
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
}

docker_logs() {
  docker_require || return 1
  local name=${1:-} lines=${2:-100}
  if [[ -z $name ]]; then
    name=$(docker_pick) || return 0
  fi
  docker logs --tail "$lines" "$name" 2>&1
  if [[ -t 0 ]] && confirm "持续跟踪日志（Ctrl+C 退出）？"; then
    docker logs -f --tail 0 "$name" 2>&1
  fi
}

docker_restart() {
  require_root
  docker_require || return 1
  local name=${1:-}
  [[ -n $name ]] || name=$(docker_pick) || return 0
  docker restart "$name" && ok "已重启容器：$name"
}

docker_start() {
  require_root
  docker_require || return 1
  local name=${1:-}
  [[ -n $name ]] || name=$(docker_pick) || return 0
  docker start "$name" && ok "已启动容器：$name"
}

docker_stop() {
  require_root
  docker_require || return 1
  local name=${1:-}
  [[ -n $name ]] || name=$(docker_pick) || return 0
  docker stop "$name" && ok "已停止容器：$name"
}

docker_prune() {
  require_root
  docker_require || return 1
  section "当前空间占用"
  docker system df 2>/dev/null || true

  confirm "清理已停止容器、未使用网络与悬空镜像？" || return 0
  docker system prune -f || warn "基础清理未完成"
  if confirm "同时清理所有未被使用的镜像（-a）？"; then
    docker system prune -a -f || warn "镜像清理未完成"
  fi
  if [[ ${SST_YES:-0} -ne 1 ]] && [[ -t 0 ]] \
    && confirm "清理未被使用的数据卷（会删除卷内数据！）？"; then
    docker volume prune -f || warn "卷清理未完成"
  fi
  section "清理后空间占用"
  docker system df 2>/dev/null || true
}

docker_compose() {
  docker_require || return 1
  section "Compose 项目"
  if docker compose version >/dev/null 2>&1; then
    docker compose ls 2>/dev/null || true
  elif have docker-compose; then
    docker ps -a --filter 'label=com.docker.compose.project' \
      --format 'table {{.Label "com.docker.compose.project"}}\t{{.Names}}\t{{.Status}}' 2>/dev/null
  else
    warn "未安装 Docker Compose，可参考：apt install docker-compose-plugin"
  fi
}

docker_exec() {
  require_root
  docker_require || return 1
  local name=${1:-}
  [[ -n $name ]] || name=$(docker_pick) || return 0
  docker exec -it "$name" sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'
}

docker_images() {
  require_root
  docker_require || return 1
  section "镜像列表"
  docker images
  local -a ids=() labels=()
  while IFS=' ' read -r repo id size; do
    [[ -n $id ]] || continue
    ids+=("$id")
    labels+=("$repo $size")
  done < <(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' 2>/dev/null)
  [[ ${#ids[@]} -gt 0 ]] || { info "没有镜像"; return 0; }

  local i sel
  printf '\n'
  for i in "${!ids[@]}"; do printf '  %2d) %s\n' "$((i + 1))" "${labels[$i]}"; done
  read -r -p "要删除的镜像编号（0 返回）: " sel || return 0
  [[ $sel == 0 ]] && return 0
  [[ $sel =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#ids[@]} )) || die "无效编号"
  confirm "删除镜像 ${labels[$((sel - 1))]}？" || return 0
  docker rmi "${ids[$((sel - 1))]}"
}

docker_networks() {
  require_root
  docker_require || return 1
  section "网络列表"
  docker network ls
  local -a names=()
  mapfile -t names < <(docker network ls --format '{{.Name}}' 2>/dev/null)
  local i sel
  printf '\n'
  for i in "${!names[@]}"; do printf '  %2d) %s\n' "$((i + 1))" "${names[$i]}"; done
  read -r -p "要删除的网络编号（0 返回）: " sel || return 0
  [[ $sel == 0 ]] && return 0
  [[ $sel =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#names[@]} )) || die "无效编号"
  local name=${names[$((sel - 1))]}
  case $name in
    bridge|host|none) die "内置网络 $name 不能删除" ;;
  esac
  confirm "删除网络 $name？" || return 0
  docker network rm "$name"
}

docker_volumes() {
  require_root
  docker_require || return 1
  section "数据卷列表"
  docker volume ls
  local -a names=()
  mapfile -t names < <(docker volume ls --format '{{.Name}}' 2>/dev/null)
  local i sel
  printf '\n'
  for i in "${!names[@]}"; do printf '  %2d) %s\n' "$((i + 1))" "${names[$i]}"; done
  read -r -p "要删除的卷编号（0 返回）: " sel || return 0
  [[ $sel == 0 ]] && return 0
  [[ $sel =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#names[@]} )) || die "无效编号"
  local name=${names[$((sel - 1))]}
  confirm "删除数据卷 $name？卷内数据会永久丢失" || return 0
  docker volume rm "$name"
}

docker_uninstall() {
  require_root
  confirm "停止所有容器并卸载 Docker？" || return 0
  if have docker; then
    if confirm "先删除所有容器？"; then
      mapfile -t ids < <(docker ps -aq 2>/dev/null)
      [[ ${#ids[@]} -gt 0 ]] && docker rm -f "${ids[@]}" >/dev/null 2>&1 || true
    fi
    if confirm "删除所有镜像？"; then
      mapfile -t ids < <(docker images -aq 2>/dev/null)
      [[ ${#ids[@]} -gt 0 ]] && docker rmi -f "${ids[@]}" >/dev/null 2>&1 || true
    fi
  fi

  case ${PKG:-unknown} in
    apt) pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose || true ;;
    dnf|yum) pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true ;;
    apk) pkg_remove docker docker-cli-compose || true ;;
    pacman) pkg_remove docker docker-compose || true ;;
    zypper) pkg_remove docker docker-compose || true ;;
  esac
  ok "Docker 软件包卸载流程结束"
  if confirm "同时删除 /var/lib/docker 与 /etc/docker（所有容器数据会永久丢失）？"; then
    rm -rf /var/lib/docker /etc/docker
    ok "Docker 数据目录已删除"
  fi
}
