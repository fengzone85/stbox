#!/usr/bin/env bash
# 模块：常用组件、语言环境与 tmux 工作区

sst_register_module components "组件环境" "常用工具 语言环境 工作区"
SST_MODULE_ITEMS[components]=$'list|组件清单\ninstall|安装组件\ninstall_all|安装全部组件\nremove|卸载组件\ncustom|安装自定义包\npython|Python 环境\nnodejs|Node.js 环境\ngolang|Go 环境\njava|Java 环境\nuninstall_env|卸载语言环境\nworkspace|tmux 工作区'

COMP_KEYS=(curl wget sudo socat htop iftop unzip tar tmux ffmpeg btop ranger gdu fzf screen masscan cmatrix sl bastet nsnake ninvaders)
COMP_PKGS=(curl wget sudo socat htop iftop unzip tar tmux ffmpeg btop ranger gdu fzf screen masscan cmatrix sl bastet nsnake ninvaders)
COMP_DESCS=("HTTP 下载工具" "下载工具" "权限管理" "网络通信/证书辅助" "进程监控" "网络流量监控" "ZIP 解压" "GZ 压缩解压" "终端复用" "视频编码/推流" "现代监控工具" "终端文件管理器" "磁盘占用分析" "全局模糊搜索" "后台会话" "端口扫描" "黑客帝国屏保" "跑火车屏保" "俄罗斯方块" "贪吃蛇" "太空入侵者")

comp_installed() {
  have "$1" || [[ -x "/usr/games/$1" ]]
}

components_list() {
  section "组件清单"
  printf '  %3s  %-12s %-8s %s\n' "序号" "组件" "状态" "说明"
  hr
  local i
  for i in "${!COMP_KEYS[@]}"; do
    printf '  %3d  %-12s %-8s %s\n' \
      "$((i + 1))" "${COMP_KEYS[$i]}" \
      "$(comp_installed "${COMP_KEYS[$i]}" && echo 已安装 || echo 未安装)" \
      "${COMP_DESCS[$i]}"
  done
}

components_parse_selection() {
  local input=$1 i
  input=${input//,/ }
  local -a idxs=()
  for i in $input; do
    [[ $i =~ ^[0-9]+$ ]] || die "无效编号：$i"
    (( i >= 1 && i <= ${#COMP_KEYS[@]} )) || die "编号超出范围：$i"
    idxs+=("$((i - 1))")
  done
  printf '%s\n' "${idxs[@]}"
}

components_install() {
  require_root
  components_list
  local input
  input=$(ask "要安装的编号（空格分隔，all=全部）" "all")
  local -a idxs=()
  if [[ $input == all ]]; then
    idxs=("${!COMP_KEYS[@]}")
  else
    local parsed
    parsed=$(components_parse_selection "$input") || return 1
    mapfile -t idxs <<<"$parsed"
  fi
  [[ ${#idxs[@]} -gt 0 ]] || return 0

  confirm "安装以上 ${#idxs[@]} 个组件？" || return 0
  pkg_update || die "软件源更新失败"
  local idx failed=0
  for idx in "${idxs[@]}"; do
    info "安装 ${COMP_KEYS[$idx]}（${COMP_DESCS[$idx]}）…"
    pkg_install "${COMP_PKGS[$idx]}" || { warn "${COMP_KEYS[$idx]} 安装失败"; failed=$((failed + 1)); }
  done
  if (( failed == 0 )); then
    ok "全部组件安装完成"
  else
    warn "完成，但有 ${failed} 个组件安装失败（可能当前发行版无对应软件包）"
  fi
}

components_install_all() {
  require_root
  confirm "安装全部 ${#COMP_KEYS[@]} 个组件？" || return 0
  pkg_update || die "软件源更新失败"
  local i failed=0
  for i in "${!COMP_KEYS[@]}"; do
    info "安装 ${COMP_KEYS[$i]}…"
    pkg_install "${COMP_PKGS[$i]}" || { warn "${COMP_KEYS[$i]} 安装失败"; failed=$((failed + 1)); }
  done
  ok "批量安装结束，失败 ${failed} 个"
}

components_remove() {
  require_root
  section "已安装组件"
  local -a installed=()
  local i
  for i in "${!COMP_KEYS[@]}"; do
    if comp_installed "${COMP_KEYS[$i]}"; then
      installed+=("$i")
      printf '  %3d  %-12s %s\n' "$((i + 1))" "${COMP_KEYS[$i]}" "${COMP_DESCS[$i]}"
    fi
  done
  [[ ${#installed[@]} -gt 0 ]] || { info "没有已安装的组件"; return 0; }

  local input
  input=$(ask "要卸载的编号（空格分隔）" "")
  [[ -n $input ]] || return 0
  local -a idxs=()
  local parsed
  parsed=$(components_parse_selection "$input") || return 1
  mapfile -t idxs <<<"$parsed"
  [[ ${#idxs[@]} -gt 0 ]] || return 0

  local -a pkgs=()
  for i in "${idxs[@]}"; do pkgs+=("${COMP_PKGS[$i]}"); done
  confirm "卸载：${pkgs[*]}（可能同时移除依赖）？" || return 0
  pkg_remove "${pkgs[@]}" || warn "部分组件卸载失败"
  ok "卸载完成"
}

components_custom() {
  require_root
  local pkgs
  pkgs=$(ask "要安装的软件包名（空格分隔）" "")
  [[ -n $pkgs ]] || return 0
  local -a list=()
  read -r -a list <<<"$pkgs"
  confirm "安装：${list[*]}？" || return 0
  pkg_update || die "软件源更新失败"
  pkg_install "${list[@]}" || die "安装失败：${list[*]}"
  ok "安装完成"
}

components_env_pkgs() {
  local lang=$1
  case $PKG:$lang in
    apt:python) printf '%s\n' "python3 python3-pip python3-venv" ;;
    dnf:python|yum:python) printf '%s\n' "python3 python3-pip" ;;
    apk:python) printf '%s\n' "python3 py3-pip" ;;
    pacman:python) printf '%s\n' "python python-pip" ;;
    zypper:python) printf '%s\n' "python3 python3-pip" ;;
    apt:node) printf '%s\n' "nodejs npm" ;;
    dnf:node|yum:node) printf '%s\n' "nodejs npm" ;;
    apk:node) printf '%s\n' "nodejs npm" ;;
    pacman:node) printf '%s\n' "nodejs npm" ;;
    zypper:node) printf '%s\n' "nodejs npm" ;;
    apt:go) printf '%s\n' "golang-go" ;;
    dnf:go|yum:go) printf '%s\n' "golang" ;;
    apk:go) printf '%s\n' "go" ;;
    pacman:go) printf '%s\n' "go" ;;
    zypper:go) printf '%s\n' "go" ;;
    apt:java) printf '%s\n' "openjdk-17-jdk" ;;
    dnf:java|yum:java) printf '%s\n' "java-17-openjdk-devel" ;;
    apk:java) printf '%s\n' "openjdk17" ;;
    pacman:java) printf '%s\n' "jdk17-openjdk" ;;
    zypper:java) printf '%s\n' "java-17-openjdk-devel" ;;
    *) return 1 ;;
  esac
}

