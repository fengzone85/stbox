#!/usr/bin/env bash
# Uptime Kuma：站点可用性监控

app_uptime_kuma_install() {
  docker_require || return 1
  app_compose_up uptime-kuma <<'YAML' || return 1
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - uptime_kuma_data:/app/data
volumes:
  uptime_kuma_data:
YAML
  ok "Uptime Kuma 已启动：http://$(get_public_ip):3001"
  info "首次访问需创建管理员账号"
}

app_uptime_kuma_remove() {
  app_compose_down uptime-kuma || return 1
  info "容器已移除，数据卷 uptime_kuma_data 仍保留在 Docker 中"
}
