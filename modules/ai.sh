#!/usr/bin/env bash
# 模块：常用 AI 编程工具部署（Claude Code / Codex / Gemini CLI / OpenCode 等）

sst_register_module ai "AI 工具" "Claude Codex Gemini OpenCode 等"
SST_MODULE_ITEMS[ai]=$'status|已安装与可用\ninstall|选择安装\nversion|版本与路径\nupdate|更新已安装\nremove|卸载工具\nlist|项目清单\nccswitch|CC Switch CLI\nclaude|Claude Code\ncodex|Codex CLI\ngemini|Gemini CLI\nqoder|Qoder 国际版\nqodercn|Qoder CN\ncodebuddy|CodeBuddy 国际版\ncodebuddycn|CodeBuddy 国内版\ngrok|Grok Build\nopencode|OpenCode\nopenclaw|OpenClaw\nhermes|Hermes Agent\npi|Pi Coding Agent\nminimax|MiniMax Code\nkimi|Kimi Code\nohmy|Oh My Pi\ndocs|官方地址'

AI_IDS=(claude codex gemini qoder qodercn codebuddy codebuddycn grok opencode openclaw hermes pi minimax kimi ohmy ccswitch)
declare -gA AI_TITLE=(
  [claude]="Claude Code"
  [codex]="Codex CLI"
  [gemini]="Gemini CLI"
  [qoder]="Qoder 国际版"
  [qodercn]="Qoder CN"
  [codebuddy]="CodeBuddy 国际版"
  [codebuddycn]="CodeBuddy 国内版"
  [grok]="Grok Build"
  [opencode]="OpenCode"
  [openclaw]="OpenClaw"
  [hermes]="Hermes Agent"
  [pi]="Pi Coding Agent"
  [minimax]="MiniMax Code"
  [kimi]="Kimi Code"
  [ohmy]="Oh My Pi"
  [ccswitch]="CC Switch CLI"
)
declare -gA AI_CMD=(
  [claude]=claude
  [codex]=codex
  [gemini]=gemini
  [qoder]=qodercli
  [qodercn]=qoderclicn
  [codebuddy]=codebuddy
  [codebuddycn]=codebuddy
  [grok]=grok
  [opencode]=opencode
  [openclaw]=openclaw
  [hermes]=hermes
  [pi]=pi
  [minimax]=mcode
  [kimi]=kimi
  [ohmy]=oh-my-pi
  [ccswitch]=cc-switch
)
declare -gA AI_KIND=(
  [claude]=npm
  [codex]=npm
  [gemini]=npm
  [qoder]=npm
  [qodercn]=npm
  [codebuddy]=npm
  [codebuddycn]=npm
  [grok]=script
  [opencode]=script
  [openclaw]=script
  [hermes]=script
  [pi]=npm
  [minimax]=npm
  [kimi]=script
  [ohmy]=npm
  [ccswitch]=script
)
declare -gA AI_SOURCE=(
  [claude]="@anthropic-ai/claude-code"
  [codex]="@openai/codex"
  [gemini]="@google/gemini-cli"
  [qoder]="@qoder-ai/qodercli"
  [qodercn]="@qodercn-ai/qoderclicn"
  [codebuddy]="@tencent-ai/codebuddy-code"
  [codebuddycn]="@tencent-ai/codebuddy-code"
  [grok]="https://x.ai/cli/install.sh"
  [opencode]="https://opencode.ai/install"
  [openclaw]="https://openclaw.ai/install.sh"
  [hermes]="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"
  [pi]="@earendil-works/pi-coding-agent"
  [minimax]="@minimax-ai/code"
  [kimi]="https://code.kimi.com/kimi-code/install.sh"
  [ohmy]="oh-my-pi"
  [ccswitch]="https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh"
)
declare -gA AI_DESC=(
  [claude]="Anthropic 官方终端编程助手"
  [codex]="OpenAI 官方终端编程助手"
  [gemini]="Google Gemini 终端助手"
  [qoder]="Qoder 国际版终端 Agent"
  [qodercn]="Qoder CN（原通义灵码）终端 Agent"
  [codebuddy]="腾讯 CodeBuddy 国际版 CLI"
  [codebuddycn]="腾讯 CodeBuddy 国内版 CLI（同一命令，国内登录）"
  [grok]="xAI Grok Build 终端助手"
  [opencode]="开源终端 AI 编程工具"
  [openclaw]="开源 AI 助手与工作区"
  [hermes]="带长期记忆的开源 AI Agent"
  [pi]="Pi 终端编程 Agent"
  [minimax]="MiniMax Code 终端助手"
  [kimi]="Moonshot Kimi Code 终端助手"
  [ohmy]="Pi 扩展/增强工具"
  [ccswitch]="无界面版 CC Switch，服务器集中切换供应商"
)
declare -gA AI_DOC=(
  [claude]="https://docs.claude.com/en/docs/claude-code/overview"
  [codex]="https://github.com/openai/codex"
  [gemini]="https://github.com/google-gemini/gemini-cli"
  [qoder]="https://docs.qoder.com/cli/quick-start"
  [qodercn]="https://docs.qoder.cn/cli/installation"
  [codebuddy]="https://www.codebuddy.ai/docs/zh/cli/quickstart"
  [codebuddycn]="https://copilot.tencent.com/docs/cli/quickstart"
  [grok]="https://docs.x.ai/build/overview"
  [opencode]="https://opencode.ai"
  [openclaw]="https://openclaw.ai"
  [hermes]="https://github.com/NousResearch/hermes-agent"
  [pi]="https://pi.dev"
  [minimax]="https://github.com/MiniMax-AI/cli"
  [kimi]="https://www.kimi.com/code"
  [ohmy]="https://www.npmjs.com/package/oh-my-pi"
  [ccswitch]="https://github.com/SaladDay/cc-switch-cli"
)

