#!/usr/bin/env bash
# VS Code Docker：OpenVSCode Server，浏览器访问的 VS Code

app_vscode_install() {
  docker_require || return 1
  local token
  token=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
  app_compose_up vscode <<YAML || return 1
services:
  vscode:
    image: lscr.io/linuxserver/openvscode-server:latest
    container_name: sst-vscode
    restart: unless-stopped
    environment:
      PUID: 1000
      PGID: 1000
      TZ: Asia/Shanghai
      CONNECTION_TOKEN: $token
    ports:
      - "8444:3000"
    volumes:
      - ./config:/config
YAML
  ok "VS Code Docker 已启动"
  info "访问地址：http://$(get_public_ip):8444/?tkn=$token"
  info "连接 Token：$token"
}

app_vscode_remove() {
  app_compose_down vscode || return 1
  info "容器已移除，config 目录仍保留"
}
