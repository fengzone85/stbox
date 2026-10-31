#!/usr/bin/env bash
# 开荒向导 P3 回归测试：严格 rp_filter、BBR 实际关闭
# 用法：sudo bash tests/init_hardening.sh
# 说明：会临时修改系统 sysctl 与 /etc/sysctl.d 配置，退出时自动恢复。

set -o pipefail

SST_HOME=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SST_HOME
export SST_ENTRY="$SST_HOME/st.sh"
export SST_YES=1
export SST_NO_COLOR=1

if [[ ${EUID:-1} -ne 0 ]]; then
  printf '需要 root 运行：sudo bash %s\n' "$0" >&2
  exit 1
fi

# shellcheck source=../core/common.sh
source "$SST_HOME/core/common.sh"
# shellcheck source=../core/config.sh
source "$SST_HOME/core/config.sh"
# shellcheck source=../core/wizard.sh
source "$SST_HOME/core/wizard.sh"
# shellcheck source=../core/menu.sh
source "$SST_HOME/core/menu.sh"
# shellcheck source=../modules/security.sh
source "$SST_HOME/modules/security.sh"
# shellcheck source=../modules/tune.sh
source "$SST_HOME/modules/tune.sh"
# shellcheck source=../modules/init.sh
source "$SST_HOME/modules/init.sh"

sst_detect_os

WORK_DIR=$(mktemp -d /tmp/stbox-hardening-test.XXXXXX)
ORIG_DIR="$WORK_DIR/original"
mkdir -p "$ORIG_DIR"
SST_CONFIG_DIR="$WORK_DIR/config"
SST_DATA_DIR="$WORK_DIR/data"
SST_WIZARD_DIR="$SST_DATA_DIR/init"
SST_WIZARD_STATE="$SST_WIZARD_DIR/state.conf"
SST_LOG="$WORK_DIR/sst.log"
mkdir -p "$SST_CONFIG_DIR" "$SST_DATA_DIR/backups" "$SST_WIZARD_DIR"
wizard_init

SEC_FILE=/etc/sysctl.d/99-stbox-security.conf
BBR_FILE=/etc/sysctl.d/99-sst-bbr.conf
LOCAL_LOADER=/etc/local.d/99-stbox-sysctl.start

PASS=0
FAIL=0
SKIP=0
declare -a FAILED=()

pass() { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); FAILED+=("$*"); printf '  [FAIL] %s\n' "$*" >&2; }
skip() { SKIP=$((SKIP + 1)); printf '  [SKIP] %s\n' "$*"; }

check_eq() {
  local label=$1 expected=$2 actual=${3:-}
  if [[ $actual == "$expected" ]]; then
    pass "$label（$actual）"
  else
    fail "$label 期望 $expected，实际 ${actual:-空}"
  fi
}

check_file_absent() {
  local label=$1 file=$2
  if [[ ! -e $file ]]; then pass "$label"; else fail "$label：$file 仍存在"; fi
}

check_file_exists() {
  local label=$1 file=$2
  if [[ -f $file ]]; then pass "$label"; else fail "$label：$file 不存在"; fi
}

runtime_get() { sysctl -n "$1" 2>/dev/null || true; }

SYSCTL_KEYS=(
  net.ipv4.conf.all.rp_filter
  net.ipv4.conf.default.rp_filter
  net.ipv4.tcp_syncookies
  net.ipv4.conf.all.accept_redirects
  net.ipv4.conf.default.accept_redirects
  net.ipv4.conf.all.send_redirects
  net.ipv4.conf.default.send_redirects
  net.ipv4.conf.all.accept_source_route
  net.ipv4.conf.default.accept_source_route
  net.ipv4.icmp_echo_ignore_broadcasts
  net.ipv4.icmp_ignore_bogus_error_responses
  net.ipv4.conf.all.log_martians
  net.ipv6.conf.all.accept_redirects
  net.ipv6.conf.all.accept_source_route
  fs.protected_hardlinks
  fs.protected_symlinks
)

declare -A ORIG_SYSCTL=()
for key in "${SYSCTL_KEYS[@]}"; do
  ORIG_SYSCTL[$key]=$(runtime_get "$key")
done
ORIG_CC=$(runtime_get net.ipv4.tcp_congestion_control)
ORIG_QDISC=$(runtime_get net.core.default_qdisc)
BBR_MODULE_PRELOADED=0
bbr_available && BBR_MODULE_PRELOADED=1

save_file() {
  local src=$1 name=$2
  if [[ -e $src ]]; then
    cp -a "$src" "$ORIG_DIR/$name"
    printf 'present\n' >"$ORIG_DIR/$name.state"
  else
    printf 'absent\n' >"$ORIG_DIR/$name.state"
  fi
}

