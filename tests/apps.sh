#!/usr/bin/env bash
# 应用插件测试：元数据完整性、端口唯一性、生命周期函数与 Compose 字段
# 用法：bash tests/apps.sh

set -o pipefail

SST_HOME=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SST_HOME
export SST_ENTRY="$SST_HOME/st.sh"
export SST_NO_COLOR=1

# shellcheck source=../core/common.sh
source "$SST_HOME/core/common.sh"
# shellcheck source=../core/apps.sh
source "$SST_HOME/core/apps.sh"

WORK_DIR=$(mktemp -d /tmp/stbox-apps-test.XXXXXX)
SST_CONFIG_DIR="$WORK_DIR/config"
SST_DATA_DIR="$WORK_DIR/data"
SST_LOG="$WORK_DIR/sst.log"
mkdir -p "$SST_CONFIG_DIR" "$SST_DATA_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

PASS=0
FAIL=0
declare -a FAILED=()

pass() { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); FAILED+=("$*"); printf '  [FAIL] %s\n' "$*" >&2; }

check_eq() {
  local label=$1 expected=$2 actual=${3:-}
  if [[ $actual == "$expected" ]]; then
    pass "$label（$actual）"
  else
    fail "$label 期望 $expected，实际 ${actual:-空}"
  fi
}

sst_load_apps

section "应用数量"
count=${#SST_APP_ORDER[@]}
if (( count >= 12 )); then
  pass "应用数量 $count"
else
  fail "应用数量过少：$count"
fi

section "元数据完整性"
declare -A seen_port=()
for name in "${SST_APP_ORDER[@]}"; do
  title=${SST_APP_TITLE[$name]:-}
  desc=${SST_APP_DESC[$name]:-}
  category=${SST_APP_CATEGORY[$name]:-}
  port=${SST_APP_PORT[$name]:-}
  url=${SST_APP_URL[$name]:-}

  [[ -n $title ]] || fail "$name 缺少 APP_TITLE"
  [[ -n $desc ]] || fail "$name 缺少 APP_DESC"
  [[ -n $category ]] || fail "$name 缺少 APP_CATEGORY"
  [[ -n $port ]] || fail "$name 缺少 APP_PORT"
  [[ -n $url ]] || fail "$name 缺少 APP_URL"

  if [[ -n $port ]]; then
    if [[ $port =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
      [[ -n ${seen_port[$port]:-} ]] && fail "$name 端口 $port 与 ${seen_port[$port]} 冲突"
      seen_port[$port]=$name
    else
      fail "$name 端口无效：$port"
    fi
  fi

  [[ $url == http://* || $url == https://* ]] || fail "$name URL 协议无效：$url"
  [[ $url == *IP* ]] || fail "$name URL 未包含 IP 占位符：$url"
done
(( FAIL == 0 )) && pass "所有应用元数据完整且端口唯一"

section "生命周期函数"
for name in "${SST_APP_ORDER[@]}"; do
  safe=${name//-/_}
  declare -F "app_${safe}_install" >/dev/null 2>&1 || fail "$name 缺少 app_${safe}_install"
  declare -F "app_${safe}_remove" >/dev/null 2>&1 || fail "$name 缺少 app_${safe}_remove"
done
(( FAIL == 0 )) && pass "所有应用安装/移除函数存在"

section "Compose 定义"
for name in "${SST_APP_ORDER[@]}"; do
  dir=${SST_APP_DIR[$name]}
  [[ -f ${dir}app.sh ]] || { fail "$name 缺少 app.sh"; continue; }
  for field in 'image:' 'ports:' 'volumes:'; do
    grep -q "$field" "${dir}app.sh" || fail "$name Compose 缺少 $field"
  done
  grep -q "app_compose_up $name" "${dir}app.sh" || fail "$name 未使用 app_compose_up"
  grep -q "app_compose_down $name" "${dir}app.sh" || fail "$name 未使用 app_compose_down"
done
(( FAIL == 0 )) && pass "所有应用 Compose 定义完整"

section "应用助手"
check_eq "app_exists portainer" 0 "$(app_exists portainer; echo $?)"
check_eq "app_exists unknown" 1 "$(app_exists unknown; echo $?)"
if ( app_call portainer nosuch ) >/dev/null 2>&1; then
  fail "app_call 未知操作应失败"
else
  pass "app_call 未知操作返回非零"
fi

app_compose_up demo <<'YAML' >/dev/null 2>&1
services:
  demo:
    image: alpine:latest
YAML
check_eq "app_installed 检测 Compose 文件" 0 "$(app_installed demo; echo $?)"

compose_run() { return 0; }
app_compose_down demo >/dev/null 2>&1
check_eq "移除后删除 Compose 文件" 1 "$(app_installed demo; echo $?)"

section "Web IDE 安全提示"
out=$(app_webide_notice 8443 2>&1)
if [[ $out == *"HTTPS"* && $out == *"SSH 隧道"* ]]; then
  pass "提示包含 HTTPS 与 SSH 隧道"
else
  fail "Web IDE 安全提示不完整：$out"
fi

section "测试结果"
kv "通过" "$PASS"
kv "失败" "$FAIL"
if (( FAIL > 0 )); then
  printf '失败项：\n'
  for item in "${FAILED[@]}"; do
    printf '  - %s\n' "$item"
  done
  exit 1
fi
ok "应用插件测试通过"
exit 0
