#!/usr/bin/env bash
# Nginx Proxy Manager：图形化反代与证书管理

app_npm_install() {
  docker_require || return 1
  app_compose_up npm <<'YAML' || return 1
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: sst-npm
    restart: unless-stopped
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
      - /etc/localtime:/etc/localtime:ro
YAML
  ok "Nginx Proxy Manager 已启动：http://$(get_public_ip):81"
  info "默认账号 admin@example.com / changeme，首次登录会要求修改"
  warn "占用宿主机 80/443 端口，请勿与其他建站环境同时部署"
}

app_npm_remove() {
  app_compose_down npm || return 1
  info "容器已移除，data/letsencrypt 数据仍保留"
}
