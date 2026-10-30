#!/usr/bin/env bash
# code-server：Web 版 VS Code

app_code_server_install() {
  docker_require || return 1
  local pass
  pass=$(ask "Web 访问密码（字母数字._-）" "changeme")
  [[ $pass =~ ^[A-Za-z0-9._-]+$ ]] || die "密码仅支持字母、数字、点、下划线和短横线"
  app_compose_up code-server <<YAML || return 1
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: sst-code-server
    restart: unless-stopped
    environment:
      PUID: 1000
      PGID: 1000
      TZ: Asia/Shanghai
      PASSWORD: $pass
    ports:
      - "8443:8443"
    volumes:
      - ./config:/config
YAML
  ok "code-server 已启动：https://$(get_public_ip):8443"
  info "访问密码：$pass"
}

app_code_server_remove() {
  app_compose_down code-server || return 1
  info "容器已移除，config 目录仍保留"
}
