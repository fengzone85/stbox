#!/usr/bin/env bash
# qBittorrent：BT 下载面板

app_qbittorrent_install() {
  docker_require || return 1
  app_compose_up qbittorrent <<'YAML' || return 1
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: sst-qbittorrent
    restart: unless-stopped
    environment:
      PUID: 1000
      PGID: 1000
      TZ: Asia/Shanghai
      WEBUI_PORT: 8080
    ports:
      - "8080:8080"
      - "6881:6881"
      - "6881:6881/udp"
    volumes:
      - ./config:/config
      - ./downloads:/downloads
YAML
  ok "qBittorrent 已启动：http://$(get_public_ip):8080"
  info "下载目录：$(app_data_dir qbittorrent)/downloads"
  warn "WebUI 默认无密码，请首次登录后在设置中启用认证"
}

app_qbittorrent_remove() {
  app_compose_down qbittorrent || return 1
  info "容器已移除，config 与 downloads 目录仍保留"
}
