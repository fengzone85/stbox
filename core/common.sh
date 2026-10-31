#!/usr/bin/env bash
# 基础层：颜色、日志、权限、系统探测、包管理、交互工具
# 由 st.sh 加载，不独立执行。

if [[ ${SST_NO_COLOR:-0} -eq 1 || ! -t 1 || ${TERM:-} == "dumb" ]]; then
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_MAGENTA=''
else
  C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m' C_CYAN=$'\033[36m' C_MAGENTA=$'\033[35m'
fi

SST_CONFIG_DIR="$SST_HOME/config"
SST_DATA_DIR="$SST_HOME/data"
SST_LOG_DIR="$SST_HOME/logs"
SST_LOG="$SST_LOG_DIR/sst.log"
ARCH=${ARCH:-$(uname -m)}

sst_init_dirs() {
  mkdir -p "$SST_CONFIG_DIR" "$SST_DATA_DIR/backups" "$SST_DATA_DIR/apps" "$SST_LOG_DIR" 2>/dev/null || true
}

# ---------- 输出与日志 ----------
sst_log() {
  local level=$1
  shift
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >>"$SST_LOG" 2>/dev/null || true
}
info() { printf '%s %s\n' "${C_CYAN}[信息]${C_RESET}" "$*"; sst_log INFO "$*"; }
ok()   { printf '%s %s\n' "${C_GREEN}[完成]${C_RESET}" "$*"; sst_log OK "$*"; }
warn() { printf '%s %s\n' "${C_YELLOW}[注意]${C_RESET}" "$*" >&2; sst_log WARN "$*"; }
err()  { printf '%s %s\n' "${C_RED}[错误]${C_RESET}" "$*" >&2; sst_log ERROR "$*"; }
die()  { err "$*"; exit 1; }

section() { printf '\n%s%s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
kv()      { printf '  %-14s %s\n' "$1" "$2"; }
hr()      { printf '%s\n' "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"; }

# ---------- 通用工具 ----------
have() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  local prompt=${1:-"确认执行该操作？"} answer
  [[ ${SST_YES:-0} -eq 1 ]] && return 0
  [[ -t 0 ]] || die "非交互环境请追加 --yes 参数"
  read -r -p "$prompt [y/N] " answer || return 1
  case ${answer,,} in
    y|yes|是) return 0 ;;
    *) return 1 ;;
  esac
}

pause() {
  [[ -t 0 ]] || return 0
  read -r -p "按回车继续…" _ || true
}

ask() {
  local prompt=$1 default=${2:-} answer
  read -r -p "$prompt${default:+ [$default]}: " answer || true
  printf '%s\n' "${answer:-$default}"
}

valid_port() {
  [[ ${1:-} =~ ^[0-9]+$ ]] && (( 1 <= $1 && $1 <= 65535 ))
}

# 通过 /dev/tcp 检测远端端口（需 timeout 命令）
tcp_check() {
  local host=$1 port=$2 wait=${3:-3}
  have timeout || return 1
  timeout "$wait" bash -c "exec 3<>/dev/tcp/$host/$port" >/dev/null 2>&1
}

bytes_h() {
  awk -v b="${1:-0}" 'BEGIN{split("B KB MB GB TB PB",u," ");i=1;while(b>=1024&&i<6){b/=1024;i++}printf "%.2f %s",b,u[i]}'
}

# ---------- 权限 ----------
require_root() {
  [[ ${EUID:-1} -eq 0 ]] && return 0
  if have sudo && [[ -t 0 ]]; then
    warn "该操作需要 root 权限，正在使用 sudo 重新执行…"
    exec sudo -E env SST_YES="$SST_YES" SST_NO_COLOR="$SST_NO_COLOR" bash "$SST_ENTRY" "${SST_ARGS[@]}"
  fi
  die "需要 root 权限，请使用 sudo $SST_ENTRY ${SST_ARGS[*]:-}"
}

