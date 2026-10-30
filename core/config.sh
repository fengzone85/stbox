#!/usr/bin/env bash
# 配置层：键值配置的读取与写入（config/settings.conf）

cfg_file() { printf '%s/settings.conf' "$SST_CONFIG_DIR"; }

cfg_get() {
  local key=$1 default=${2:-} value='' f
  f=$(cfg_file)
  if [[ -r $f ]]; then
    value=$(grep -E "^${key}=" "$f" 2>/dev/null | tail -n 1 | cut -d= -f2-)
  fi
  printf '%s\n' "${value:-$default}"
}

cfg_set() {
  local key=$1 value=$2 f tmp
  [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "非法配置键：$key"
  f=$(cfg_file)
  mkdir -p "$SST_CONFIG_DIR" 2>/dev/null || die "无法创建配置目录：$SST_CONFIG_DIR"
  tmp=$(mktemp) || die "无法创建临时文件"
  if [[ -r $f ]]; then
    grep -vE "^${key}=" "$f" >"$tmp" 2>/dev/null || true
  fi
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv "$tmp" "$f"
  chmod 600 "$f" 2>/dev/null || true
}

cfg_show() {
  local f
  f=$(cfg_file)
  section "配置信息"
  kv "配置文件" "$f"
  kv "数据目录" "$SST_DATA_DIR"
  kv "日志文件" "$SST_LOG"
  if [[ -r $f ]]; then
    hr
    cat "$f"
  else
    warn "暂无配置，运行相关功能后会自动生成"
  fi
}
