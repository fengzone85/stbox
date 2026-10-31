#!/usr/bin/env bash
# 界面层：能力检测、配色、Unicode/ASCII 符号、显示宽度、面板与菜单组件
# 由 core/common.sh 自动加载；业务模块只使用 common.sh 的 section/kv/info 等封装。

UI_COLOR_ENABLED=0
UI_UNICODE=0
UI_UTF8_LOCALE=0
UI_WIDTH=${COLUMNS:-80}
UI_FRAME_MAX=${SST_UI_FRAME_MAX:-72}
UI_CHAR_WIDTH=1

# ---------- 能力检测 ----------
ui_locale_utf8() {
  local charmap=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
  case $charmap in
    *UTF-8*|*utf-8*|*utf8*|*UTF8*) return 0 ;;
  esac
  charmap=$(locale charmap 2>/dev/null || true)
  [[ $charmap == UTF-8 ]]
}

ui_has_utf8() {
  [[ ${SST_UI_ASCII:-0} -eq 1 ]] && return 1
  [[ ${TERM:-dumb} == dumb ]] && return 1
  ui_locale_utf8
}

ui_has_color() {
  [[ ${SST_NO_COLOR:-0} -eq 1 ]] && return 1
  [[ ${SST_PLAIN:-0} -eq 1 ]] && return 1
  [[ -n ${NO_COLOR:-} ]] && return 1
  [[ -t 1 ]] || return 1
  [[ ${TERM:-dumb} == dumb ]] && return 1
  return 0
}

ui_detect_width() {
  local width=${COLUMNS:-}
  if ! [[ $width =~ ^[0-9]+$ ]] || (( width < 20 )); then
    width=$(tput cols 2>/dev/null || true)
  fi
  [[ $width =~ ^[0-9]+$ ]] && (( width > 1 )) || width=80
  UI_WIDTH=$width
}

ui_set_palette() {
  if (( ! UI_COLOR_ENABLED )); then
    C_RESET='' C_BOLD='' C_DIM=''
    C_ACCENT='' C_INFO='' C_OK='' C_WARN='' C_ERROR='' C_MUTED='' C_HIGHLIGHT=''
    C_GREEN='' C_RED='' C_YELLOW='' C_CYAN='' C_BLUE='' C_MAGENTA=''
    return 0
  fi

  local colors=8
  if command -v tput >/dev/null 2>&1; then
    colors=$(tput colors 2>/dev/null || printf '8')
  fi
  [[ $colors =~ ^[0-9]+$ ]] || colors=8

  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  if (( colors >= 256 )); then
    C_ACCENT=$'\033[38;5;45m'
    C_INFO=$'\033[38;5;75m'
    C_OK=$'\033[38;5;114m'
    C_WARN=$'\033[38;5;179m'
    C_ERROR=$'\033[38;5;203m'
    C_MUTED=$'\033[38;5;244m'
    C_HIGHLIGHT=$'\033[38;5;223m'
  else
    C_ACCENT=$'\033[36m'
    C_INFO=$'\033[36m'
    C_OK=$'\033[32m'
    C_WARN=$'\033[33m'
    C_ERROR=$'\033[31m'
    C_MUTED=$'\033[2m'
    C_HIGHLIGHT=$'\033[1;36m'
  fi
  C_GREEN=$C_OK
  C_RED=$C_ERROR
  C_YELLOW=$C_WARN
  C_CYAN=$C_ACCENT
  C_BLUE=$C_INFO
  C_MAGENTA=$C_ACCENT
}

ui_set_symbols() {
  if (( UI_UNICODE )); then
    UI_SYM_BAR='│'
    UI_SYM_H='─'
    UI_BOX_TL='╭'
    UI_BOX_TR='╮'
    UI_BOX_BL='╰'
    UI_BOX_BR='╯'
    UI_BOX_V='│'
    UI_SYM_OK='✓'
    UI_SYM_WARN='!'
    UI_SYM_ERR='✗'
    UI_SYM_INFO='·'
    UI_SYM_ARROW='→'
    UI_SYM_BULLET='·'
    UI_SYM_PROMPT='›'
    UI_SYM_ELLIPSIS='…'
  else
    UI_SYM_BAR='|'
    UI_SYM_H='-'
    UI_BOX_TL='+'
    UI_BOX_TR='+'
    UI_BOX_BL='+'
    UI_BOX_BR='+'
    UI_BOX_V='|'
    UI_SYM_OK='[OK]'
    UI_SYM_WARN='[!]'
    UI_SYM_ERR='[X]'
    UI_SYM_INFO='[i]'
    UI_SYM_ARROW='->'
    UI_SYM_BULLET='-'
    UI_SYM_PROMPT='>'
    UI_SYM_ELLIPSIS='...'
  fi
}

