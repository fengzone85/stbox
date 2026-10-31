#!/usr/bin/env bash
# 第三方脚本市场：登记经过筛选的外部脚本，下载后执行，而不是 curl | bash 直通。
# 目录：scripts/*.conf、plugins/scripts/*.conf
#
# 字段：
#   SCRIPT_TITLE    显示名称
#   SCRIPT_DESC     功能说明
#   SCRIPT_CATEGORY 测试 / 工具 / 探针 / 面板 / 节点 / 代理 / 内核 / 甲骨文 / 重装 / NAT
#   SCRIPT_URL      下载地址（HTTPS）
#   SCRIPT_MODE     bash | binary
#   SCRIPT_ARG      固定参数（可选）
#   SCRIPT_ROOT     1 需要 root（默认 1）
#   SCRIPT_RISK     低 / 中 / 高
#   SCRIPT_SHA256   可选校验值
#   SCRIPT_ARCH     可选限定架构（如 x86_64）

declare -A SST_SCRIPT_TITLE=() SST_SCRIPT_DESC=() SST_SCRIPT_CATEGORY=()
declare -A SST_SCRIPT_URL=() SST_SCRIPT_MODE=() SST_SCRIPT_ARG=()
declare -A SST_SCRIPT_ROOT=() SST_SCRIPT_RISK=() SST_SCRIPT_SHA256=()
declare -A SST_SCRIPT_ARCH=()
SST_SCRIPT_ORDER=()

