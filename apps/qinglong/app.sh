#!/usr/bin/env bash
# 青龙面板：定时任务管理

app_qinglong_install() {
  docker_require || return 1
  app_compose_up qinglong <<'YAML' || return 1
services:
  qinglong:
    image: whyour/qinglong:latest
    container_name: sst-qinglong
    restart: unless-stopped
    ports:
      - "5700:5700"
    volumes:
      - ./data:/ql/data
    environment:
      ENABLE_HANGUP: "true"
YAML
  ok "青龙面板已启动：http://$(get_public_ip):5700"
  info "首次访问按页面提示初始化"
}

app_qinglong_remove() {
  app_compose_down qinglong || return 1
  info "容器已移除，data 目录仍保留"
}
