#!/usr/bin/env bash
# STBOX 单文件安装器：curl -fsSL .../i.sh | sudo bash
set -euo pipefail

BASE=${STBOX_BASE_URL:-https://raw.githubusercontent.com/fengzone85/stbox/main}
MIRROR=${STBOX_MIRROR_URL:-https://cdn.jsdelivr.net/gh/fengzone85/stbox@main}
BIN_DIR=${STBOX_BIN_DIR:-/usr/local/bin}

die() { printf '[错误] %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-1} -eq 0 ]] || die "请使用 sudo 执行：curl -fsSL .../i.sh | sudo bash"
command -v curl >/dev/null 2>&1 || die "需要 curl"
command -v sha256sum >/dev/null 2>&1 || die "需要 sha256sum"

TMP=$(mktemp) || die "无法创建临时文件"
SHA=$(mktemp) || die "无法创建临时文件"
trap 'rm -f "$TMP" "$SHA"' EXIT

fetch() {
  local url=$1 out=$2
  curl -fsSL --connect-timeout 6 --max-time 60 "$url" -o "$out" 2>/dev/null
}

fetch "$BASE/stbox.sh" "$TMP" || fetch "$MIRROR/stbox.sh" "$TMP" || die "下载 stbox.sh 失败"
fetch "$BASE/stbox.sh.sha256" "$SHA" || fetch "$MIRROR/stbox.sh.sha256" "$SHA" || die "下载校验文件失败"

expected=$(awk 'NR==1 {print $1}' "$SHA")
actual=$(sha256sum "$TMP" | awk '{print $1}')
[[ -n $expected && $expected == "$actual" ]] || die "SHA256 校验失败"

[[ $(head -1 "$TMP") == '#!/usr/bin/env bash' ]] || die "下载文件格式无效"
bash -n "$TMP" || die "下载文件语法校验失败"

mkdir -p "$BIN_DIR" || die "无法创建目录：$BIN_DIR"
if [[ -e $BIN_DIR/st ]]; then
  cp -f "$BIN_DIR/st" "$BIN_DIR/st.bak" 2>/dev/null || true
fi
if command -v install >/dev/null 2>&1; then
  install -m 755 "$TMP" "$BIN_DIR/st" || die "安装失败"
else
  cp -f "$TMP" "$BIN_DIR/st" && chmod 755 "$BIN_DIR/st" || die "安装失败"
fi

ver=$(grep -m1 '^SST_VERSION=' "$TMP" | cut -d'"' -f2)
printf '✓ STBOX 单文件已安装：%s/st\n' "$BIN_DIR"
printf '  版本：%s\n' "${ver:-未知}"
printf '  数据目录：%s\n' "${STBOX_STATE_DIR:-/var/lib/stbox}"
printf '  执行 st 进入交互菜单，或 st help 查看命令。\n'
