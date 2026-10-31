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

WORK_DIR=$(mktemp -d /tmp/stbox-ai-test.XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*" >&2; }

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

section "AI 生命周期"
check_contains "菜单含版本" "${SST_MODULE_ITEMS[ai]}" "version|版本与路径"
check_contains "菜单含更新" "${SST_MODULE_ITEMS[ai]}" "update|更新已安装"
check_contains "菜单含卸载" "${SST_MODULE_ITEMS[ai]}" "remove|卸载工具"

check_eq "按 ID 解析工具" claude "$(ai_resolve_id claude)"
check_eq "按标题解析工具" codex "$(ai_resolve_id 'Codex CLI')"
if ai_resolve_id bogus >/dev/null 2>&1; then
  fail "未知工具应解析失败"
else
  pass "未知工具解析失败"
fi

mkdir -p "$WORK_DIR/bin"
cat >"$WORK_DIR/bin/fakeai" <<'EOF'
#!/usr/bin/env bash
printf '9.9.9\n'
EOF
chmod +x "$WORK_DIR/bin/fakeai"

old_cmd=${AI_CMD[claude]}
old_kind=${AI_KIND[claude]}
AI_CMD[claude]=fakeai
AI_KIND[claude]=script
check_eq "读取命令版本" 9.9.9 "$(PATH="$WORK_DIR/bin:$PATH" ai_version_of claude)"

AI_CMD[claude]=__sst_missing_ai_cmd__
out=$(ai_update_tool claude 2>&1)
rc=$?
check_eq "未安装工具更新返回非零" 1 "$rc"
check_contains "更新提示未安装" "$out" "未安装"

out=$(ai_remove_tool claude 2>&1)
rc=$?
check_eq "未安装工具卸载返回零" 0 "$rc"
check_contains "卸载提示未安装" "$out" "未安装"

AI_CMD[claude]=$old_cmd
AI_KIND[claude]=$old_kind

section "测试结果"
kv "通过" "$PASS"
kv "失败" "$FAIL"
if (( FAIL > 0 )); then
  exit 1
fi
ok "AI 工具模块测试通过"
exit 0
