#!/usr/bin/env bash
# STBOX（SSH Tool Box）安装脚本：部署到 /opt/ssh-tools，并注册 st 命令
set -euo pipefail

SRC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
DEST=${SST_INSTALL_DIR:-/opt/ssh-tools}
BIN_DIR=${SST_BIN_DIR:-/usr/local/bin}

if [[ ${EUID:-1} -ne 0 ]]; then
  echo "请使用 root 执行：sudo bash $SRC/install.sh" >&2
  exit 1
fi

echo "[1/4] 部署目录：$DEST"
mkdir -p "$DEST"
if [[ $SRC != "$DEST" ]]; then
  cp -a "$SRC"/. "$DEST"/
fi
chmod +x "$DEST/st.sh"

echo "[2/4] 初始化数据目录"
mkdir -p "$DEST/config" "$DEST/data/backups" "$DEST/data/apps" "$DEST/logs"
chown -R root:root "$DEST" 2>/dev/null || true
chmod 700 "$DEST/data" "$DEST/config" "$DEST/logs" 2>/dev/null || true

echo "[3/4] 注册命令：$BIN_DIR/st"
mkdir -p "$BIN_DIR"
ln -sfn "$DEST/st.sh" "$BIN_DIR/st"

echo "[4/4] 检查入口"
"$BIN_DIR/st" --no-color version >/dev/null || {
  echo "入口自检失败，请检查 $DEST 是否完整" >&2
  exit 1
}
echo "安装完成。执行 st 进入交互菜单，或 st help 查看命令。"
