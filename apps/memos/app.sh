#!/usr/bin/env bash
# Memos：网页备忘录

app_memos_install() {
  docker_require || return 1
  app_compose_up memos <<'YAML' || return 1
services:
  memos:
    image: neosmemo/memos:stable
    container_name: sst-memos
    restart: unless-stopped
    ports:
      - "5230:5230"
    volumes:
      - ./data:/var/opt/memos
YAML
  ok "Memos 已启动：http://$(get_public_ip):5230"
  info "首次访问注册管理员账号"
}

app_memos_remove() {
  app_compose_down memos || return 1
  info "容器已移除，data 目录仍保留"
}