ai_require_node() {
  have npm && return 0
  info "未检测到 npm，先安装 Node.js 与 npm…"
  pkg_update || return 1
  pkg_install nodejs npm || return 1
  have npm || die "Node.js/npm 安装失败"
}

ai_after_install_hint() {
  case $1 in
    qoder) info "Qoder 国际版首次运行：qodercli" ;;
    qodercn) info "Qoder CN 首次运行：qoderclicn" ;;
    codebuddy) info "CodeBuddy 国际版首次运行：codebuddy，登录时选择国际站" ;;
    codebuddycn)
      info "CodeBuddy 国内版：codebuddy 登录时选择国内站，或设置 CODEBUDDY_INTERNET_ENVIRONMENT=internal"
      ;;
  esac
}

ai_install_npm() {
  local id=$1 title=${AI_TITLE[$1]} pkg=${AI_SOURCE[$1]} cmd=${AI_CMD[$1]}
  require_root
  ai_require_node || return 1
  if have "$cmd"; then
    info "已安装：$(command -v "$cmd")"
    confirm "重新安装/升级 $title？" || { ai_after_install_hint "$id"; return 0; }
  else
    confirm "通过 npm 安装 $title（$pkg）？" || return 0
  fi
  if npm install -g "$pkg"; then
    ok "$title 安装完成：$(command -v "$cmd")"
    ai_after_install_hint "$id"
  else
    warn "$title 安装失败，请检查 npm 源或 Node.js 版本要求"
    return 1
  fi
}

ai_install_script() {
  local id=$1 title=${AI_TITLE[$1]} url=${AI_SOURCE[$1]}
  require_root
  ensure_tool curl curl || return 1
  section "安装 $title"
  kv "来源" "$url"
  warn "该安装脚本来自第三方项目，执行前请确认来源可信。"
  confirm "下载并执行 $title 安装脚本？" || return 0
  ai_run_script "$id"
}

# 执行第三方安装脚本（不含确认，供安装/更新复用）
ai_run_script() {
  local id=$1 title=${AI_TITLE[$1]} url=${AI_SOURCE[$1]} tmp rc
  tmp=$(mktemp) || return 1
  if ! download_with_fallback "$url" "$tmp" 120; then
    rm -f "$tmp"
    warn "$title 安装脚本下载失败，可访问官方文档手动安装：${AI_DOC[$id]}"
    return 1
  fi
  bash "$tmp"
  rc=$?
  rm -f "$tmp"
  if (( rc == 0 )); then
    ok "$title 安装流程完成"
  else
    warn "$title 安装脚本退出码：$rc，请查看官方文档：${AI_DOC[$id]}"
    return 1
  fi
}