# ---------- 系统探测 ----------
sst_detect_os() {
  OS_ID=unknown
  OS_NAME=Linux
  OS_VER=''
  OS_LIKE=''
  ARCH=$(uname -m)

  if [[ -r /etc/os-release ]]; then
    OS_ID=$(. /etc/os-release; printf '%s' "${ID:-unknown}")
    OS_NAME=$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}")
    OS_VER=$(. /etc/os-release; printf '%s' "${VERSION_ID:-}")
    OS_LIKE=$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")
  fi

  if have apt-get; then PKG=apt
  elif have dnf; then PKG=dnf
  elif have yum; then PKG=yum
  elif have apk; then PKG=apk
  elif have pacman; then PKG=pacman
  elif have zypper; then PKG=zypper
  else PKG=unknown
  fi

  if [[ -d /run/systemd/system ]] && have systemctl; then INIT=systemd
  elif have rc-service; then INIT=openrc
  else INIT=sysv
  fi

  VIRT=''
  if have systemd-detect-virt; then
    VIRT=$(systemd-detect-virt 2>/dev/null || true)
    VIRT=${VIRT%%$'\n'*}
  fi
  [[ -n $VIRT ]] || VIRT=unknown
}

# ---------- 包管理 ----------
pkg_update() {
  case ${PKG:-unknown} in
    apt) DEBIAN_FRONTEND=noninteractive apt-get update -qq ;;
    dnf) dnf makecache -q ;;
    yum) yum makecache -q ;;
    apk) apk update -q ;;
    pacman) pacman -Sy --noconfirm ;;
    zypper) zypper -q refresh ;;
    *) die "当前系统不支持自动安装依赖（未知包管理器）" ;;
  esac
}

pkg_install() {
  [[ $# -gt 0 ]] || return 0
  case ${PKG:-unknown} in
    apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" ;;
    dnf|yum) "$PKG" install -y -q "$@" ;;
    apk) apk add --no-cache "$@" ;;
    pacman) pacman -S --noconfirm --needed "$@" ;;
    zypper) zypper -n install "$@" ;;
    *) die "当前系统不支持自动安装依赖（未知包管理器）" ;;
  esac
}

