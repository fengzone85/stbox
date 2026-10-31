#!/usr/bin/env bash
# 模块：备份与迁移

sst_register_module backup "备份迁移" "站点 数据库 定时 远程"
SST_MODULE_ITEMS[backup]=$'list|备份列表\ncreate|创建备份\nrestore|恢复备份\nschedule|定时备份\nremote|远程传输'

backup_dir_get() { cfg_get BACKUP_DIR "$SST_DATA_DIR/backups"; }
backup_targets_get() { cfg_get BACKUP_TARGETS "/etc /var/www"; }

backup_list() {
  local dir f
  dir=$(backup_dir_get)
  section "备份列表"
  if ! compgen -G "$dir/full-*.tar.gz" >/dev/null 2>&1; then
    info "暂无备份，可执行：st backup create"
    return 0
  fi
  printf '  %-32s %10s  %s\n' "文件" "大小" "创建时间"
  hr
  while IFS= read -r f; do
    printf '  %-32s %10s  %s\n' \
      "$(basename "$f")" "$(du -h "$f" | cut -f1)" "$(date -r "$f" '+%Y-%m-%d %H:%M')"
  done < <(ls -1t "$dir"/full-*.tar.gz 2>/dev/null)
  printf '\n  目录：%s\n' "$dir"
}

