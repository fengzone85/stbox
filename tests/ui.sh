#!/usr/bin/env bash
# 界面组件单元测试：向导进度、危险确认面板
# 用法：bash tests/ui.sh

set -o pipefail

SST_HOME=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SST_HOME
export SST_ENTRY="$SST_HOME/st.sh"
export SST_YES=0
export SST_NO_COLOR=1

# shellcheck source=../core/common.sh
source "$SST_HOME/core/common.sh"
# shellcheck source=../core/config.sh
source "$SST_HOME/core/config.sh"
# shellcheck source=../core/wizard.sh
source "$SST_HOME/core/wizard.sh"
# shellcheck source=../core/menu.sh
source "$SST_HOME/core/menu.sh"

WORK_DIR=$(mktemp -d /tmp/stbox-ui-test.XXXXXX)
SST_CONFIG_DIR="$WORK_DIR/config"
SST_DATA_DIR="$WORK_DIR/data"
SST_WIZARD_DIR="$SST_DATA_DIR/init"
SST_WIZARD_STATE="$SST_WIZARD_DIR/state.conf"
SST_LOG="$WORK_DIR/sst.log"
mkdir -p "$SST_CONFIG_DIR" "$SST_DATA_DIR/backups" "$SST_WIZARD_DIR"

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

