#!/usr/bin/env bash
# AList：多存储文件列表程序

app_alist_install() {
  docker_require || return 1
  app_compose_up alist <<'YAML' || return 1
services:
  alist:
    image: xhofe/alist:latest
    container_name: sst-alist
    restart: unless-stopped
    ports:
      - "5244:5244"
    volumes:
      - ./data:/opt/alist/data
    environment:
      PUID: 0
      PGID: 0
      UMASK: 022
YAML
  ok "AList 已启动：http://$(get_public_ip):5244"
  info "查看初始密码：docker exec -it sst-alist ./alist admin random"
}

app_alist_remove() {
  app_compose_down alist || return 1
  info "容器已移除，data 目录仍保留"
}
