#!/usr/bin/env bash
# 单文件产物校验：内嵌清单、运行入口、自安装
# 用法：bash build.sh && bash tests/bundle.sh

set -o pipefail

export SST_NO_COLOR=1
SST_HOME=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
BUNDLE="$SST_HOME/stbox.sh"
VERSION=$(cat "$SST_HOME/VERSION")

# shellcheck source=../core/common.sh
source "$SST_HOME/core/common.sh"

WORK_DIR=$(mktemp -d /tmp/stbox-bundle-test.XXXXXX)
SST_LOG="$WORK_DIR/sst.log"
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

check_contains() {
  local label=$1 haystack=$2 needle=$3
  if [[ $haystack == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label 缺少：$needle"
  fi
}

section "产物完整性"
[[ -f $BUNDLE ]] || { fail "缺少 stbox.sh，请先执行 bash build.sh"; exit 1; }
[[ -x $BUNDLE ]] && pass "stbox.sh 可执行" || fail "stbox.sh 不可执行"
check_contains "shebang" "$(head -1 "$BUNDLE")" '#!/usr/bin/env bash'
check_contains "单文件标记" "$(head -4 "$BUNDLE")" 'SST_BUNDLED=1'
check_contains "内嵌版本" "$(head -4 "$BUNDLE")" "SST_VERSION=\"$VERSION\""
bash -n "$BUNDLE" && pass "语法检查" || fail "语法检查失败"
if grep -q 'source "$SST_HOME/core' "$BUNDLE"; then
  fail "单文件仍引用外部 core 目录"
else
  pass "单文件不引用外部 core 目录"
fi

section "内嵌清单"
check_eq "应用数量" 12 "$(grep -c '^SST_APP_ORDER+=(' "$BUNDLE")"
check_eq "脚本数量" 72 "$(grep -c '^SST_SCRIPT_ORDER+=(' "$BUNDLE")"
check_eq "模块数量" 14 "$(grep -c '^SST_MODULE_ITEMS\[' "$BUNDLE")"
grep -q 'stbox_write_ssh_rollback' "$BUNDLE" && pass "包含 SSH 回滚脚本生成器" || fail "缺少 SSH 回滚脚本生成器"

section "运行入口"
out=$(STBOX_STATE_DIR="$WORK_DIR/state" bash "$BUNDLE" --no-color version 2>&1)
check_contains "版本信息" "$out" "单文件"
check_contains "版本号" "$out" "$VERSION"
out=$(STBOX_STATE_DIR="$WORK_DIR/state" bash "$BUNDLE" --no-color apps list 2>&1)
check_eq "应用清单行数" 12 "$(grep -c '已部署\|未部署' <<<"$out")"
out=$(STBOX_STATE_DIR="$WORK_DIR/state" bash "$BUNDLE" --no-color ai list 2>&1)
check_contains "AI 清单 Qoder CN" "$out" "Qoder CN"
out=$(STBOX_STATE_DIR="$WORK_DIR/state" bash "$BUNDLE" --no-color tools scripts 2>&1)
check_contains "脚本市场条目" "$out" "Aria2"

section "安装器"
[[ -f $SST_HOME/i.sh ]] && pass "存在 i.sh" || fail "缺少 i.sh"
bash -n "$SST_HOME/i.sh" && pass "i.sh 语法检查" || fail "i.sh 语法检查失败"
grep -q 'stbox.sh.sha256' "$SST_HOME/i.sh" && pass "安装器校验 SHA256" || fail "安装器未校验 SHA256"

section "自安装"
if [[ ${EUID:-1} -eq 0 ]]; then
  out=$(STBOX_BIN_DIR="$WORK_DIR/bin" STBOX_STATE_DIR="$WORK_DIR/state" \
    bash "$BUNDLE" --no-color --yes install 2>&1)
  if [[ -x $WORK_DIR/bin/st ]]; then
    pass "安装到临时目录"
    check_contains "安装输出" "$out" "已安装"
    out=$(STBOX_STATE_DIR="$WORK_DIR/state" "$WORK_DIR/bin/st" --no-color version 2>&1)
    check_contains "安装后可运行" "$out" "单文件"
  else
    fail "自安装失败"
  fi
else
  printf '  [SKIP] 非 root，跳过自安装（CI 容器内会执行）\n'
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
ok "单文件产物校验通过"
exit 0
