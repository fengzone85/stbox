#!/usr/bin/env bash
# Portainer：Docker 可视化管理面板

app_portainer_install() {
  docker_require || return 1
  app_compose_up portainer <<'YAML' || return 1
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
volumes:
  portainer_data:
YAML
  ok "Portainer 已启动：https://$(get_public_ip):9443"
  info "首次访问需在浏览器中设置管理员账号"
}

app_portainer_remove() {
  app_compose_down portainer || return 1
  info "容器已移除，数据卷 portainer_data 仍保留在 Docker 中"
}
