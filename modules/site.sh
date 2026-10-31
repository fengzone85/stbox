#!/usr/bin/env bash
# 模块：建站环境（Docker 版：Apache + PHP 8.2 + MariaDB + Redis）
# 原生实现：Apache+PHP 8.2、MariaDB、Redis 均为独立容器。

sst_register_module site "建站环境" "静态站 WordPress 反代 SSL"
SST_MODULE_ITEMS[site]=$'install|安装建站环境\nstatus|环境状态\nadd|新建静态站点\nwordpress|安装 WordPress\nproxy|新建反向代理\nssl|申请 SSL 证书\nlist|站点列表\nremove|删除站点\nbackup|备份站点数据\nupdate|更新环境镜像\nuninstall|卸载建站环境'

SITE_ROOT=/home/web
SITE_COMPOSE="$SITE_ROOT/compose.yml"
SITE_CONF_DIR="$SITE_ROOT/conf"
SITE_HTML_DIR="$SITE_ROOT/html"

site_require() {
  [[ -f $SITE_COMPOSE ]] || die "建站环境未安装，请先执行：st site install"
  docker info >/dev/null 2>&1 || die "Docker 未运行，请先启动 Docker"
}

site_web_running() {
  [[ $(docker inspect -f '{{.State.Status}}' sst-web 2>/dev/null) == "running" ]]
}

site_db_pass() {
  awk -F= '$1 == "MARIADB_ROOT_PASSWORD" {print $2}' "$SITE_ROOT/.env" 2>/dev/null
}

# 在容器内使用 MYSQL_PWD，避免密码出现在宿主机 argv
site_db_exec() {
  docker exec -i sst-db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot'
}

