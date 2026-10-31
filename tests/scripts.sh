#!/usr/bin/env bash
# 脚本市场清单校验：字段完整性、URL 协议、新增条目
# 用法：bash tests/scripts.sh

set -o pipefail

SST_HOME=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SST_HOME
export SST_ENTRY="$SST_HOME/st.sh"
export SST_NO_COLOR=1

# shellcheck source=../core/common.sh
source "$SST_HOME/core/common.sh"
# shellcheck source=../core/scripts.sh
source "$SST_HOME/core/scripts.sh"

WORK_DIR=$(mktemp -d /tmp/stbox-scripts-test.XXXXXX)
SST_CONFIG_DIR="$WORK_DIR/config"
SST_DATA_DIR="$WORK_DIR/data"
SST_LOG="$WORK_DIR/sst.log"
mkdir -p "$SST_CONFIG_DIR" "$SST_DATA_DIR/backups"
trap 'rm -rf "$WORK_DIR"' EXIT

PASS=0
FAIL=0
declare -a FAILED=()

pass() { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); FAILED+=("$*"); printf '  [FAIL] %s\n' "$*" >&2; }

sst_load_scripts

section "脚本清单数量"
count=${#SST_SCRIPT_ORDER[@]}
if (( count >= 60 )); then
  pass "脚本数量 $count"
else
  fail "脚本数量过少：$count"
fi

section "字段完整性"
for name in "${SST_SCRIPT_ORDER[@]}"; do
  title=${SST_SCRIPT_TITLE[$name]:-}
  url=${SST_SCRIPT_URL[$name]:-}
  mode=${SST_SCRIPT_MODE[$name]:-}
  risk=${SST_SCRIPT_RISK[$name]:-}
  root=${SST_SCRIPT_ROOT[$name]:-}
  category=${SST_SCRIPT_CATEGORY[$name]:-}

  [[ -n $title ]] || fail "$name 缺少标题"
  [[ -n $url ]] || fail "$name 缺少 URL"
  [[ -n $category ]] || fail "$name 缺少分类"
  [[ $url == https://* || $url == http://* ]] || fail "$name URL 协议无效：$url"
  [[ $mode == bash || $mode == binary ]] || fail "$name 模式无效：$mode"
  [[ $root == 0 || $root == 1 ]] || fail "$name SCRIPT_ROOT 无效：$root"
  [[ $risk == 低 || $risk == 中 || $risk == 高 ]] || fail "$name 风险等级无效：$risk"
done
(( FAIL == 0 )) && pass "所有脚本字段完整"

section "新增脚本条目"
for name in nodebench tcpquality autotrace nodequality ipcheck taier hardware-info acme ansible cf-tunnel image realm gost; do
  if script_exists "$name"; then
    pass "新增脚本：$name"
  else
    fail "缺少脚本：$name"
  fi
done

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
ok "脚本清单校验通过"
exit 0
