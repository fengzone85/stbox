#!/usr/bin/env bash
# STBOX（SSH Tool Box）入口：解析全局参数，加载框架后按模块分发
set -o pipefail

# 解析软链接，确保通过 /usr/local/bin/st 启动时仍能找到真实安装目录
SST_SOURCE=${BASH_SOURCE[0]}
while [[ -L $SST_SOURCE ]]; do
  SST_LINK_DIR=$(cd -- "$(dirname -- "$SST_SOURCE")" && pwd -P)
  SST_SOURCE=$(readlink "$SST_SOURCE")
  [[ $SST_SOURCE == /* ]] || SST_SOURCE="$SST_LINK_DIR/$SST_SOURCE"
done
SST_HOME=$(cd -- "$(dirname -- "$SST_SOURCE")" && pwd -P)
SST_ENTRY="$SST_HOME/st.sh"
export SST_HOME SST_ENTRY
export SST_YES=${SST_YES:-0}
export SST_NO_COLOR=${SST_NO_COLOR:-0}

# 先消费全局开关，再加载核心（颜色等依赖这些变量）
args=()
for arg in "$@"; do
  case $arg in
    --yes|-y) SST_YES=1 ;;
    --no-color) SST_NO_COLOR=1 ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]}"

# shellcheck source=core/common.sh
source "$SST_HOME/core/common.sh"
# shellcheck source=core/config.sh
source "$SST_HOME/core/config.sh"
# shellcheck source=core/apps.sh
source "$SST_HOME/core/apps.sh"
# shellcheck source=core/scripts.sh
source "$SST_HOME/core/scripts.sh"
# shellcheck source=core/update.sh
source "$SST_HOME/core/update.sh"
# shellcheck source=core/menu.sh
source "$SST_HOME/core/menu.sh"

sst_init_dirs
sst_detect_os
sst_load_scripts
sst_load_modules
sst_load_apps

sst_dispatch "$@"
