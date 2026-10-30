#!/usr/bin/env bash
# 模块：脚本设置与维护

sst_register_module settings "脚本设置" "版本 更新 配置 日志"
SST_MODULE_ITEMS[settings]=$'version|版本信息\nupdate|更新脚本\nconfig|查看配置\nlog|查看日志'

settings_version() { version_info; }

settings_update() { update_self; }

settings_config() { cfg_show; }

settings_log() {
  section "运行日志（最近 60 行）"
  if [[ -r $SST_LOG ]]; then
    tail -n 60 "$SST_LOG"
  else
    info "暂无日志：$SST_LOG"
  fi
}
