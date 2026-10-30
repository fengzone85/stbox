#!/usr/bin/env bash
# Nginx：静态站点容器

app_nginx_install() {
  docker_require || return 1
  local dir
  dir=$(app_data_dir nginx)
  mkdir -p "$dir/html"
  if [[ ! -f $dir/html/index.html ]]; then
    cat >"$dir/html/index.html" <<'HTML'
<!doctype html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>STBOX</title></head>
<body style="font-family:system-ui;padding:40px">
<h1>Nginx 已就绪</h1>
<p>站点目录：data/apps/nginx/html</p>
</body>
</html>
HTML
  fi
  cat <<YAML | app_compose_up nginx || return 1
services:
  nginx:
    image: nginx:alpine
    container_name: sst-nginx
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
YAML
  ok "Nginx 已启动：http://$(get_public_ip):80"
  info "修改页面：$dir/html/index.html"
}

app_nginx_remove() {
  app_compose_down nginx || return 1
  info "容器已移除，站点文件仍保留在 data/apps/nginx/html"
}