site_valid_domain() {
  local d=$1
  [[ $d =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "域名格式无效：$d"
  [[ $d != *".."* ]] || die "域名格式无效：$d"
  printf '%s' "$d"
}

site_reload() {
  if site_web_running; then
    docker exec sst-web apache2ctl graceful >/dev/null 2>&1 || docker restart sst-web >/dev/null
    ok "Web 服务已重载"
  else
    warn "sst-web 容器未运行，配置已写入，启动容器后生效"
  fi
}

site_db_wait() {
  local i
  for i in $(seq 1 30); do
    if docker exec sst-db sh -c \
      'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -N -e "SELECT 1"' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

site_write_http_vhost() {
  local domain=$1 docroot=$2 target=${3:-}
  local conf="$SITE_CONF_DIR/$domain.conf"
  {
    printf '<VirtualHost *:80>\n'
    printf '  ServerName %s\n' "$domain"
    printf '  DocumentRoot /var/www/html/%s\n' "$docroot"
    printf '  <Directory /var/www/html/%s>\n' "$docroot"
    printf '    Options -Indexes\n'
    printf '    AllowOverride All\n'
    printf '    Require all granted\n'
    printf '  </Directory>\n'
    if [[ -n $target ]]; then
      printf '  ProxyPreserveHost On\n'
      printf '  ProxyPass / http://%s/\n' "$target"
      printf '  ProxyPassReverse / http://%s/\n' "$target"
    fi
    printf '  ErrorLog /var/log/apache2/%s-error.log\n' "$domain"
    printf '  CustomLog /var/log/apache2/%s-access.log combined\n' "$domain"
    printf '</VirtualHost>\n'
  } >"$conf"
  chmod 644 "$conf"
}

site_append_ssl_vhost() {
  local domain=$1 docroot=$2 target=${3:-}
  local conf="$SITE_CONF_DIR/$domain.conf"
  local cert="/etc/apache2/certs/${domain}_cert.pem"
  local key="/etc/apache2/certs/${domain}_key.pem"
  [[ -f "$SITE_ROOT/certs/${domain}_cert.pem" && -f "$SITE_ROOT/certs/${domain}_key.pem" ]] || return 1
  grep -Fq "ServerName $domain" "$conf" 2>/dev/null || site_write_http_vhost "$domain" "$docroot" "$target"

  if grep -q 'VirtualHost \*:443' "$conf" 2>/dev/null; then
    return 0
  fi
  {
    printf '\n<VirtualHost *:443>\n'
    printf '  ServerName %s\n' "$domain"
    printf '  DocumentRoot /var/www/html/%s\n' "$docroot"
    printf '  SSLEngine on\n'
    printf '  SSLCertificateFile %s\n' "$cert"
    printf '  SSLCertificateKeyFile %s\n' "$key"
    printf '  <Directory /var/www/html/%s>\n' "$docroot"
    printf '    Options -Indexes\n'
    printf '    AllowOverride All\n'
    printf '    Require all granted\n'
    printf '  </Directory>\n'
    if [[ -n $target ]]; then
      printf '  ProxyPreserveHost On\n'
      printf '  ProxyPass / http://%s/\n' "$target"
      printf '  ProxyPassReverse / http://%s/\n' "$target"
    fi
    printf '  ErrorLog /var/log/apache2/%s-ssl-error.log\n' "$domain"
    printf '  CustomLog /var/log/apache2/%s-ssl-access.log combined\n' "$domain"
    printf '</VirtualHost>\n'
  } >>"$conf"
}

site_add() {
  require_root
  site_require
  local domain
  domain=$(ask "站点域名（先用测试域名即可）" "")
  [[ -n $domain ]] || return 0
  site_valid_domain "$domain" >/dev/null

  local dir="$SITE_HTML_DIR/$domain"
  mkdir -p "$dir"
  if [[ ! -f $dir/index.html ]]; then
    cat >"$dir/index.html" <<EOF
<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><title>$domain</title></head>
<body style="font-family:system-ui;padding:40px"><h1>$domain</h1><p>站点已创建。</p></body></html>
EOF
  fi

  site_write_http_vhost "$domain" "$domain"
  local docroot="$domain"
  site_append_ssl_vhost "$domain" "$docroot" || true
  chown -R 33:33 "$dir" 2>/dev/null || true
  site_reload
  ok "静态站点已创建：http://$domain"
  info "站点目录：$dir"
}

site_proxy() {
  require_root
  site_require
  local domain target
  domain=$(ask "反代域名" "")
  [[ -n $domain ]] || return 0
  site_valid_domain "$domain" >/dev/null
  target=$(ask "后端地址（host:port）" "127.0.0.1:8080")
  [[ $target =~ ^[A-Za-z0-9._:-]+$ ]] || die "后端地址格式无效"

  local dir="$SITE_HTML_DIR/$domain"
  mkdir -p "$dir"
  site_write_http_vhost "$domain" "$domain" "$target"
  site_append_ssl_vhost "$domain" "$domain" "$target" || true
  site_reload
  ok "反向代理已创建：http://$domain → http://$target"
}

site_ssl() {
  require_root
  site_require
  local domain email
  domain=$(ask "需要申请证书的域名" "")
  [[ -n $domain ]] || return 0
  site_valid_domain "$domain" >/dev/null
  email=$(ask "Let's Encrypt 邮箱" "admin@$domain")
  [[ $email == *@* ]] || die "邮箱格式无效"

  confirm "申请 $domain 的 Let's Encrypt 证书？申请期间会短暂停止 Web 容器" || return 0
  ensure_tool certbot certbot || return 1
  mkdir -p "$SITE_ROOT/certs"

  info "停止 Web 容器以释放 80 端口…"
  docker stop sst-web >/dev/null 2>&1 || true
  if ! certbot certonly --standalone -d "$domain" --email "$email" --agree-tos --no-eff-email --force-renewal; then
    docker start sst-web >/dev/null 2>&1 || true
    die "证书申请失败，请确认域名解析到本机且 80 端口可用"
  fi
  docker start sst-web >/dev/null 2>&1 || true

  cp "/etc/letsencrypt/live/$domain/cert.pem" "$SITE_ROOT/certs/${domain}_cert.pem" || die "复制证书失败"
  cp "/etc/letsencrypt/live/$domain/privkey.pem" "$SITE_ROOT/certs/${domain}_key.pem" || die "复制私钥失败"
  chmod 600 "$SITE_ROOT/certs/${domain}_key.pem" 2>/dev/null || true

  local docroot=$domain
  local target=''
  if [[ -f $SITE_CONF_DIR/$domain.conf ]]; then
    target=$(awk '/^  ProxyPass \/ http:\/\// {print $3}' "$SITE_CONF_DIR/$domain.conf" | head -n 1)
    target=${target#http://}
    target=${target%/}
  fi
  site_append_ssl_vhost "$domain" "$docroot" "$target"
  site_reload
  ok "证书已部署：https://$domain"
  info "证书续期：certbot renew 后复制到 $SITE_ROOT/certs，可加入 cron"
}

site_wordpress() {
  require_root
  site_require
  local domain
  domain=$(ask "WordPress 域名" "")
  [[ -n $domain ]] || return 0
  site_valid_domain "$domain" >/dev/null

  ensure_tool unzip unzip || return 1
  ensure_tool openssl openssl || return 1

  local dir="$SITE_HTML_DIR/$domain"
  mkdir -p "$dir"
  info "下载 WordPress 中文版…"
  local tmp
  tmp=$(mktemp -d)
  if ! curl -fsSL --connect-timeout 10 --max-time 300 -o "$tmp/wp.zip" \
    https://cn.wordpress.org/latest-zh_CN.zip; then
    rm -rf "$tmp"
    die "WordPress 下载失败"
  fi
  unzip -q -o "$tmp/wp.zip" -d "$tmp" || { rm -rf "$tmp"; die "解压失败"; }
  cp -a "$tmp/wordpress/." "$dir/"
  rm -rf "$tmp"

  local rootpass dbname dbuser dbpass
  rootpass=$(site_db_pass)
  [[ -n $rootpass ]] || die "读取数据库密码失败：$SITE_ROOT/.env"
  dbname="wp_$(printf '%s' "$domain" | sed 's/[^A-Za-z0-9]/_/g')"
  dbuser="$dbname"
  dbpass=$(openssl rand -hex 12)
  site_db_wait || die "数据库未就绪，请稍后重试"

  info "创建数据库与用户：$dbname"
  site_db_exec <<SQL || die "创建数据库失败"
CREATE DATABASE IF NOT EXISTS \`$dbname\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$dbuser'@'%' IDENTIFIED BY '$dbpass';
GRANT ALL PRIVILEGES ON \`$dbname\`.* TO '$dbuser'@'%';
FLUSH PRIVILEGES;
SQL

  info "生成 wp-config.php…"
  local -A salts=()
  local k
  for k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
    salts[$k]=$(openssl rand -base64 48 | tr -d '\n')
  done
  cat >"$dir/wp-config.php" <<EOF
<?php
define('DB_NAME', '$dbname');
define('DB_USER', '$dbuser');
define('DB_PASSWORD', '$dbpass');
define('DB_HOST', 'db');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');
define('AUTH_KEY', '${salts[AUTH_KEY]}');
define('SECURE_AUTH_KEY', '${salts[SECURE_AUTH_KEY]}');
define('LOGGED_IN_KEY', '${salts[LOGGED_IN_KEY]}');
define('NONCE_KEY', '${salts[NONCE_KEY]}');
define('AUTH_SALT', '${salts[AUTH_SALT]}');
define('SECURE_AUTH_SALT', '${salts[SECURE_AUTH_SALT]}');
define('LOGGED_IN_SALT', '${salts[LOGGED_IN_SALT]}');
define('NONCE_SALT', '${salts[NONCE_SALT]}');
\$table_prefix = 'wp_';
define('WP_DEBUG', false);
if ( ! defined( 'ABSPATH' ) ) { define( 'ABSPATH', __DIR__ . '/' ); }
require_once ABSPATH . 'wp-settings.php';
EOF
  chown -R 33:33 "$dir" 2>/dev/null || true

  site_write_http_vhost "$domain" "$domain"
  site_append_ssl_vhost "$domain" "$domain" || true
  site_reload
  ok "WordPress 已安装：http://$domain"
  if confirm "现在申请 HTTPS 证书？"; then
    site_ssl
  fi
}

site_list() {
  site_require
  section "站点列表"
  local conf domain
  if ! compgen -G "$SITE_CONF_DIR/*.conf" >/dev/null 2>&1; then
    info "暂无站点"
    return 0
  fi
  printf '  %-24s %-10s %s\n' "域名" "HTTPS" "配置文件"
  hr
  for conf in "$SITE_CONF_DIR"/*.conf; do
    domain=$(awk '/^  ServerName/ {print $2; exit}' "$conf")
    [[ -n $domain ]] || continue
    printf '  %-24s %-10s %s\n' \
      "$domain" \
      "$(grep -q 'VirtualHost \*:443' "$conf" && echo 已启用 || echo 未启用)" \
      "$(basename "$conf")"
  done
}

site_remove() {
  require_root
  site_require
  local domain
  domain=${1:-}
  [[ -n $domain ]] || domain=$(ask "要删除的域名" "")
  [[ -n $domain ]] || return 0
  site_valid_domain "$domain" >/dev/null
  [[ -f $SITE_CONF_DIR/$domain.conf ]] || die "站点不存在：$domain"

  confirm "删除站点 $domain 的配置与文件（数据库默认保留）？" || return 0
  rm -f "$SITE_CONF_DIR/$domain.conf"
  rm -rf "${SITE_HTML_DIR:?}/$domain"
  rm -f "$SITE_ROOT/certs/${domain}_cert.pem" "$SITE_ROOT/certs/${domain}_key.pem"
  site_reload

  if confirm "同时删除该站点的数据库 wp_$(printf '%s' "$domain" | sed 's/[^A-Za-z0-9]/_/g')？"; then
    site_db_exec <<SQL || warn "数据库删除失败"
DROP DATABASE IF EXISTS \`wp_$(printf '%s' "$domain" | sed 's/[^A-Za-z0-9]/_/g')\`;
SQL
  fi
  ok "站点已删除：$domain"
}

site_status() {
  section "建站环境状态"
  if [[ ! -f $SITE_COMPOSE ]]; then
    warn "未安装，可执行：st site install"
    return 1
  fi
  kv "目录" "$SITE_ROOT"
  kv "Web 容器" "$(docker inspect -f '{{.State.Status}}' sst-web 2>/dev/null || echo 未创建)"
  kv "数据库容器" "$(docker inspect -f '{{.State.Status}}' sst-db 2>/dev/null || echo 未创建)"
  kv "Redis 容器" "$(docker inspect -f '{{.State.Status}}' sst-redis 2>/dev/null || echo 未创建)"
  printf '\n'
  compose_run -f "$SITE_COMPOSE" ps 2>/dev/null || true
}

site_backup() {
  require_root
  site_require
  local dir ts file tmpd
  dir=$(backup_dir_get)
  mkdir -p "$dir"
  ts=$(date +%Y%m%d-%H%M%S)
  file="$dir/site-$ts.tar.gz"
  tmpd=$(mktemp -d)

  info "导出数据库…"
  if ! docker exec sst-db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --single-transaction --all-databases' >"$tmpd/database.sql" 2>/dev/null; then
    warn "数据库导出失败，继续备份文件（备份中将不含数据库）"
    rm -f "$tmpd/database.sql"
  fi

  info "打包站点文件…"
  local -a extra=()
  [[ -f $tmpd/database.sql ]] && extra=(-C "$tmpd" database.sql)
  if ! tar --ignore-failed-read -czf "$file" \
    -C "$SITE_ROOT" html conf certs .env "${extra[@]}"; then
    rm -rf "$tmpd"
    rm -f "$file"
    die "站点备份失败"
  fi
  rm -rf "$tmpd"
  {
    printf 'host=%s\n' "$(hostname)"
    printf 'time=%s\n' "$(date '+%F %T')"
    printf 'type=lnmp-site\n'
  } >"$file.manifest"
  ok "站点备份完成：$file（$(du -h "$file" | cut -f1)）"
}

site_update() {
  require_root
  site_require
  confirm "重新构建 PHP 镜像并更新容器？" || return 0
  compose_run -f "$SITE_COMPOSE" build --pull || die "镜像构建失败"
  compose_run -f "$SITE_COMPOSE" up -d || die "容器更新失败"
  ok "建站环境已更新"
}

site_install() {
  require_root
  docker_require || die "需要先安装并启动 Docker"

  if [[ -f $SITE_COMPOSE ]]; then
    info "建站环境已存在：$SITE_ROOT"
    confirm "重新生成配置并重建容器？（站点文件与数据库保留）" || return 0
  fi
  if ! site_web_running && ss -tln 2>/dev/null | awk '{print $4}' | grep -qE '(:80|:443)$'; then
    die "80/443 端口已被占用，请先停止占用服务（如系统 Nginx/Apache）"
  fi

  confirm "安装建站环境（PHP 8.2 + MariaDB + Redis，首次构建镜像需要数分钟）？" || return 0
  ensure_tool openssl openssl || return 1

  mkdir -p "$SITE_ROOT"/{html,conf,certs,mysql,redis,logs,php}
  local dbpass
  dbpass=$(openssl rand -hex 16)
  cat >"$SITE_ROOT/.env" <<EOF
MARIADB_ROOT_PASSWORD=$dbpass
EOF
  chmod 600 "$SITE_ROOT/.env"

  cat >"$SITE_ROOT/php/Dockerfile" <<'EOF'
FROM php:8.2-apache
RUN apt-get update && apt-get install -y --no-install-recommends \
      libpng-dev libjpeg62-turbo-dev libfreetype6-dev libzip-dev libonig-dev libicu-dev unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" mysqli pdo_mysql gd zip intl bcmath exif opcache \
    && a2enmod rewrite headers expires ssl proxy proxy_http \
    && rm -rf /var/lib/apt/lists/*
EOF

  cat >"$SITE_COMPOSE" <<'EOF'
services:
  web:
    build: ./php
    container_name: sst-web
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./html:/var/www/html
      - ./conf:/etc/apache2/sites-enabled
      - ./certs:/etc/apache2/certs
      - ./logs:/var/log/apache2
    depends_on:
      - db
      - redis
  db:
    image: mariadb:11
    container_name: sst-db
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${MARIADB_ROOT_PASSWORD}
    volumes:
      - ./mysql:/var/lib/mysql
  redis:
    image: redis:7-alpine
    container_name: sst-redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - ./redis:/data
EOF

  cat >"$SITE_CONF_DIR/000-default.conf" <<'EOF'
<VirtualHost *:80>
  ServerName default
  DocumentRoot /var/www/html
  <Directory /var/www/html>
    Options -Indexes
    AllowOverride All
    Require all granted
  </Directory>
  ErrorLog /var/log/apache2/default-error.log
  CustomLog /var/log/apache2/default-access.log combined
</VirtualHost>
EOF
  chmod 644 "$SITE_CONF_DIR/000-default.conf"

  info "构建并启动容器…"
  compose_run -f "$SITE_COMPOSE" up -d --build || die "建站环境启动失败"
  ok "建站环境安装完成"
  info "站点目录：$SITE_ROOT/html；配置目录：$SITE_CONF_DIR"
  compose_run -f "$SITE_COMPOSE" ps 2>/dev/null || true
}

site_uninstall() {
  require_root
  site_require
  warn "卸载会删除容器、数据库卷与 Redis 数据；站点文件默认保留"
  local phrase
  read -r -p "输入 REMOVE 确认卸载 建站环境: " phrase || return 1
  [[ $phrase == REMOVE ]] || { warn "已取消"; return 0; }
  compose_run -f "$SITE_COMPOSE" down -v --remove-orphans || die "卸载失败"
  if confirm "同时删除 $SITE_ROOT（站点文件、证书、数据库目录）？"; then
    rm -rf "$SITE_ROOT"
    ok "建站目录已删除"
  fi
  ok "建站环境已卸载"
}