backup_create() {
  require_root
  local -a raw=() targets=() rels=()
  if [[ $# -gt 0 ]]; then
    raw=("$@")
  elif [[ -t 0 ]]; then
    local input
    input=$(ask "需要备份的路径（空格分隔）" "$(backup_targets_get)")
    read -r -a raw <<<"$input"
    cfg_set BACKUP_TARGETS "${raw[*]}"
  else
    read -r -a raw <<<"$(backup_targets_get)"
  fi

  local t
  for t in "${raw[@]}"; do
    if [[ ! -e $t ]]; then
      warn "跳过不存在的路径：$t"
      continue
    fi
    targets+=("$t")
    rels+=("${t#/}")
  done
  [[ ${#targets[@]} -gt 0 ]] || die "没有可备份的路径"

  confirm "将备份以下路径：${targets[*]}" || return 0

  local dir ts file tmpd
  dir=$(backup_dir_get)
  mkdir -p "$dir" || die "无法创建备份目录：$dir"
  ts=$(date +%Y%m%d-%H%M%S)
  file="$dir/full-$ts.tar.gz"
  tmpd=$(mktemp -d)
  local -a extra=()

  # 数据库导出仅在交互模式下询问，避免 cron 任务误触发
  if [[ -t 0 ]] && { have mysqldump || have mariadb-dump; }; then
    if confirm "同时导出 MySQL/MariaDB 数据库？"; then
      local dumpcmd client pass dbs db
      dumpcmd=mysqldump
      have mariadb-dump && dumpcmd=mariadb-dump
      client=mysql
      have mysql || client=mariadb
      pass=$(ask "MySQL root 密码（留空表示免密 socket）" "")
      mkdir -p "$tmpd/databases"
      dbs=$(MYSQL_PWD="$pass" "$client" -uroot -N -e 'show databases' 2>/dev/null) || true
      for db in $dbs; do
        case $db in
          information_schema|performance_schema|mysql|sys) continue ;;
        esac
        info "导出数据库：$db"
        MYSQL_PWD="$pass" "$dumpcmd" -uroot --single-transaction --quick \
          "$db" >"$tmpd/databases/$db.sql" 2>/dev/null || warn "数据库 $db 导出失败"
      done
      extra=(-C "$tmpd" databases)
    fi
  fi

  info "创建归档：$file"
  if ! tar --ignore-failed-read -czf "$file" -C / "${rels[@]}" "${extra[@]}"; then
    rm -rf "$tmpd"
    rm -f "$file"
    die "备份失败"
  fi
  rm -rf "$tmpd"

  {
    printf 'host=%s\n' "$(hostname)"
    printf 'time=%s\n' "$(date '+%F %T')"
    printf 'paths=%s\n' "${targets[*]}"
  } >"$file.manifest"

  ok "备份完成：$file（$(du -h "$file" | cut -f1)）"
  backup_prune
}

backup_prune() {
  local days dir
  days=$(cfg_get BACKUP_RETENTION 0)
  [[ $days =~ ^[0-9]+$ ]] || days=0
  (( days > 0 )) || return 0
  dir=$(backup_dir_get)
  info "清理 ${days} 天前的备份…"
  find "$dir" -maxdepth 1 -name 'full-*.tar.gz*' -mtime +"$days" -print -delete 2>/dev/null || true
}

backup_restore() {
  require_root
  local dir file target=${2:-/}
  dir=$(backup_dir_get)

  if [[ -n ${1:-} ]]; then
    file=${1}
    [[ -f $file ]] || file="$dir/${1}"
  else
    [[ -t 0 ]] || die "非交互环境请指定备份文件：st backup restore <文件> [目标]"
    local -a files=()
    mapfile -t files < <(ls -1t "$dir"/full-*.tar.gz 2>/dev/null)
    [[ ${#files[@]} -gt 0 ]] || die "没有可用备份"
    local i choice
    section "选择备份"
    for i in "${!files[@]}"; do
      ui_menu_item "$((i + 1))" "$(basename "${files[$i]}")"
    done
    ui_menu_footer "取消"
    ui_read_choice "选择编号" || return 1
    choice=$UI_CHOICE
    [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )) || {
      [[ $choice == 0 || $choice == q || $choice == back ]] && return 0
      die "无效编号"
    }
    file=${files[$((choice - 1))]}
  fi
  [[ -f $file ]] || die "备份文件不存在：$file"

  section "备份信息"
  [[ -f $file.manifest ]] && cat "$file.manifest"
  kv "归档文件" "$file"
  kv "恢复目标" "$target"
  warn "恢复会覆盖目标目录中的同名文件，请确认已了解影响范围"

  if [[ ${SST_YES:-0} -ne 1 ]]; then
    local phrase
    read -r -p "输入 RESTORE 确认恢复: " phrase || return 1
    [[ $phrase == RESTORE ]] || { warn "已取消"; return 0; }
  fi

  if [[ ! -d $target ]]; then
    mkdir -p "$target" || die "无法创建恢复目标目录：$target"
  fi

  info "开始解压…"
  tar -xzf "$file" -C "$target" --numeric-owner || die "恢复失败"
  ok "恢复完成，请检查服务配置并重启相关服务"
}

backup_schedule() {
  require_root
  local cronfile=/etc/cron.d/sst-backup
  section "定时备份"
  if [[ ${1:-} == remove ]]; then
    rm -f "$cronfile"
    ok "已删除定时备份任务"
    return 0
  fi
  if [[ -f $cronfile ]]; then
    cat "$cronfile"
  else
    info "当前未配置定时备份"
  fi

  confirm "设置/修改每日定时备份？（选择 n 将删除现有任务）" || {
    rm -f "$cronfile"
    ok "已删除定时备份任务"
    return 0
  }

  local time h m retention
  time=$(ask "每天执行时间（HH:MM）" "03:30")
  [[ $time =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || die "时间格式错误：$time"
  h=$((10#${time%%:*}))
  m=$((10#${time#*:}))
  retention=$(ask "保留天数（0 表示不自动清理）" "$(cfg_get BACKUP_RETENTION 7)")
  [[ $retention =~ ^[0-9]+$ ]] || die "保留天数必须是数字"

  cfg_set BACKUP_RETENTION "$retention"
  cfg_set BACKUP_TARGETS "$(backup_targets_get)"

  cat >"$cronfile" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$m $h * * * root "$SST_ENTRY" --yes backup create >> "$SST_LOG" 2>&1
EOF
  chmod 644 "$cronfile"
  ok "已设置每天 $time 执行备份，保留 ${retention} 天"
  info "备份路径来自配置 BACKUP_TARGETS=$(backup_targets_get)"
}

backup_remote() {
  local all=0 dir file host remote_dir
  [[ ${1:-} == all ]] && all=1
  dir=$(backup_dir_get)
  host=$(ask "远程主机（user@host）" "")
  [[ -n $host ]] || return 0
  remote_dir=$(ask "远程目录" "/root/backups")

  if ! have rsync; then
    confirm "安装 rsync 用于远程传输？" || return 0
    pkg_install rsync || die "rsync 安装失败"
  fi

  if (( all == 1 )); then
    info "传输全部备份到 $host:$remote_dir …"
    rsync -avz --progress "$dir"/ "$host:$remote_dir"/
  else
    mapfile -t files < <(ls -1t "$dir"/full-*.tar.gz 2>/dev/null)
    [[ ${#files[@]} -gt 0 ]] || die "没有可用备份"
    file=${files[0]}
    info "传输 $(basename "$file") 到 $host:$remote_dir …"
    rsync -avz --progress "$file" "$file.manifest" "$host:$remote_dir"/ 2>/dev/null \
      || rsync -avz --progress "$file" "$host:$remote_dir"/
  fi
  ok "远程传输完成"
}