pkg_clean() {
  case ${PKG:-unknown} in
    apt) apt-get clean; rm -rf /var/lib/apt/lists/* 2>/dev/null || true ;;
    dnf|yum) "$PKG" clean all ;;
    apk) apk cache clean ;;
    pacman) pacman -Sc --noconfirm ;;
    zypper) zypper clean -a ;;
    *) return 0 ;;
  esac
}

pkg_upgrade() {
  case ${PKG:-unknown} in
    apt) DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y ;;
    dnf) dnf upgrade -y ;;
    yum) yum upgrade -y ;;
    apk) apk update && apk upgrade ;;
    pacman) pacman -Syu --noconfirm ;;
    zypper) zypper -n update ;;
    *) die "当前系统不支持自动更新" ;;
  esac
}

pkg_remove() {
  [[ $# -gt 0 ]] || return 0
  case ${PKG:-unknown} in
    apt) DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@" && apt-get autoremove -y ;;
    dnf|yum) "$PKG" remove -y "$@" && "$PKG" autoremove -y ;;
    apk) apk del "$@" ;;
    pacman) pacman -Rns --noconfirm "$@" ;;
    zypper) zypper -n remove "$@" ;;
    *) die "当前系统不支持自动卸载软件包" ;;
  esac
}

ensure_tool() {
  local cmd=$1
  shift
  have "$cmd" && return 0
  [[ $# -gt 0 ]] || die "缺少命令：$cmd，请手动安装"
  info "安装依赖：$*"
  pkg_update
  pkg_install "$@"
  have "$cmd" || die "依赖安装失败：$cmd"
}

# ---------- 服务管理 ----------
svc_enable() {
  case ${INIT:-sysv} in
    systemd) systemctl enable --now "$1" ;;
    openrc) rc-update add "$1" default >/dev/null 2>&1 || true; rc-service "$1" start ;;
    *) service "$1" start ;;
  esac
}

svc_restart() {
  case ${INIT:-sysv} in
    systemd) systemctl restart "$1" ;;
    openrc) rc-service "$1" restart ;;
    *) service "$1" restart ;;
  esac
}

svc_active() {
  case ${INIT:-sysv} in
    systemd) systemctl is-active --quiet "$1" ;;
    openrc) rc-service "$1" status >/dev/null 2>&1 ;;
    *) service "$1" status >/dev/null 2>&1 ;;
  esac
}

# ---------- 网络信息 ----------
get_public_ip() {
  local cache="$SST_DATA_DIR/public_ip" ip=''
  if [[ -s $cache ]]; then
    local now mtime
    now=$(date +%s)
    mtime=$(stat -c %Y "$cache" 2>/dev/null || echo 0)
    if (( now - mtime < 600 )); then
      cat "$cache"
      return 0
    fi
  fi
  ip=$(curl -4 -fsS --max-time 4 https://api.ipify.org 2>/dev/null \
    || curl -4 -fsS --max-time 4 https://ifconfig.me 2>/dev/null || true)
  if [[ -n $ip ]]; then
    printf '%s\n' "$ip" >"$cache" 2>/dev/null || true
  fi
  printf '%s\n' "${ip:-未知}"
}

# 下载文件；GitHub raw 不可达时自动切换 jsDelivr / gh-proxy 镜像
download_with_fallback() {
  local url=$1 out=$2 max_time=${3:-60} alt='' first_time
  first_time=$max_time
  if [[ $url == https://raw.githubusercontent.com/* ]] && (( first_time > 15 )); then
    first_time=15
  elif [[ $url == *github.com* ]] && (( first_time > 25 )); then
    first_time=25
  fi

  if curl -fL --connect-timeout 6 --max-time "$first_time" -o "$out" "$url" 2>/dev/null; then
    return 0
  fi
  rm -f "$out"

  if [[ $url == https://raw.githubusercontent.com/* ]]; then
    local rest=${url#https://raw.githubusercontent.com/}
    local owner=${rest%%/*}
    rest=${rest#*/}
    local repo=${rest%%/*}
    rest=${rest#*/}
    local branch=${rest%%/*}
    rest=${rest#*/}
    alt="https://cdn.jsdelivr.net/gh/${owner}/${repo}@${branch}/${rest}"
  fi

  if [[ -n $alt ]]; then
    warn "原始地址不可达，尝试镜像：$alt"
    if curl -fL --connect-timeout 6 --max-time "$max_time" -o "$out" "$alt" 2>/dev/null; then
      return 0
    fi
    rm -f "$out"
  fi

  if [[ $url == *github.com* || $url == *githubusercontent.com* ]]; then
    alt="https://gh-proxy.com/${url}"
    warn "尝试 GitHub 代理：$alt"
    if curl -fL --connect-timeout 6 --max-time "$max_time" -o "$out" "$alt" 2>/dev/null; then
      return 0
    fi
    rm -f "$out"
  fi
  return 1
}

get_mem_info() {
  # 输出：总量/已用/可用（MB），优先 free，缺失时读取 /proc/meminfo
  local out
  out=$(free -m 2>/dev/null | awk 'NR==2 {print $2, $3, ($7 != "" ? $7 : $4)}')
  if [[ -n $out ]]; then
    printf '%s\n' "$out"
    return 0
  fi
  awk '
    /MemTotal/ { total = $2 }
    /MemAvailable/ { avail = $2 }
    /MemFree/ { free = $2 }
    END {
      if (total == "") { print ""; exit }
      if (avail == "") avail = free
      used = total - avail
      printf "%d %d %d\n", total / 1024, used / 1024, avail / 1024
    }
  ' /proc/meminfo 2>/dev/null
}

get_rx_tx() {
  # 输出：自开机以来累计接收/发送字节数
  awk -F: '/^[ ]*[a-zA-Z]/ && $1 !~ /lo/ {
        split($2, a, " ");
        rx += a[1]; tx += a[9];
      } END { printf "%d %d\n", rx, tx }' /proc/net/dev 2>/dev/null
}

get_load() {
  cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo "未知"
}

get_cpu_model() {
  if have lscpu; then
    lscpu 2>/dev/null | awk -F: '/Model name/{gsub(/^ +/,"",$2); print $2; exit}'
  else
    awk -F: '/model name/{gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null
  fi
}

get_uptime_human() {
  local secs
  secs=$(cut -d. -f1 /proc/uptime 2>/dev/null) || { echo "未知"; return; }
  local d=$(( secs / 86400 )) h=$(( secs % 86400 / 3600 )) m=$(( secs % 3600 / 60 ))
  printf '%d 天 %d 小时 %d 分' "$d" "$h" "$m"
}
