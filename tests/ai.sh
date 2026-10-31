#!/usr/bin/env bash
# AI 工具模块测试：清单、状态、官方地址（不执行安装）
# 用法：bash tests/ai.sh

set -o pipefail

SST_HOME=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SST_HOME
export SST_ENTRY="$SST_HOME/st.sh"
export SST_NO_COLOR=1

# shellcheck source=../core/common.sh
source "$SST_HOME/core/common.sh"
# shellcheck source=../core/menu.sh
source "$SST_HOME/core/menu.sh"
# shellcheck source=../modules/ai.sh
source "$SST_HOME/modules/ai.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*" >&2; }

check_contains() {
  local label=$1 haystack=$2 needle=$3
  if [[ $haystack == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label 缺少：$needle"
  fi
}

section "AI 工具注册"
check_contains "模块已注册" "${SST_MODULE_TITLE[ai]:-}" "AI 工具"
check_contains "模块菜单项" "${SST_MODULE_ITEMS[ai]:-}" "ccswitch"
check_contains "Claude Code 标题" "${AI_TITLE[claude]:-}" "Claude Code"
check_contains "CC Switch CLI 标题" "${AI_TITLE[ccswitch]:-}" "CC Switch CLI"

count=${#AI_IDS[@]}
if (( count == 16 )); then
  pass "可安装工具数量 $count"
else
  fail "可安装工具数量应为 16，实际 $count"
fi

section "AI 项目清单"
out=$(ai_list)
check_contains "清单包含 Claude Code" "$out" "Claude Code"
check_contains "清单包含 Codex" "$out" "Codex CLI"
check_contains "清单包含 Gemini" "$out" "Gemini CLI"
check_contains "清单包含 OpenCode" "$out" "OpenCode"
check_contains "清单包含 Qoder 国际版" "$out" "Qoder 国际版"
check_contains "清单包含 Qoder CN" "$out" "Qoder CN"
check_contains "清单包含 CodeBuddy 国际版" "$out" "CodeBuddy 国际版"
check_contains "清单包含 CodeBuddy 国内版" "$out" "CodeBuddy 国内版"
check_contains "清单包含 Kimi Code" "$out" "Kimi Code"
check_contains "清单包含 Claude Desktop" "$out" "Claude Desktop"

section "AI 状态与官方地址"
out=$(ai_status)
check_contains "状态表标题" "$out" "AI 工具状态"
check_contains "状态表包含 MiniMax Code" "$out" "MiniMax Code"
check_contains "状态表包含 CC Switch CLI" "$out" "CC Switch CLI"
out=$(ai_docs)
check_contains "文档包含 Claude Code" "$out" "docs.claude.com"
check_contains "文档包含 CC Switch CLI" "$out" "SaladDay/cc-switch-cli"

section "测试结果"
kv "通过" "$PASS"
kv "失败" "$FAIL"
if (( FAIL > 0 )); then
  exit 1
fi
ok "AI 工具模块测试通过"
exit 0