restore_file() {
  local src=$1 name=$2 state
  state=$(cat "$ORIG_DIR/$name.state" 2>/dev/null || printf 'absent')
  if [[ $state == present && -e $ORIG_DIR/$name ]]; then
    mkdir -p "$(dirname "$src")"
    cp -a "$ORIG_DIR/$name" "$src"
  else
    rm -f "$src"
  fi
}

restore_runtime() {
  local key value
  for key in "${SYSCTL_KEYS[@]}"; do
    value=${ORIG_SYSCTL[$key]:-}
    [[ -n $value ]] || continue
    sysctl -w "$key=$value" >/dev/null 2>&1 || true
  done
  [[ -n $ORIG_CC ]] && sysctl -w "net.ipv4.tcp_congestion_control=$ORIG_CC" >/dev/null 2>&1 || true
  [[ -n $ORIG_QDISC ]] && sysctl -w "net.core.default_qdisc=$ORIG_QDISC" >/dev/null 2>&1 || true
}

cleanup() {
  local rc=$? bad=0 key value actual
  trap - EXIT INT TERM
  set +e
  printf '\n'
  section "恢复现场"
  restore_file "$SEC_FILE" stbox-security
  restore_file "$BBR_FILE" sst-bbr
  restore_file "$LOCAL_LOADER" stbox-sysctl-loader
  sysctl --system >/dev/null 2>&1 || true
  restore_runtime
  if (( BBR_MODULE_PRELOADED == 0 )) && lsmod 2>/dev/null | grep -q '^tcp_bbr'; then
    modprobe -r tcp_bbr >/dev/null 2>&1 || true
  fi

  for key in "${SYSCTL_KEYS[@]}"; do
    value=${ORIG_SYSCTL[$key]:-}
    [[ -n $value ]] || continue
    actual=$(runtime_get "$key")
    if [[ $actual != "$value" ]]; then
      printf '  [警告] %s 未恢复：期望 %s，实际 %s\n' "$key" "$value" "${actual:-空}" >&2
      bad=1
    fi
  done
  actual=$(runtime_get net.ipv4.tcp_congestion_control)
  if [[ -n $ORIG_CC && $actual != "$ORIG_CC" ]]; then
    printf '  [警告] TCP 算法未恢复：期望 %s，实际 %s\n' "$ORIG_CC" "${actual:-空}" >&2
    bad=1
  fi
  actual=$(runtime_get net.core.default_qdisc)
  if [[ -n $ORIG_QDISC && $actual != "$ORIG_QDISC" ]]; then
    printf '  [警告] 队列规则未恢复：期望 %s，实际 %s\n' "$ORIG_QDISC" "${actual:-空}" >&2
    bad=1
  fi

  if (( bad == 0 )); then
    ok "已恢复原始 sysctl 与配置文件"
  else
    warn "现场恢复不完整，请手动检查 /etc/sysctl.d"
  fi
  rm -rf "$WORK_DIR"
  exit "$rc"
}

save_file "$SEC_FILE" stbox-security
save_file "$BBR_FILE" sst-bbr
save_file "$LOCAL_LOADER" stbox-sysctl-loader
trap cleanup EXIT INT TERM

section "测试环境"
kv "系统" "${OS_NAME:-未知}"
kv "内核" "$(uname -r)"
kv "rp_filter(all/default)" "$(runtime_get net.ipv4.conf.all.rp_filter) / $(runtime_get net.ipv4.conf.default.rp_filter)"
kv "TCP 算法" "$ORIG_CC"
kv "队列规则" "$ORIG_QDISC"