ai_install_tool() {
  local id=$1
  [[ -n ${AI_TITLE[$id]:-} ]] || die "未知 AI 工具：$id"
  case ${AI_KIND[$id]} in
    npm) ai_install_npm "$id" ;;
    script) ai_install_script "$id" ;;
    *) die "暂不支持自动安装：${AI_TITLE[$id]}" ;;
  esac
}

ai_resolve_id() {
  local key=$1 id
  [[ -n $key ]] || return 1
  for id in "${AI_IDS[@]}"; do
    [[ $key == "$id" || $key == "${AI_CMD[$id]}" || $key == "${AI_TITLE[$id]}" ]] || continue
    printf '%s\n' "$id"
    return 0
  done
  return 1
}

# 选择已安装工具，结果写入 AI_PICKED
ai_pick_installed() {
  local title=$1 id labels=() ids=()
  for id in "${AI_IDS[@]}"; do
    have "${AI_CMD[$id]}" || continue
    ids+=("$id")
    labels+=("${AI_TITLE[$id]}（${AI_CMD[$id]}）")
  done
  if (( ${#ids[@]} == 0 )); then
    info "没有检测到已安装的 AI 工具"
    return 1
  fi
  ui_menu_list "$(printf '%s\n' "${labels[@]}")" "返回"
  ui_read_choice "$title" || return 1
  local choice=$UI_CHOICE
  if ! [[ $choice =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#ids[@]} )); then
    warn "无效编号：$choice"
    return 1
  fi
  AI_PICKED=${ids[$((choice - 1))]}
}

ai_version_of() {
  local id=$1 cmd=${AI_CMD[$1]} out=''
  if [[ ${AI_KIND[$id]} == npm ]] && have npm; then
    out=$(npm ls -g --depth=0 "${AI_SOURCE[$id]}" 2>/dev/null | grep -F "${AI_SOURCE[$id]}@" | head -n1)
    out=${out##*@}
  fi
  if [[ -z $out ]]; then
    if have timeout; then
      out=$(timeout 5 "$cmd" --version 2>/dev/null </dev/null | head -n1)
    else
      out=$("$cmd" --version 2>/dev/null </dev/null | head -n1)
    fi
  fi
  printf '%s\n' "${out:-未知}"
}

ai_version() {
  local id state ver path
  section "AI 工具版本"
  printf '  %-18s %-10s %-18s %s\n' "工具" "状态" "版本" "命令"
  hr
  for id in "${AI_IDS[@]}"; do
    if have "${AI_CMD[$id]}"; then
      state="已安装"
      path=$(command -v "${AI_CMD[$id]}")
      ver=$(ai_version_of "$id")
    else
      state="未安装"
      path=${AI_DOC[$id]}
      ver="-"
    fi
    printf '  %-18s %-10s %-18s %s\n' "${AI_TITLE[$id]}" "$state" "$ver" "$path"
  done
}

ai_update_tool() {
  local id=$1 title=${AI_TITLE[$1]}
  have "${AI_CMD[$id]}" || { warn "$title 未安装，请先安装：st ai $id"; return 1; }
  case ${AI_KIND[$id]} in
    npm)
      require_root
      ai_require_node || return 1
      confirm "更新 $title 到最新版本？" || return 0
      if npm install -g "${AI_SOURCE[$id]}@latest"; then
        ok "$title 已更新：$(ai_version_of "$id")"
      else
        warn "$title 更新失败，请检查 npm 源或网络"
        return 1
      fi
      ;;
    script)
      confirm "重新执行 $title 安装脚本以更新？" || return 0
      ai_run_script "$id"
      ;;
  esac
}

ai_update() {
  local id=${1:-}
  if [[ -z $id ]]; then
    ai_pick_installed "选择要更新的工具" || return 0
    id=$AI_PICKED
  else
    id=$(ai_resolve_id "$id") || die "未知 AI 工具：$1"
  fi
  ai_update_tool "$id"
}

ai_remove_tool() {
  local id=$1 title=${AI_TITLE[$1]}
  if ! have "${AI_CMD[$id]}"; then
    info "$title 未安装"
    return 0
  fi
  case ${AI_KIND[$id]} in
    npm)
      require_root
      [[ $id == codebuddy || $id == codebuddycn ]] && warn "CodeBuddy 国际版/国内版共用同一命令，卸载后两者均不可用"
      confirm "卸载 $title（npm uninstall -g ${AI_SOURCE[$id]}）？" || return 0
      if npm uninstall -g "${AI_SOURCE[$id]}"; then
        ok "$title 已卸载"
      else
        warn "$title 卸载失败"
        return 1
      fi
      ;;
    script)
      warn "$title 由第三方安装脚本管理，本工具不自动卸载"
      info "手动卸载方式参考：${AI_DOC[$id]}"
      ;;
  esac
}

ai_remove() {
  local id=${1:-}
  if [[ -z $id ]]; then
    ai_pick_installed "选择要卸载的工具" || return 0
    id=$AI_PICKED
  else
    id=$(ai_resolve_id "$id") || die "未知 AI 工具：$1"
  fi
  ai_remove_tool "$id"
}

ai_status() {
  local id cmd state path
  section "AI 工具状态"
  printf '  %-18s %-10s %s\n' "工具" "状态" "命令"
  hr
  for id in "${AI_IDS[@]}"; do
    cmd=${AI_CMD[$id]}
    if have "$cmd"; then
      state="已安装"
      path=$(command -v "$cmd")
    else
      state="未安装"
      path=${AI_DOC[$id]}
    fi
    printf '  %-18s %-10s %s\n' "${AI_TITLE[$id]}" "$state" "$path"
  done
}

ai_list() {
  local id
  section "AI 项目清单"
  printf '  %-20s %-12s %s\n' "工具" "命令" "说明"
  hr
  for id in "${AI_IDS[@]}"; do
    printf '  %-20s %-12s %s\n' "${AI_TITLE[$id]}" "${AI_CMD[$id]}" "${AI_DESC[$id]}"
  done
  printf '  %-20s %-12s %s\n' "Claude Desktop" "-" "仅桌面版，服务器环境请使用 Claude Code"
}

ai_install_menu() {
  local choice id i labels=()
  for id in "${AI_IDS[@]}"; do
    labels+=("${AI_TITLE[$id]}")
  done
  ui_menu_list "$(printf '%s\n' "${labels[@]}")" "返回"
  ui_read_choice "选择要安装的工具" || return 0
  choice=$UI_CHOICE
  if ! [[ $choice =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#AI_IDS[@]} )); then
    warn "无效编号：$choice"
    return 0
  fi
  ai_install_tool "${AI_IDS[$((choice - 1))]}"
}

ai_docs() {
  local id
  section "官方地址"
  for id in "${AI_IDS[@]}"; do
    kv "${AI_TITLE[$id]}" "${AI_DOC[$id]}"
  done
  kv "Claude Desktop" "https://claude.ai/download（仅桌面版）"
  printf '\n'
  info "服务器无桌面环境时，优先使用 CC Switch CLI：st ai ccswitch"
}

ai_ccswitch() { ai_install_tool ccswitch; }
ai_claude() { ai_install_tool claude; }
ai_codex() { ai_install_tool codex; }
ai_gemini() { ai_install_tool gemini; }
ai_qoder() { ai_install_tool qoder; }
ai_qodercn() { ai_install_tool qodercn; }
ai_codebuddy() { ai_install_tool codebuddy; }
ai_codebuddycn() { ai_install_tool codebuddycn; }
ai_grok() { ai_install_tool grok; }
ai_opencode() { ai_install_tool opencode; }
ai_openclaw() { ai_install_tool openclaw; }
ai_hermes() { ai_install_tool hermes; }
ai_pi() { ai_install_tool pi; }
ai_minimax() { ai_install_tool minimax; }
ai_kimi() { ai_install_tool kimi; }
ai_ohmy() { ai_install_tool ohmy; }