sst_load_scripts() {
  SST_SCRIPT_ORDER=()
  SST_SCRIPT_TITLE=() SST_SCRIPT_DESC=() SST_SCRIPT_CATEGORY=()
  SST_SCRIPT_URL=() SST_SCRIPT_MODE=() SST_SCRIPT_ARG=()
  SST_SCRIPT_ROOT=() SST_SCRIPT_RISK=() SST_SCRIPT_SHA256=()
  SST_SCRIPT_ARCH=()

  local root file name
  for root in "$SST_HOME/scripts" "$SST_HOME/plugins/scripts"; do
    [[ -d $root ]] || continue
    for file in "$root"/*.conf; do
      [[ -f $file ]] || continue
      name=$(basename "$file" .conf)
      [[ -n ${SST_SCRIPT_TITLE[$name]:-} ]] && continue

      SCRIPT_TITLE='' SCRIPT_DESC='' SCRIPT_CATEGORY='' SCRIPT_URL=''
      SCRIPT_MODE='' SCRIPT_ARG='' SCRIPT_ROOT='' SCRIPT_RISK=''
      SCRIPT_SHA256='' SCRIPT_ARCH=''
      # shellcheck disable=SC1090
      source "$file" || { warn "脚本配置加载失败：$file"; continue; }

      [[ -n ${SCRIPT_URL:-} ]] || continue
      SST_SCRIPT_TITLE[$name]=${SCRIPT_TITLE:-$name}
      SST_SCRIPT_DESC[$name]=${SCRIPT_DESC:-}
      SST_SCRIPT_CATEGORY[$name]=${SCRIPT_CATEGORY:-工具}
      SST_SCRIPT_URL[$name]=$SCRIPT_URL
      SST_SCRIPT_MODE[$name]=${SCRIPT_MODE:-bash}
      SST_SCRIPT_ARG[$name]=${SCRIPT_ARG:-}
      SST_SCRIPT_ROOT[$name]=${SCRIPT_ROOT:-1}
      SST_SCRIPT_RISK[$name]=${SCRIPT_RISK:-中}
      SST_SCRIPT_SHA256[$name]=${SCRIPT_SHA256:-}
      SST_SCRIPT_ARCH[$name]=${SCRIPT_ARCH:-}
      SST_SCRIPT_ORDER+=("$name")
    done
  done
}

script_exists() { [[ -n ${SST_SCRIPT_TITLE[${1:-}]:-} ]]; }

scripts_run() {
  local name=$1
  shift
  script_exists "$name" || die "未知脚本：$name（可执行 st bench scripts 查看清单）"

  local url mode arg title risk need_root want_arch file rc
  url=${SST_SCRIPT_URL[$name]}
  mode=${SST_SCRIPT_MODE[$name]}
  arg=${SST_SCRIPT_ARG[$name]}
  title=${SST_SCRIPT_TITLE[$name]}
  risk=${SST_SCRIPT_RISK[$name]}
  need_root=${SST_SCRIPT_ROOT[$name]}
  want_arch=${SST_SCRIPT_ARCH[$name]}

  if [[ $need_root == 1 ]]; then
    require_root
  fi
  if [[ -n $want_arch && $want_arch != "$ARCH" ]]; then
    die "$title 仅支持 $want_arch 架构，当前为 $ARCH"
  fi

  section "$title"
  kv "说明" "${SST_SCRIPT_DESC[$name]}"
  kv "来源" "$url"
  kv "风险" "$risk"
  warn "该功能由第三方脚本提供，执行前请确认来源可信；脚本拥有当前用户权限。"
  confirm "下载并执行 $title？" || return 0

  mkdir -p "$SST_DATA_DIR/scripts" 2>/dev/null || die "无法创建脚本缓存目录"
  file="$SST_DATA_DIR/scripts/${name}-${ARCH}"
  info "下载脚本：$url"
  if ! download_with_fallback "$url" "$file" 90; then
    rm -f "$file"
    die "下载失败，请检查网络或地址"
  fi

  if [[ -n ${SST_SCRIPT_SHA256[$name]} ]]; then
    if ! printf '%s  %s\n' "${SST_SCRIPT_SHA256[$name]}" "$file" | sha256sum -c - >/dev/null 2>&1; then
      rm -f "$file"
      die "SHA256 校验失败，已阻止执行"
    fi
    ok "SHA256 校验通过"
  fi

  chmod +x "$file" 2>/dev/null || true
  local -a cmd
  if [[ $mode == binary ]]; then
    cmd=("$file")
  else
    cmd=(bash "$file")
    if [[ -n $arg ]]; then
      local -a fixed=()
      read -r -a fixed <<<"$arg"
      cmd+=("${fixed[@]}")
    fi
  fi
  cmd+=("$@")

  info "开始执行：${cmd[*]}"
  "${cmd[@]}"
  rc=$?
  if (( rc == 0 )); then
    ok "$title 执行完成"
  else
    warn "$title 退出码：$rc（部分测试脚本在未达标时会返回非 0）"
  fi
  info "脚本已缓存：$file"
}

scripts_menu() {
  local filter=${1:-全部} choice idx name meta title
  local -a names=()

  for name in "${SST_SCRIPT_ORDER[@]}"; do
    case $filter in
      全部) ;;
      测试) [[ ${SST_SCRIPT_CATEGORY[$name]} == "测试" ]] || continue ;;
      工具) [[ ${SST_SCRIPT_CATEGORY[$name]} == "工具" ]] || continue ;;
      *) [[ ${SST_SCRIPT_CATEGORY[$name]} == "$filter" ]] || continue ;;
    esac
    names+=("$name")
  done

  if [[ ${#names[@]} -eq 0 ]]; then
    warn "该分类下暂无脚本"
    return 1
  fi

  while true; do
    section "脚本市场（${filter}）"
    for idx in "${!names[@]}"; do
      name=${names[$idx]}
      title=${SST_SCRIPT_TITLE[$name]}
      meta=${SST_SCRIPT_RISK[$name]}
      [[ -n $meta ]] && meta="$meta · "
      ui_menu_item "$((idx + 1))" "$title" "${meta}${SST_SCRIPT_DESC[$name]}"
    done
    ui_menu_footer
    ui_read_choice "请选择脚本" || break
    choice=$UI_CHOICE
    case $choice in
      0|q|back) break ;;
      [0-9]|[0-9][0-9])
        idx=$((choice - 1))
        if (( idx >= 0 && idx < ${#names[@]} )); then
          scripts_run "${names[$idx]}"
          pause
        else
          warn "无效编号：$choice"
        fi
        ;;
      *)
        if script_exists "$choice"; then
          scripts_run "$choice"
          pause
        else
          warn "未知脚本：$choice"
        fi
        ;;
    esac
  done
}