components_env_install() {
  local lang=$1 label=$2
  require_root
  local pkgs out
  out=$(components_env_pkgs "$lang") || die "当前系统不支持安装 $label"
  read -r -a pkgs <<<"$out"
  confirm "通过系统包管理器安装 $label（${pkgs[*]}）？发行版仓库版本可能不是最新" || return 0
  pkg_update || die "软件源更新失败"
  pkg_install "${pkgs[@]}" || die "$label 安装失败"
  ok "$label 安装完成"
  case $lang in
    python) python3 --version 2>/dev/null || true ;;
    node) node --version 2>/dev/null || true ;;
    go) go version 2>/dev/null || true ;;
    java) java -version 2>&1 | head -n 1 || true ;;
  esac
}

components_python() { components_env_install python "Python3"; }
components_nodejs() { components_env_install node "Node.js"; }
components_golang() { components_env_install go "Golang"; }
components_java() { components_env_install java "OpenJDK 17"; }

components_uninstall_env() {
  require_root
  section "卸载语言环境"
  printf '  %s1%s) Python3\n  %s2%s) Node.js\n  %s3%s) Golang\n  %s4%s) OpenJDK 17\n  %s0%s) 返回\n\n' \
    "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET"
  local choice lang label
  read -r -p "请选择: " choice || return 0
  case $choice in
    1) lang=python label=Python3 ;;
    2) lang=node label="Node.js" ;;
    3) lang=go label=Golang ;;
    4) lang=java label="OpenJDK 17" ;;
    0|q|back) return 0 ;;
    *) warn "无效选项"; return 0 ;;
  esac

  local pkgs out
  out=$(components_env_pkgs "$lang") || die "当前系统不支持卸载 $label"
  read -r -a pkgs <<<"$out"
  warn "卸载 $label 可能影响依赖它的其他软件，Python3 在部分发行版中还是系统依赖"
  if [[ $lang == python ]]; then
    local phrase
    read -r -p "输入 REMOVE 确认卸载 $label: " phrase || return 1
    [[ $phrase == REMOVE ]] || { warn "已取消"; return 0; }
  else
    confirm "确认卸载 $label（${pkgs[*]}）？" || return 0
  fi
  pkg_remove "${pkgs[@]}" || warn "部分软件包卸载失败"
  ok "$label 卸载流程结束"
}

components_workspace() {
  local choice name
  while true; do
    section "tmux 工作区"
    if have tmux; then
      tmux ls 2>/dev/null || info "暂无 tmux 会话"
    else
      warn "tmux 未安装"
    fi
    printf '\n'
    printf '  %s1-5%s) 进入对应工作区（不存在则创建）\n' "$C_GREEN" "$C_RESET"
    printf '  %sa%s) 安装 tmux\n  %sb%s) 卸载 tmux\n  %s0%s) 返回\n\n' \
      "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET"
    read -r -p "请选择: " choice || break
    case $choice in
      [1-5])
        if ! have tmux; then
          confirm "tmux 未安装，现在安装？" || continue
          pkg_update || die "软件源更新失败"
          pkg_install tmux || die "tmux 安装失败"
        fi
        name="work$choice"
        info "进入工作区 $name（Ctrl+b 再按 d 退出，任务会继续后台运行）"
        tmux new-session -A -s "$name"
        ;;
      a)
        require_root
        pkg_update || die "软件源更新失败"
        pkg_install tmux || die "tmux 安装失败"
        ok "tmux 安装完成"
        ;;
      b)
        require_root
        confirm "卸载 tmux？现有后台会话会全部结束" || continue
        pkg_remove tmux || warn "tmux 卸载失败"
        ok "tmux 已卸载"
        ;;
      0|q|back) break ;;
      *) warn "无效选项：$choice" ;;
    esac
  done
}
