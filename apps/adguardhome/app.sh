#!/usr/bin/env bash
# AdGuard Home：DNS 去广告

app_adguardhome_install() {
  docker_require || return 1
  mkdir -p "$(app_data_dir adguardhome)/work" "$(app_data_dir adguardhome)/conf"
  app_compose_up adguardhome <<'YAML' || return 1
services:
  adguardhome:
    image: adguard/adguardhome:latest
    container_name: sst-adguardhome
    restart: unless-stopped
    ports:
      - "3000:3000"
      - "53:53/tcp"
      - "53:53/udp"
    volumes:
      - ./work:/opt/adguardhome/work
      - ./conf:/opt/adguardhome/conf
YAML
  ok "AdGuard Home 已启动：http://$(get_public_ip):3000"
  warn "占用宿主机 53 端口，部署前请确认没有其他 DNS 服务（如 systemd-resolved）"
}

app_adguardhome_remove() {
  app_compose_down adguardhome || return 1
  info "容器已移除，work/conf 目录仍保留"
}