ui_init() {
  if ui_locale_utf8; then UI_UTF8_LOCALE=1; else UI_UTF8_LOCALE=0; fi
  if ui_has_utf8; then UI_UNICODE=1; else UI_UNICODE=0; fi
  [[ ${SST_PLAIN:-0} -eq 1 ]] && UI_UNICODE=0
  ui_detect_width
  if ui_has_color; then UI_COLOR_ENABLED=1; else UI_COLOR_ENABLED=0; fi
  ui_set_palette
  ui_set_symbols
}

# ---------- 显示宽度 ----------
# 结果写入 UI_CHAR_WIDTH，避免逐字符启动子进程
ui_char_width() {
  local cp=$1
  UI_CHAR_WIDTH=1
  if (( cp <= 0 )); then
    UI_CHAR_WIDTH=0
    return 0
  fi
  if (( cp < 32 || (cp >= 0x7f && cp < 0xa0) )); then
    UI_CHAR_WIDTH=0
    return 0
  fi
  if (( cp >= 0x300 && cp <= 0x36f )) \
    || (( cp == 0x200b || cp == 0x200c || cp == 0x200d )) \
    || (( cp >= 0xfe00 && cp <= 0xfe0f )); then
    UI_CHAR_WIDTH=0
    return 0
  fi
  if (( cp >= 0x1100 && cp <= 0x115f )) \
    || (( cp >= 0x2e80 && cp <= 0x303e )) \
    || (( cp >= 0x3041 && cp <= 0x33ff )) \
    || (( cp >= 0x3400 && cp <= 0x4dbf )) \
    || (( cp >= 0x4e00 && cp <= 0x9fff )) \
    || (( cp >= 0xa000 && cp <= 0xa4cf )) \
    || (( cp >= 0xa960 && cp <= 0xa97f )) \
    || (( cp >= 0xac00 && cp <= 0xd7a3 )) \
    || (( cp >= 0xf900 && cp <= 0xfaff )) \
    || (( cp >= 0xfe10 && cp <= 0xfe19 )) \
    || (( cp >= 0xfe30 && cp <= 0xfe6f )) \
    || (( cp >= 0xff00 && cp <= 0xff60 )) \
    || (( cp >= 0xffe0 && cp <= 0xffe6 )) \
    || (( cp >= 0x1f300 && cp <= 0x1f64f )) \
    || (( cp >= 0x1f900 && cp <= 0x1f9ff )) \
    || (( cp >= 0x20000 && cp <= 0x3fffd )); then
    UI_CHAR_WIDTH=2
  fi
}

