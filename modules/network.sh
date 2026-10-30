#!/usr/bin/env bash
# 模块：网络测试

sst_register_module network "网络测试" "测速 路由 延迟 DNS 端口"
SST_MODULE_ITEMS[network]=$'info|网络概览\nip|IP 与归属地\nspeed|下载测速\nping|延迟与丢包\nroute|路由追踪\ndns|DNS 检测\nport|远程端口检测\nlisten|本机监听端口'

network_info() {
  section "网络概览"
  if have ip; then
    ip -br address 2>/dev/null
    printf '\n'
    info "默认路由："
    ip route show default 2>/dev/null || true
  else
    ifconfig -a 2>/dev/null || warn "未找到 ip/ifconfig 命令"
  fi

  local dns
  dns=$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)
  kv "DNS 服务器" "${dns:-未知}"
  kv "公网 IP" "$(get_public_ip)"
}

network_ip() {
  section "本机 IP 与归属地"
  local v4 v6 json field city region country org
  v4=$(ip -4 -br addr show scope global 2>/dev/null | awk '{print $3}' | paste -sd, -)
  v6=$(ip -6 -br addr show scope global 2>/dev/null | awk '{print $3}' | paste -sd, -)
  kv "本机 IPv4" "${v4:-无}"
  kv "本机 IPv6" "${v6:-无}"
  kv "公网 IPv4" "$(get_public_ip)"

  v6=$(curl -6 -fsS --max-time 4 https://api6.ipify.org 2>/dev/null || true)
  kv "公网 IPv6" "${v6:-无或不可用}"

  json=$(curl -fsS --max-time 6 https://ipinfo.io/json 2>/dev/null || true)
  if [[ -n $json ]]; then
    field() { printf '%s\n' "$2" | sed -n "s/.*\"$1\": \"\\([^\"]*\\)\".*/\\1/p" | head -n 1; }
    city=$(field city "$json")
    region=$(field region "$json")
    country=$(field country "$json")
    org=$(field org "$json")
    kv "归属地" "${country:-未知} / ${region:-未知} / ${city:-未知}"
    kv "运营商" "${org:-未知}"
  else
    warn "归属地查询失败（ipinfo.io 不可达）"
  fi
}

network_speed() {
  local size=${1:-50} out speed sampled time
  [[ $size =~ ^[0-9]+$ ]] || die "测速大小必须是数字（单位 MB）"
  (( size >= 5 && size <= 500 )) || die "测速大小需在 5-500 MB 之间"
  ensure_tool curl curl || return 1

  info "从 Cloudflare 下载 ${size} MB 测试数据…"
  if ! out=$(curl -o /dev/null -fsS --max-time 60 \
    -w '%{speed_download} %{size_download} %{time_total}' \
    "https://speed.cloudflare.com/__down?bytes=$((size * 1024 * 1024))" 2>/dev/null); then
    die "测速失败：无法访问测速节点，请检查网络或代理设置"
  fi
  read -r speed sampled time <<<"$out"
  awk -v s="$speed" -v n="$sampled" -v t="$time" 'BEGIN{
    printf "下载速度：%.2f Mbps（%.2f MB/s）\n", s * 8 / 1000000, s / 1048576;
    printf "下载大小：%.1f MB，用时 %.2f 秒\n", n / 1048576, t;
  }'
}

network_ping() {
  local host=${1:-1.1.1.1} out
  ensure_tool ping iputils-ping || return 1
  info "对 $host 进行 10 次探测…"
  out=$(ping -c 10 -W 2 "$host" 2>&1) || warn "存在丢包或目标不可达"
  printf '%s\n' "$out" | tail -n 5
}

network_route() {
  local host=${1:-1.1.1.1}
  if have mtr; then
    info "使用 mtr 追踪到 $host 的路由…"
    mtr -r -c 10 "$host"
    return 0
  fi
  if ! have traceroute; then
    confirm "安装 traceroute 用于路由追踪？" || return 0
    pkg_install traceroute || die "traceroute 安装失败"
  fi
  info "使用 traceroute 追踪到 $host 的路由…"
  traceroute -m 20 -w 1 "$host"
}

network_dns() {
  section "DNS 配置"
  grep -E '^nameserver' /etc/resolv.conf 2>/dev/null || warn "未配置 nameserver"

  section "域名解析测试"
  local d out start end ms failed=0
  printf '  %-24s %-18s %s\n' "域名" "解析结果" "耗时"
  for d in github.com www.cloudflare.com www.baidu.com; do
    start=$(date +%s%3N)
    if have dig; then
      out=$(dig +short +time=2 "$d" 2>/dev/null | head -n 1)
    else
      out=$(getent ahosts "$d" 2>/dev/null | awk 'NR==1 {print $1}')
    fi
    end=$(date +%s%3N)
    ms=$(( end - start ))
    if [[ -n $out ]]; then
      printf '  %-24s %-18s %s ms\n' "$d" "$out" "$ms"
    else
      printf '  %-24s %-18s %s\n' "$d" "解析失败" "-"
      failed=$((failed + 1))
    fi
  done
  (( failed == 0 )) || warn "存在解析失败，通常是 DNS 污染或本地解析服务异常"
}

network_port() {
  local host=${1:-} port=${2:-}
  [[ -n $host ]] || host=$(ask "目标主机" "1.1.1.1")
  [[ -n $port ]] || port=$(ask "目标端口" "443")
  valid_port "$port" || die "端口无效：$port"

  info "检测 $host:$port（最多 3 秒）…"
  if tcp_check "$host" "$port" 3; then
    ok "$host:$port 可达"
  else
    err "$host:$port 不可达（可能被防火墙拦截或服务未监听）"
    return 1
  fi
}

network_listen() {
  section "本机监听端口"
  if have ss; then
    ss -tulpn 2>/dev/null || ss -tuln 2>/dev/null
  elif have netstat; then
    netstat -tulpn 2>/dev/null
  else
    warn "未找到 ss/netstat，请安装 iproute2 或 net-tools"
    return 1
  fi
}
