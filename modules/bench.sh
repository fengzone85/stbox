#!/usr/bin/env bash
# 模块：性能与综合测试
# 原生实现内存/磁盘/CPU 测试，第三方测试脚本统一走脚本市场。

sst_register_module bench "性能测试" "内存 磁盘 CPU 与综合测试"
SST_MODULE_ITEMS[bench]=$'memtest|内存压力测试\ndiskbench|磁盘读写测试\ncpu|CPU 基准测试\nscripts|第三方测试脚本\nsuperbench|Superbench 综合测试\nlemonbench|Lemonbench 综合测试\nunixbench|UNIXbench 综合测试\nyabs|YABS 综合测试\nsuperspeed|三网测速\nspeedtest|Ookla SpeedTest\nmedia|流媒体解锁检测\nmt|MT 流媒体检测\ntubecheck|YouTube CDN 检测\nbesttrace|Besttrace 路由追踪\ndisktest|Disk Test 综合测试\nroutetrace|三网回程路由'

bench_memtest() {
  require_root
  local size iters
  size=$(ask "测试内存大小（如 512M、1G）" "512M")
  [[ $size =~ ^[0-9]+[GgMm]$ ]] || die "大小格式错误，示例：512M / 1G"
  iters=$(ask "循环次数" "2")
  [[ $iters =~ ^[0-9]+$ ]] && (( iters >= 1 )) || die "循环次数必须是正整数"

  confirm "memtester 将占用 $size 内存并运行 $iters 轮，可能影响线上服务，继续？" || return 0
  info "memtester 未安装时会先通过包管理器安装…"
  ensure_tool memtester memtester || return 1
  memtester "$size" "$iters"
}

bench_diskbench() {
  local size=${1:-100} file out
  [[ $size =~ ^[0-9]+$ ]] && (( size >= 10 && size <= 2048 )) \
    || die "测试大小需在 10-2048 MB 之间"
  file="/tmp/sst-disk-test-$$"

  confirm "将在 $file 写入 ${size}MB 测试数据（会自动删除），继续？" || return 0

  info "顺序写入测试…"
  if ! out=$(LC_ALL=C dd if=/dev/zero of="$file" bs=1M count="$size" oflag=direct conv=fdatasync 2>&1); then
    warn "direct IO 不可用，改用普通写入（结果可能受缓存影响）"
    if ! out=$(LC_ALL=C dd if=/dev/zero of="$file" bs=1M count="$size" conv=fdatasync 2>&1); then
      rm -f "$file"
      die "写入测试失败，请检查 /tmp 空间"
    fi
  fi
  kv "写入" "$(printf '%s\n' "$out" | tail -n 1)"

  sync
  if [[ ${EUID:-1} -eq 0 ]]; then
    echo 3 >/proc/sys/vm/drop_caches 2>/dev/null || true
  fi

  info "顺序读取测试…"
  if ! out=$(LC_ALL=C dd if="$file" of=/dev/null bs=1M iflag=direct 2>&1); then
    warn "direct 读取不可用，结果可能受缓存影响"
    out=$(LC_ALL=C dd if="$file" of=/dev/null bs=1M 2>&1) || true
  fi
  kv "读取" "$(printf '%s\n' "$out" | tail -n 1)"

  rm -f "$file"
  ok "磁盘测试完成，测试文件已清理"
}

bench_cpu() {
  require_root
  local cores
  cores=$(nproc 2>/dev/null || echo 1)
  confirm "使用 sysbench 对 ${cores} 线程进行 CPU 整数运算测试？" || return 0
  info "sysbench 未安装时会先通过包管理器安装…"
  ensure_tool sysbench sysbench || return 1
  section "CPU 基准测试（cpu-max-prime=20000）"
  sysbench cpu --cpu-max-prime=20000 --threads="$cores" run
}

bench_scripts() { scripts_menu 测试; }
