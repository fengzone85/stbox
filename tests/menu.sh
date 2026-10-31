#!/usr/bin/env bash
# 菜单分发校验：模块注册完整、每个菜单动作都有对应函数
# 用法：bash tests/menu.sh

set -o pipefail

SST_HOME=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SST_HOME
export SST_ENTRY="$SST_HOME/st.sh"
export SST_NO_COLOR=1

# shellcheck source=../core/common.sh
source "$SST_HOME/core/common.sh"
# shellcheck source=../core/menu.sh
source "$SST_HOME/core/menu.sh"
# shellcheck source=../core/scripts.sh
source "$SST_HOME/core/scripts.sh"

WORK_DIR=$(mktemp -d /tmp/stbox-menu-test.XXXXXX)
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

sst_load_scripts
sst_load_modules

section "模块注册"
for m in "${SST_MODULE_ORDER[@]}"; do
  [[ -n ${SST_MODULE_TITLE[$m]:-} ]] || fail "$m 缺少模块标题"
  [[ -n ${SST_MODULE_ITEMS[$m]:-} ]] || fail "$m 缺少菜单项"
done
(( FAIL == 0 )) && pass "所有模块已注册且有菜单项"

section "菜单动作函数"
for m in "${SST_MODULE_ORDER[@]}"; do
  while IFS='|' read -r action label; do
    [[ -n $action ]] || continue
    fn="${m}_${action}"
    declare -F "$fn" >/dev/null 2>&1 && continue
    script_exists "$action" && continue
    fail "$m 缺少动作函数：$fn（$label）"
  done <<<"${SST_MODULE_ITEMS[$m]}"
done
(( FAIL == 0 )) && pass "所有菜单动作可分发"

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
ok "菜单分发校验通过"
exit 0
