#!/usr/bin/env bash
# 配置写入与 cron 参数校验测试
# 用法：bash tests/config.sh

set -o pipefail

SST_HOME=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SST_HOME
export SST_ENTRY="$SST_HOME/st.sh"
export SST_NO_COLOR=1

# shellcheck source=../core/common.sh
source "$SST_HOME/core/common.sh"
# shellcheck source=../core/menu.sh
source "$SST_HOME/core/menu.sh"
# shellcheck source=../core/config.sh
source "$SST_HOME/core/config.sh"
# shellcheck source=../core/wizard.sh
source "$SST_HOME/core/wizard.sh"
# shellcheck source=../modules/system.sh
source "$SST_HOME/modules/system.sh"

WORK_DIR=$(mktemp -d /tmp/stbox-config-test.XXXXXX)
SST_CONFIG_DIR="$WORK_DIR/config"
SST_DATA_DIR="$WORK_DIR/data"
SST_LOG="$WORK_DIR/sst.log"
SST_WIZARD_DIR="$SST_DATA_DIR/init"
SST_WIZARD_STATE="$SST_WIZARD_DIR/state.conf"
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

section "cfg_set 值校验"
( cfg_set TEST_VALUE $'ok\nINJECT=1' ) >/dev/null 2>&1
check_eq "拒绝换行值" 1 "$?"
[[ -f $SST_CONFIG_DIR/settings.conf ]] && fail "拒绝后不应创建配置文件"
cfg_set TEST_VALUE "a=b"
check_eq "正常值可写入" "a=b" "$(cfg_get TEST_VALUE)"
cfg_set TEST_VALUE "含空格 的值"
check_eq "空格与等号保留" "含空格 的值" "$(cfg_get TEST_VALUE)"

section "wizard_set 值校验"
wizard_set TEST_KEY $'ok\nINJECT=1' >/dev/null 2>&1
check_eq "拒绝换行状态值" 1 "$?"
wizard_set TEST_KEY "normal"
check_eq "正常状态值可写入" "normal" "$(wizard_get TEST_KEY)"

section "cron 表达式校验"
check_eq "标准表达式" 0 "$(cron_schedule_valid '0 3 * * *'; echo $?)"
check_eq "步长表达式" 0 "$(cron_schedule_valid '*/5 * * * *'; echo $?)"
check_eq "列表与范围" 0 "$(cron_schedule_valid '0 0 1,15 * 1-5'; echo $?)"
check_eq "非法字符" 1 "$(cron_schedule_valid 'a b c d e'; echo $?)"
check_eq "段数不足" 1 "$(cron_schedule_valid '0 3 * *'; echo $?)"
check_eq "段数过多" 1 "$(cron_schedule_valid '0 3 * * * extra'; echo $?)"
check_eq "百分号转义" 'date +\%F' "$(cron_escape_percent 'date +%F')"

section "site 数据库密码传递"
if grep -q -- '-p"' "$SST_HOME/modules/site.sh"; then
  fail "site.sh 仍使用命令行密码参数"
else
  pass "site.sh 未使用命令行密码参数"
fi
grep -q 'MYSQL_PWD' "$SST_HOME/modules/site.sh" && pass "site.sh 使用 MYSQL_PWD" || fail "site.sh 未使用 MYSQL_PWD"

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
ok "配置与 cron 校验测试通过"
exit 0
