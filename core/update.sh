#!/usr/bin/env bash
# 版本与自更新

SST_VERSION=$(cat "$SST_HOME/VERSION" 2>/dev/null || echo "unknown")

version_info() {
  section "STBOX 版本信息"
  kv "版本" "$SST_VERSION"
  kv "安装目录" "$SST_HOME"
  kv "入口命令" "$SST_ENTRY"
  kv "配置目录" "$SST_CONFIG_DIR"
  kv "数据目录" "$SST_DATA_DIR"
  kv "日志文件" "$SST_LOG"
  kv "运行系统" "$OS_NAME ($ARCH)"
  kv "包管理器" "$PKG"
  kv "服务管理器" "$INIT"
}

update_self() {
  require_root
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
