#!/usr/bin/env bash
# SSH 变更自动回滚：由 systemd 定时器调用
set -o pipefail

STATE=${1:-}
[[ -r $STATE ]] || exit 1

state_get() {
  grep -E "^${1}=" "$STATE" 2>/dev/null | tail -n 1 | cut -d= -f2-
}
state_set() {
  local tmp
  tmp=$(mktemp)
  grep -vE "^${1}=" "$STATE" >"$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$1" "$2" >>"$tmp"
  mv "$tmp" "$STATE"
  chmod 600 "$STATE" 2>/dev/null || true
}

log_file=$(state_get ROLLBACK_LOG)
[[ -n $log_file ]] || log_file=/var/log/stbox-ssh-rollback.log
mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

if [[ $(state_get SSH_KEEP) == 1 ]]; then
  printf '%s SSH rollback skipped: configuration kept\n' "$(date '+%F %T')" >>"$log_file"
  exit 0
fi

backup=$(state_get SSH_BACKUP)
service=$(state_get SSH_SERVICE)
[[ -f $backup ]] || {
  printf '%s SSH rollback failed: backup missing (%s)\n' "$(date '+%F %T')" "$backup" >>"$log_file"
  state_set SSH_ROLLBACK failed
  exit 1
}

if ! rm -f /etc/ssh/sshd_config.d/00-stbox-port.conf /etc/ssh/sshd_config.d/00-stbox-auth.conf 2>/dev/null; then
  printf '%s SSH rollback failed: remove wizard drop-ins failed\n' "$(date '+%F %T')" >>"$log_file"
  state_set SSH_ROLLBACK failed
  exit 1
fi

if ! tar -xzf "$backup" -C / 2>>"$log_file"; then
  printf '%s SSH rollback failed: restore failed\n' "$(date '+%F %T')" >>"$log_file"
  state_set SSH_ROLLBACK failed
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$service" >>"$log_file" 2>&1
else
  service "$service" restart >>"$log_file" 2>&1
fi
rc=$?
if (( rc != 0 )); then
  printf '%s SSH rollback failed: restart %s rc=%s\n' "$(date '+%F %T')" "$service" "$rc" >>"$log_file"
  state_set SSH_ROLLBACK failed
  exit 1
fi

printf '%s SSH rollback completed, service=%s backup=%s\n' "$(date '+%F %T')" "$service" "$backup" >>"$log_file"
state_set SSH_ROLLBACK done
state_set SSH_STATUS rolledback
exit 0
