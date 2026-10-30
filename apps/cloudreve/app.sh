#!/usr/bin/env bash
# Cloudreve：私有云盘

app_cloudreve_install() {
  docker_require || return 1
  mkdir -p "$(app_data_dir cloudreve)/data"
  app_compose_up cloudreve <<'YAML' || return 1
services:
  cloudreve:
    image: cloudreve/cloudreve:latest
    container_name: sst-cloudreve
    restart: unless-stopped
    ports:
      - "5212:5212"
    volumes:
      - ./data:/cloudreve
YAML
  ok "Cloudreve 已启动：http://$(get_public_ip):5212"
  info "首次访问按页面引导完成初始化"
}

app_cloudreve_remove() {
  app_compose_down cloudreve || return 1
  info "容器已移除，data 目录仍保留"
}