check_not_contains() {
  local label=$1 haystack=$2 needle=$3
  if [[ $haystack != *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label 不应包含：$needle"
  fi
}

check_line_count() {
  local label=$1 expected=$2 text=$3 count
  count=$(printf '%s\n' "$text" | grep -c . 2>/dev/null || true)
  check_eq "$label" "$expected" "$count"
}

check_lines_within() {
  local label=$1 max=$2 text=$3 line width bad=0
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    width=$(ui_text_width "$line")
    if (( width > max )); then
      fail "$label 行宽 $width 超过 $max：$line"
      bad=1
    fi
  done <<<"$text"
  (( bad == 0 )) && pass "$label（所有行 <= $max）"
}

write_state() {
  local -A statuses=()
  local step pair
  for step in "${SST_WIZARD_STEPS[@]}"; do
    statuses[$step]=pending
  done
  for pair in "$@"; do
    statuses[${pair%%=*}]=${pair#*=}
  done
  {
    printf 'VERSION=2\n'
    for step in "${SST_WIZARD_STEPS[@]}"; do
      printf 'STEP_%s=%s\n' "$step" "${statuses[$step]}"
    done
  } >"$SST_WIZARD_STATE"
  chmod 600 "$SST_WIZARD_STATE" 2>/dev/null || true
}

# ---------- 向导进度 ----------
section "向导进度：无状态文件"
rm -f "$SST_WIZARD_STATE"
wizard_status_table >/dev/null
[[ ! -e $SST_WIZARD_STATE ]] && pass "状态表只读，不创建状态文件" || fail "状态表创建了状态文件"
check_eq "完成数" 0 "$(wizard_done_count)"
check_eq "下一步" preflight "$(wizard_next_step)"
check_eq "进度摘要" "0/8 完成 · 下一步：服务器预检" "$(wizard_progress_meta)"
check_eq "pending 状态文案" 待执行 "$(wizard_step_state_text pending)"

section "向导进度：部分完成与跳过"
write_state preflight=done disk=done basics=skipped accounts=pending
check_eq "完成数只统计 done" 2 "$(wizard_done_count)"
check_eq "下一步跳过 skipped" accounts "$(wizard_next_step)"
check_eq "进度摘要" "2/8 完成 · 下一步：账户设置" "$(wizard_progress_meta)"
check_eq "done 状态文案" 已完成 "$(wizard_step_state_text done)"
check_eq "skipped 状态文案" 已跳过 "$(wizard_step_state_text skipped)"
check_eq "in_progress 状态文案" 进行中 "$(wizard_step_state_text in_progress)"

section "向导进度：全部完成"
write_state preflight=done disk=done basics=done accounts=done ssh=done firewall=done hardening=done report=done
check_eq "完成数" 8 "$(wizard_done_count)"
check_eq "下一步为空" "" "$(wizard_next_step)"
check_eq "进度摘要" "全部完成 · 可生成报告" "$(wizard_progress_meta)"

section "向导进度：完成加跳过"
write_state preflight=done disk=done basics=skipped accounts=skipped ssh=done firewall=done hardening=done report=done
check_eq "完成数" 6 "$(wizard_done_count)"
check_eq "下一步为空" "" "$(wizard_next_step)"
check_eq "进度摘要" "6/8 完成 · 可生成报告" "$(wizard_progress_meta)"

section "向导步骤条"
write_state preflight=done disk=done basics=skipped accounts=pending
UI_WIDTH=80
UI_UNICODE=1
ui_set_symbols
out=$(sst_wizard_checklist)
check_contains "80 列显示预检完成" "$out" "✓ 预检"
check_contains "80 列显示跳过标记" "$out" "! 基础"
check_contains "80 列显示下一步" "$out" "→ 账户"
check_contains "80 列显示待执行项" "$out" "· SSH"
check_line_count "80 列为 4 列布局" 2 "$out"

UI_WIDTH=40
out=$(sst_wizard_checklist)
check_line_count "40 列为 2 列布局" 4 "$out"
check_lines_within "40 列步骤条不溢出" 40 "$out"

UI_WIDTH=80
UI_UNICODE=0
ui_set_symbols
out=$(sst_wizard_checklist)
check_contains "ASCII 完成标记" "$out" "[OK] 预检"
check_contains "ASCII 下一步标记" "$out" "-> 账户"

section "向导状态表"
UI_UNICODE=1
UI_WIDTH=80
ui_set_symbols
out=$(wizard_status_table)
check_contains "状态表标题" "$out" "开荒进度"
check_contains "状态表步骤名" "$out" "服务器预检"
check_contains "状态表已完成" "$out" "已完成"
check_contains "状态表已跳过" "$out" "已跳过"
check_contains "状态表待执行" "$out" "待执行"

# ---------- 二级菜单组件 ----------
section "二级菜单组件"
UI_WIDTH=80
UI_UNICODE=1
ui_set_symbols
out=$(ui_menu_list $'选项一\n选项二' "返回")
check_contains "菜单包含选项一" "$out" "选项一"
check_contains "菜单包含选项二" "$out" "选项二"
check_contains "菜单自动追加返回项" "$out" "0  返回"

out=$(ui_menu_footer "取消")
check_contains "自定义返回文案" "$out" "0  取消"

UI_CHOICE=''
ui_read_choice "测试选择" < <(printf '2\n') >/dev/null
rc=$?
check_eq "读取选择返回码" 0 "$rc"
check_eq "读取选择值" 2 "$UI_CHOICE"

UI_WIDTH=40
out=$(ui_menu_item 1 "这是一个很长的二级菜单选项名称，需要在窄终端下截断" "附加说明")
check_lines_within "窄终端菜单项不溢出" 40 "$out"
UI_WIDTH=80

# ---------- 危险确认面板 ----------
section "危险面板：Unicode 与宽终端"
UI_WIDTH=80
UI_UNICODE=1
ui_set_symbols
out=$(ui_danger_panel "危险操作" \
  "将关闭防火墙，所有端口会直接暴露。" \
  "影响：公网服务、Docker 端口与 SSH" \
  "回滚：st security firewall_enable")
check_contains "面板边框" "$out" "╭─ 危险操作"
check_contains "面板消息" "$out" "将关闭防火墙"
check_contains "面板影响" "$out" "影响："
check_contains "面板回滚" "$out" "回滚："
check_contains "面板底边" "$out" "╰"
check_lines_within "Unicode 面板不溢出" "$(ui_frame_width)" "$out"

section "危险面板：ASCII 与窄终端"
UI_WIDTH=60
UI_UNICODE=0
ui_set_symbols
out=$(ui_danger_panel "危险操作" "将关闭防火墙。" "所有端口" "st security firewall_enable")
check_contains "ASCII 面板边框" "$out" "+- 危险操作"
check_lines_within "ASCII 面板不溢出" 60 "$out"

UI_WIDTH=40
out=$(ui_danger_panel "危险操作" \
  "将关闭防火墙，所有端口会直接暴露到公网，请确认当前 SSH 会话仍然可用，并准备通过控制台回滚。" \
  "公网服务、Docker 端口与 SSH" \
  "st security firewall_enable")
check_lines_within "窄终端面板自动换行" 40 "$out"
count=$(printf '%s\n' "$out" | grep -c . 2>/dev/null || true)
(( count >= 6 )) && pass "窄终端面板包含多行（$count 行）" || fail "窄终端面板行数过少（$count 行）"

section "危险确认：确认与取消"
confirm() {
  CONFIRM_CALLS=$((CONFIRM_CALLS + 1))
  CONFIRM_PROMPT=${1:-}
  return "${CONFIRM_RESULT:-0}"
}
run_confirm() {
  CONFIRM_CALLS=0
  CONFIRM_PROMPT=''
  ui_confirm_danger "将关闭防火墙。" "所有端口直接暴露" "st security firewall_enable" \
    >"$WORK_DIR/confirm.out" 2>&1
  CONFIRM_RC=$?
}

SST_YES=0
CONFIRM_RESULT=0
run_confirm
check_eq "确认返回码" 0 "$CONFIRM_RC"
check_eq "confirm 调用次数" 1 "$CONFIRM_CALLS"
check_eq "确认提示" "确认继续？" "$CONFIRM_PROMPT"
out=$(cat "$WORK_DIR/confirm.out")
check_contains "确认前显示危险面板" "$out" "危险操作"
check_contains "确认前显示影响" "$out" "影响："

CONFIRM_RESULT=1
run_confirm
check_eq "取消返回码" 1 "$CONFIRM_RC"
check_eq "取消调用次数" 1 "$CONFIRM_CALLS"

section "危险确认：--yes 跳过面板"
SST_YES=1
CONFIRM_CALLS=0
ui_confirm_danger "将关闭防火墙。" "所有端口直接暴露" "st security firewall_enable" \
  >"$WORK_DIR/confirm-yes.out" 2>&1
CONFIRM_RC=$?
check_eq "--yes 返回码" 0 "$CONFIRM_RC"
check_eq "--yes 不调用 confirm" 0 "$CONFIRM_CALLS"
[[ ! -s "$WORK_DIR/confirm-yes.out" ]] && pass "--yes 不输出面板" || fail "--yes 仍输出面板"
SST_YES=0

section "危险确认：可省略影响与回滚"
CONFIRM_RESULT=0
CONFIRM_CALLS=0
ui_confirm_danger "仅显示风险说明。" >"$WORK_DIR/confirm-no-extra.out" 2>&1
out=$(cat "$WORK_DIR/confirm-no-extra.out")
check_contains "无附加信息时仍显示面板" "$out" "危险操作"
check_not_contains "无影响行" "$out" "影响："
check_not_contains "无回滚行" "$out" "回滚："
check_eq "无附加信息仍调用确认" 1 "$CONFIRM_CALLS"

section "日志降级"
out=$(SST_LOG=/sys/stbox-test.log sst_log INFO "日志降级" 2>&1)
check_eq "日志不可写时静默" "" "$out"

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
ok "全部界面用例通过"
exit 0