ui_text_width() {
  local text=${1:-}
  local i ch cp width=0
  if (( ! UI_UTF8_LOCALE )); then
    printf '%d' "${#text}"
    return 0
  fi
  for (( i = 0; i < ${#text}; i++ )); do
    ch=${text:i:1}
    printf -v cp '%d' "'$ch" 2>/dev/null || cp=0
    ui_char_width "$cp"
    width=$((width + UI_CHAR_WIDTH))
  done
  printf '%d' "$width"
}

ui_pad() {
  local text=${1:-} width=${2:-0}
  local current
  current=$(ui_text_width "$text")
  if (( current < width )); then
    printf '%s%*s' "$text" "$((width - current))" ''
  else
    printf '%s' "$text"
  fi
}

ui_fit() {
  local text=${1:-} max=${2:-0}
  [[ -n $text ]] || return 0
  [[ $max =~ ^[0-9]+$ ]] || { printf '%s' "$text"; return 0; }
  local total
  total=$(ui_text_width "$text")
  (( total <= max )) && { printf '%s' "$text"; return 0; }

  local ell=$UI_SYM_ELLIPSIS
  local ell_width target
  ell_width=$(ui_text_width "$ell")
  target=$((max - ell_width))
  if (( target < 1 )); then
    printf '%s' "$ell"
    return 0
  fi

  local i ch cp width=0 out=''
  for (( i = 0; i < ${#text}; i++ )); do
    ch=${text:i:1}
    if (( UI_UTF8_LOCALE )); then
      printf -v cp '%d' "'$ch" 2>/dev/null || cp=0
      ui_char_width "$cp"
    else
      UI_CHAR_WIDTH=1
    fi
    (( width + UI_CHAR_WIDTH > target )) && break
    out+=$ch
    width=$((width + UI_CHAR_WIDTH))
  done
  printf '%s%s' "$out" "$ell"
}

ui_wrap_text() {
  local text=${1:-} max=${2:-0}
  [[ -n $text ]] || { printf '\n'; return 0; }
  if ! [[ $max =~ ^[0-9]+$ ]] || (( max < 4 )); then
    printf '%s\n' "$text"
    return 0
  fi

  local i ch cp width=0 line=''
  for (( i = 0; i < ${#text}; i++ )); do
    ch=${text:i:1}
    if (( UI_UTF8_LOCALE )); then
      printf -v cp '%d' "'$ch" 2>/dev/null || cp=0
      ui_char_width "$cp"
    else
      UI_CHAR_WIDTH=1
    fi
    if (( width + UI_CHAR_WIDTH > max )); then
      printf '%s\n' "$line"
      line=''
      width=0
    fi
    line+=$ch
    width=$((width + UI_CHAR_WIDTH))
  done
  [[ -n $line ]] && printf '%s\n' "$line"
}

ui_frame_width() {
  local width=${UI_WIDTH:-80}
  (( width > UI_FRAME_MAX )) && width=$UI_FRAME_MAX
  (( width < 20 )) && width=20
  printf '%d' "$width"
}

# ---------- 基础输出 ----------
ui_status() {
  local type=$1
  shift
  local color prefix
  case $type in
    ok)
      color=$C_OK
      if (( UI_UNICODE )); then prefix="$UI_SYM_OK 完成"; else prefix='[完成]'; fi
      ;;
    warn)
      color=$C_WARN
      if (( UI_UNICODE )); then prefix="$UI_SYM_WARN 注意"; else prefix='[注意]'; fi
      ;;
    err)
      color=$C_ERROR
      if (( UI_UNICODE )); then prefix="$UI_SYM_ERR 错误"; else prefix='[错误]'; fi
      ;;
    *)
      color=$C_INFO
      if (( UI_UNICODE )); then prefix="$UI_SYM_INFO 信息"; else prefix='[信息]'; fi
      ;;
  esac
  printf '%s%s%s %s\n' "$color" "$prefix" "$C_RESET" "$*"
}

ui_section() {
  local title=${1:-} meta=${2:-}
  local used avail max meta_width spaces
  printf '\n%s%s%s %s%s%s' "$C_ACCENT" "$UI_SYM_BAR" "$C_RESET" "$C_BOLD" "$title" "$C_RESET"
  if [[ -n $meta ]]; then
    used=$((2 + $(ui_text_width "$title")))
    avail=$((UI_WIDTH - 1))
    meta_width=$(ui_text_width "$meta")
    max=$((avail - used - 2))
    if (( max >= 4 && meta_width > max )); then
      meta=$(ui_fit "$meta" "$max")
      meta_width=$(ui_text_width "$meta")
    fi
    if (( max >= 4 )); then
      spaces=$((avail - used - meta_width))
      (( spaces > 0 )) && printf '%*s%s%s%s' "$spaces" '' "$C_DIM" "$meta" "$C_RESET"
    fi
  fi
  printf '\n'
}

ui_rule() {
  local width i
  width=$(ui_frame_width)
  printf '%s' "$C_DIM"
  for (( i = 0; i < width; i++ )); do
    printf '%s' "$UI_SYM_H"
  done
  printf '%s\n' "$C_RESET"
}

ui_kv() {
  local label=${1:-} value=${2:-} padded
  padded=$(ui_pad "$label" 22)
  printf '  %s%s%s  %s\n' "$C_DIM" "$padded" "$C_RESET" "$value"
}

ui_group() {
  printf '\n  %s%s %s%s\n' "$C_DIM" "$UI_SYM_BULLET" "$1" "$C_RESET"
}

ui_menu_item() {
  local num=$1 title=$2 desc=${3:-}
  local title_max title_shown title_width avail shown
  title_max=$((UI_WIDTH - 6))
  (( title_max < 6 )) && title_max=6
  title_shown=$(ui_fit "$title" "$title_max")
  title_width=$(ui_text_width "$title_shown")
  printf '  %s%2d%s  %s%s%s' "$C_ACCENT" "$num" "$C_RESET" "$C_BOLD" "$title_shown" "$C_RESET"
  if [[ -n $desc ]]; then
    avail=$((UI_WIDTH - 11 - title_width))
    if (( avail > 5 )); then
      shown=$(ui_fit "$desc" "$avail")
      printf '  %s%s %s%s\n' "$C_DIM" "$UI_SYM_BULLET" "$shown" "$C_RESET"
    else
      printf '\n'
    fi
  else
    printf '\n'
  fi
}

ui_menu_footer() {
  local label=${1:-返回}
  printf '\n  %s0%s  %s\n\n' "$C_ACCENT" "$C_RESET" "$label"
}

ui_menu_list() {
  local list=$1 zero=${2:-返回} i=0 line
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    i=$((i + 1))
    ui_menu_item "$i" "$line"
  done <<<"$list"
  ui_menu_footer "$zero"
}

ui_menu_option() {
  local key=$1 label=$2
  printf '  %s%2s%s  %s\n' "$C_ACCENT" "$key" "$C_RESET" "$label"
}

ui_prompt_text() {
  local text=${1:-请选择}
  printf '%s%s%s %s%s%s ' "$C_ACCENT" "$text" "$C_RESET" "$C_ACCENT" "$UI_SYM_PROMPT" "$C_RESET"
}

ui_read_choice() {
  local prompt=${1:-请选择}
  UI_CHOICE=''
  read -r -p "$(ui_prompt_text "$prompt")" UI_CHOICE || return 1
  return 0
}

ui_panel_color() {
  local color=$1 title=$2 line width inner top fill content i
  width=$(ui_frame_width)
  inner=$((width - 4))
  (( inner < 8 )) && inner=8
  title=$(ui_fit "$title" $((width - 6)))

  fill=$((width - 5 - $(ui_text_width "$title")))
  (( fill < 0 )) && fill=0
  top="${UI_BOX_TL}${UI_SYM_H} ${C_BOLD}${title}${C_RESET}${color} "
  for (( i = 0; i < fill; i++ )); do top+="$UI_SYM_H"; done
  top+="$UI_BOX_TR"
  printf '%s%s%s\n' "$color" "$top" "$C_RESET"

  shift 2
  for line in "$@"; do
    while IFS= read -r content; do
      content=$(ui_pad "$content" "$inner")
      printf '%s%s%s %s %s%s%s\n' "$color" "$UI_BOX_V" "$C_RESET" "$content" "$color" "$UI_BOX_V" "$C_RESET"
    done < <(ui_wrap_text "$line" "$inner")
  done

  printf '%s' "$color"
  printf '%s' "$UI_BOX_BL"
  for (( i = 0; i < width - 2; i++ )); do printf '%s' "$UI_SYM_H"; done
  printf '%s%s\n' "$UI_BOX_BR" "$C_RESET"
}

ui_panel() { ui_panel_color "$C_ACCENT" "$@"; }

ui_danger_panel() { ui_panel_color "$C_ERROR" "$@"; }

ui_confirm_danger() {
  local message=$1 impact=${2:-} rollback=${3:-}
  [[ ${SST_YES:-0} -eq 1 ]] && return 0
  local -a lines=("$message")
  [[ -n $impact ]] && lines+=("影响：$impact")
  [[ -n $rollback ]] && lines+=("回滚：$rollback")
  ui_danger_panel "危险操作" "${lines[@]}"
  confirm "确认继续？"
}

ui_init