# ---------- 严格 rp_filter ----------
test_strict_rpfilter() {
  section "用例：严格 rp_filter"
  init_security_sysctl_apply strict

  check_file_exists "安全配置文件已生成" "$SEC_FILE"
  local count
  count=$(grep -cE '^net\.ipv4\.conf\.(all|default)\.rp_filter = 1$' "$SEC_FILE" 2>/dev/null || true)
  check_eq "配置文件包含 all/default 两条 rp_filter" 2 "$count"
  check_eq "向导状态记录为 strict" strict "$(wizard_get SECURITY_SYSCTL)"

  local item key expected actual
  local -a checks=(
    "net.ipv4.conf.all.rp_filter=1"
    "net.ipv4.conf.default.rp_filter=1"
    "net.ipv4.tcp_syncookies=1"
    "net.ipv4.conf.all.accept_redirects=0"
    "net.ipv4.conf.default.accept_redirects=0"
    "net.ipv4.conf.all.send_redirects=0"
    "net.ipv4.conf.default.send_redirects=0"
    "net.ipv4.conf.all.accept_source_route=0"
    "net.ipv4.conf.default.accept_source_route=0"
    "net.ipv4.icmp_echo_ignore_broadcasts=1"
    "net.ipv4.icmp_ignore_bogus_error_responses=1"
    "net.ipv4.conf.all.log_martians=1"
    "fs.protected_hardlinks=1"
    "fs.protected_symlinks=1"
  )
  for item in "${checks[@]}"; do
    key=${item%=*}
    expected=${item#*=}
    actual=$(runtime_get "$key")
    [[ -n $actual ]] || continue
    check_eq "$key" "$expected" "$actual"
  done

  init_security_sysctl_remove
  check_file_absent "安全配置文件已移除" "$SEC_FILE"
  check_eq "向导状态记录为 removed" removed "$(wizard_get SECURITY_SYSCTL)"

  # init_security_sysctl_remove 只清理配置，运行时值可能保留到重启；测试显式还原
  restore_runtime
  check_eq "恢复后 all.rp_filter" "${ORIG_SYSCTL[net.ipv4.conf.all.rp_filter]:-}" \
    "$(runtime_get net.ipv4.conf.all.rp_filter)"
  check_eq "恢复后 default.rp_filter" "${ORIG_SYSCTL[net.ipv4.conf.default.rp_filter]:-}" \
    "$(runtime_get net.ipv4.conf.default.rp_filter)"
}

# ---------- BBR 实际关闭 ----------
# 不预先加载模块，交给 init_bbr_enable 走 bbr_try_load 路径
ensure_bbr() {
  bbr_supported
}

test_bbr_disable() {
  section "用例：BBR 实际关闭"
  if ! ensure_bbr; then
    skip "内核未提供 BBR（tcp_bbr 模块不可用），跳过 BBR 用例"
    return 0
  fi

  # 先归一化为 cubic，确保后续启用会真正写入配置
  init_bbr_disable
  check_eq "关闭后拥塞算法" cubic "$(runtime_get net.ipv4.tcp_congestion_control)"
  check_eq "关闭后队列规则" fq_codel "$(runtime_get net.core.default_qdisc)"
  check_file_absent "关闭后 BBR 配置文件不存在" "$BBR_FILE"

  init_bbr_enable
  check_eq "启用后拥塞算法" bbr "$(runtime_get net.ipv4.tcp_congestion_control)"
  check_eq "启用后队列规则" fq "$(runtime_get net.core.default_qdisc)"
  check_eq "启用时自动加载 tcp_bbr" 1 "$(bbr_available && printf '1' || printf '0')"
  check_file_exists "启用后 BBR 配置文件已生成" "$BBR_FILE"
  local has_qdisc=1 has_cc=1
  grep -qx 'net.core.default_qdisc = fq' "$BBR_FILE" 2>/dev/null || has_qdisc=0
  grep -qx 'net.ipv4.tcp_congestion_control = bbr' "$BBR_FILE" 2>/dev/null || has_cc=0
  check_eq "配置文件包含 fq 队列" 1 "$has_qdisc"
  check_eq "配置文件包含 bbr 算法" 1 "$has_cc"
  check_eq "向导状态记录为 bbr" bbr "$(wizard_get BBR)"

  init_bbr_disable
  check_eq "实际关闭后拥塞算法" cubic "$(runtime_get net.ipv4.tcp_congestion_control)"
  check_eq "实际关闭后队列规则" fq_codel "$(runtime_get net.core.default_qdisc)"
  check_file_absent "实际关闭后配置文件已删除" "$BBR_FILE"
  check_eq "实际关闭后向导状态" cubic "$(wizard_get BBR)"

  # 模拟重启时 sysctl --system 重新加载；确认删除配置后不会回到 bbr
  local other_sources
  other_sources=$(grep -lE '^(net\.ipv4\.tcp_congestion_control|net\.core\.default_qdisc)' \
    /etc/sysctl.conf /etc/sysctl.d/*.conf 2>/dev/null | grep -vxF "$BBR_FILE" || true)
  if [[ -n $other_sources ]]; then
    info "检测到其他 sysctl 配置也设置 TCP 算法，跳过重载断言：$(printf '%s' "$other_sources" | paste -sd' ' -)"
  else
    sysctl --system >/dev/null 2>&1 || true
    check_eq "sysctl --system 后仍为 cubic" cubic "$(runtime_get net.ipv4.tcp_congestion_control)"
    check_eq "sysctl --system 后仍为 fq_codel" fq_codel "$(runtime_get net.core.default_qdisc)"
  fi
}

test_strict_rpfilter
test_bbr_disable

section "测试结果"
kv "通过" "$PASS"
kv "失败" "$FAIL"
kv "跳过" "$SKIP"
if (( FAIL > 0 )); then
  printf '失败项：\n'
  local_fail=''
  for local_fail in "${FAILED[@]}"; do
    printf '  - %s\n' "$local_fail"
  done
  exit 1
fi
ok "全部用例通过"
exit 0
