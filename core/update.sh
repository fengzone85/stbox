#!/usr/bin/env bash
# 版本与自更新

if [[ -z ${SST_VERSION:-} ]]; then
  SST_VERSION=$(cat "$SST_HOME/VERSION" 2>/dev/null || echo "unknown")
fi

version_info() {
  section "STBOX 版本信息"
  kv "版本" "$SST_VERSION"
  if [[ ${SST_BUNDLED:-0} -eq 1 ]]; then
    kv "运行方式" "单文件"
    kv "程序路径" "$SST_ENTRY"
    kv "状态目录" "$SST_STATE_DIR"
  else
    kv "安装目录" "$SST_HOME"
  fi
  kv "入口命令" "$SST_ENTRY"
  kv "配置目录" "$SST_CONFIG_DIR"
  kv "数据目录" "$SST_DATA_DIR"
  kv "日志文件" "$SST_LOG"
  kv "运行系统" "$OS_NAME ($ARCH)"
  kv "包管理器" "$PKG"
  kv "服务管理器" "$INIT"
}

# 安装/覆盖文件：优先 install，最小系统回退 cp
sst_install_file() {
  local src=$1 dest=$2
  if have install; then
    install -m 755 "$src" "$dest"
  else
    cp -f "$src" "$dest" && chmod 755 "$dest"
  fi
}

# 单文件版本自安装：sudo bash <(curl ...) install
stbox_self_install() {
  [[ ${SST_BUNDLED:-0} -eq 1 ]] || die "仅单文件版本支持 install"
  [[ ${EUID:-1} -eq 0 ]] || die "请使用 root 执行：sudo bash <(curl ...) install"
  local src=${BASH_SOURCE[0]:-} bin=${STBOX_BIN_DIR:-/usr/local/bin}
  [[ -r $src ]] || die "无法读取当前单文件：$src"
  mkdir -p "$bin" || die "无法创建目录：$bin"
  if [[ -e $bin/st ]]; then
    confirm "覆盖已有 $bin/st？" || return 0
  fi
  sst_install_file "$src" "$bin/st" || die "安装失败：$bin/st"
  ok "已安装：$bin/st"
  info "数据目录：$SST_STATE_DIR"
  info "执行 st 进入交互菜单"
}

update_self() {
  require_root
  if [[ ${SST_BUNDLED:-0} -eq 1 ]]; then
    local url=${STBOX_UPDATE_URL:-https://raw.githubusercontent.com/fengzone85/stbox/main/stbox.sh}
    local sha_url=${STBOX_UPDATE_SHA_URL:-$url.sha256}
    local dest=${SST_ENTRY:-}
    [[ -f $dest && $dest != /dev/fd/* && $dest != /proc/* ]] || die "请先执行 sudo bash <(curl ...) install 安装单文件版本"
    confirm "下载并更新单文件版本？" || return 0
    local tmp sha expected actual new_ver
    tmp=$(mktemp) sha=$(mktemp) || die "无法创建临时文件"
    if ! download_with_fallback "$url" "$tmp" 60; then
      rm -f "$tmp" "$sha"
      die "下载新版本失败：$url"
    fi
    if ! download_with_fallback "$sha_url" "$sha" 30; then
      rm -f "$tmp" "$sha"
      die "下载校验文件失败：$sha_url"
    fi
    expected=$(awk 'NR==1 {print $1}' "$sha")
    actual=$(sha256sum "$tmp" | awk '{print $1}')
    if [[ -z $expected || $expected != "$actual" ]]; then
      rm -f "$tmp" "$sha"
      die "SHA256 校验失败，已取消更新"
    fi
    bash -n "$tmp" || { rm -f "$tmp" "$sha"; die "新版本语法校验失败"; }
    new_ver=$(grep -m1 '^SST_VERSION=' "$tmp" | cut -d'"' -f2)
    cp -f "$dest" "$dest.bak" || { rm -f "$tmp" "$sha"; die "备份旧版本失败"; }
    if ! sst_install_file "$tmp" "$dest"; then
      cp -f "$dest.bak" "$dest" 2>/dev/null || true
      rm -f "$tmp" "$sha"
      die "替换失败，已恢复旧版本"
    fi
    rm -f "$tmp" "$sha"
    ok "更新完成${new_ver:+：$new_ver}"
    info "旧版本备份：$dest.bak"
    return 0
  fi

  if [[ -d "$SST_HOME/.git" ]] && have git; then
    info "当前为 Git 源码部署，准备拉取最新代码…"
    confirm "执行 git pull --ff-only 更新？" || return 0
    git -C "$SST_HOME" pull --ff-only || die "更新失败，请检查远程仓库或本地修改"
    ok "更新完成，重新进入脚本后生效"
  else
    warn "当前部署不是 Git 仓库，无法自动更新。"
    warn "请重新拉取/覆盖源码，或执行 install.sh 覆盖安装（配置与数据会保留）。"
  fi
}
