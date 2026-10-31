# STBOX · SSH Tool Box

面向 Linux 服务器的模块化脚本工具箱，使用 Bash 编写，同时提供交互菜单和命令行调用。

- 分层结构：核心框架 + 内置模块 + 应用/脚本插件
- 14 个功能模块、12 个 Docker 应用、72 个外部脚本入口
- 已在 Debian 13 / Intel J4125 完成主要功能实测
- 所有系统级操作默认需要确认，配置变更前自动备份

## 功能概览

| 模块 | 功能 |
|---|---|
| 开荒向导 | 服务器预检、磁盘检测与已有文件系统挂载、时区/主机名/DNS/时间同步/更新策略、账户、SSH 改端口、防火墙与 Fail2ban、安全 sysctl/SWAP/BBR、验收报告 |
| 系统维护 | 系统概览、环境信息、负载、内存与缓存、磁盘、更新、深度清理、DNS、时区、主机名、root 密码、端口扫描、cron、快捷命令 |
| 网络测试 | 网卡/IP/归属地、下载测速、ping、路由追踪、DNS 检测、端口连通、监听端口 |
| 系统优化 | sysctl 网络参数、SWAP 创建/移除、IPv4/IPv6 优先级、apt 换源 |
| 性能测试 | 内存压力、磁盘读写、CPU 基准、NodeQuality、TcpQuality、第三方综合测试 |
| Docker | 安装、状态、容器、日志、进入容器、镜像、网络、数据卷、Compose 项目启停/更新、清理、卸载 |
| 应用市场 | 一键部署常用 Docker 应用 |
| 建站环境 | Apache + PHP 8.2 + MariaDB + Redis，静态站、WordPress、反向代理、SSL、站点备份 |
| AI 工具 | Claude Code、Codex、Gemini CLI、Qoder 国际版/CN、CodeBuddy 国际版/国内版、Grok Build、OpenCode、OpenClaw、Hermes、Pi、MiniMax Code、Kimi Code、Oh My Pi、CC Switch CLI 部署 |
| 实用工具 | 磁盘挂载、Git、Rclone、Fclone、WARP、BBR3、Nezha/Komari/Diting 探针、节点/面板/代理/甲骨文/NAT/多套 DD 重装入口 |
| 组件环境 | 22 个常用组件与游戏、Python/Node.js/Go/Java、Ansible、tmux 工作区 |
| 安全与优化 | UFW/firewalld、SSH 端口与登录策略、BBR、Fail2ban |
| 备份迁移 | 目录备份、MySQL 导出、恢复、定时任务、远程传输 |
| 脚本设置 | 版本、更新、配置、日志 |

## 环境要求

- Linux，Bash 4.2+
- root 权限（脚本会自动通过 sudo 重新执行）
- Debian/Ubuntu、RHEL/CentOS/Fedora/Rocky/Alma、Alpine、Arch 等主流发行版
- Docker 可选（应用市场、建站环境需要）
- 建站环境需要空闲的 80/443 端口

## 安装

```bash
git clone https://github.com/fengzone85/stbox.git
cd stbox
sudo bash install.sh
```

安装完成后会注册 `st` 命令：

```bash
st                 # 交互菜单
st help            # 命令帮助
st --no-color version
st --plain version # 无色、ASCII 边框
```

默认安装目录 `/opt/ssh-tools`，配置、数据、日志目录权限为 700，属主 root。

## 界面预览

```text
╭─ STBOX 0.5.0 ────────────────────────────────────────╮
│ SSH Tool Box · Debian 13 · 内核 6.1                  │
│ feng-5100 · SSH 22 · UFW active · BBR bbr            │
│ 开荒向导 3/8 完成 · 下一步：账户设置                 │
╰──────────────────────────────────────────────────────╯

│ 开荒向导 3/8 完成 · 下一步：账户设置

  ✓ 预检     ✓ 磁盘     ✓ 基础     → 账户
  · SSH      · 防火墙   · 加固     · 报告
```

`st --plain` 会关闭彩色和 Unicode 边框，适合日志、CI 或远程录制。

## 常用命令

```bash
# 开荒向导
st init                  # 开始/继续开荒（需交互终端）
st init preflight        # 服务器预检
st init disk scan        # 只读磁盘扫描
st init basics           # 基础信息设置
st init accounts         # 账户设置（root 密码/管理用户）
st init ssh              # SSH 端口/密码登录/root 登录
st init ssh keep         # 验证新端口后保留配置
st init ssh rollback     # 立即回滚 SSH
st init firewall         # 防火墙与 Fail2ban
st init hardening        # 安全 sysctl / SWAP / BBR
st init status           # 查看进度
st init report           # 生成开荒报告

# 系统
st system info
st system update
st --yes system clean_deep
st --yes system dns 223.5.5.5 1.1.1.1
st system timezone Asia/Shanghai
st system cron list
st system shortcut z

# 网络与优化
st network ip
st network speed 100
st tune status
st --yes tune sysctl on
st --yes tune swap create
st --yes tune ipv6 4
st --yes tune mirror aliyun

# Docker 与应用
st docker status
st docker ps
st docker logs
st app list
st app install npm

# 建站
st site install
st site add
st site wordpress
st site ssl
st site list
st site backup

# 组件与工具
st components list
printf '5\n' | sudo st --yes components install    # 安装 htop
st tools disk_mount
st tools rclone
st tools nodes

# 安全与备份
st security status
st security bbr_status
st --yes backup create /etc /var/www
st backup list
```

自动化场景使用 `--yes` 跳过普通确认；恢复备份仍需 `RESTORE`，卸载建站环境仍需 `REMOVE`。

## 开荒向导

用于新 VPS / 新服务器的安全初始化，包含：

- **预检**：系统、CPU/内存/磁盘、SWAP、公网 IP、SSH 端口与登录策略、防火墙、Docker、BBR、密钥状态
- **磁盘检测**：只读列出设备、分区、文件系统、UUID、SSD/HDD、系统盘链路；可协助挂载已有文件系统
- **基础信息**：时区、主机名、时间同步、DNS、更新策略
- **账户**：root 密码自定义/随机、创建管理用户 + sudo + 密钥
- **SSH**：默认新增非 22 端口并保留旧端口、禁用密码登录、root 登录策略
- **防火墙**：UFW/firewalld 默认拒绝入站，放行全部 SSH 端口，可选 80/443，可选 Fail2ban
- **系统加固**：安全 sysctl（syncookies、禁重定向、源路由、硬链接/软链接保护）、可选严格 rp_filter、SWAP、BBR
- **状态与报告**：进度保存在 `data/init/state.conf`，报告写入 `data/init/report-*.md`

安全性约定：

- 向导**不提供磁盘格式化**，只在已有文件系统上协助挂载
- 挂载前拒绝系统盘、swap、LVM、RAID、LUKS；自动备份 `/etc/fstab`
- SSH 改端口采用“新增端口 + 保留旧端口”，验证后再决定是否清理旧端口
- SSH 变更默认启用 10 分钟自动回滚；`st init ssh keep` 确认保留，`st init ssh rollback` 立即回滚
- 禁用密码登录前检查 `authorized_keys`；禁止 root SSH 前验证管理用户密钥与 sudo
- 防火墙启用前自动放行全部 SSH 端口
- 安全 sysctl 使用独立配置文件，可移除；严格 rp_filter 会提示 VPN/多网卡风险
- SWAP 仅引导创建独立 `/swapfile`，btrfs/ZFS 根分区不自动处理
- 自动更新由用户选择，不默认开启
- 报告权限 600，不保存密码/私钥

兼容性：

- Debian 13：完整实测
- Rocky Linux 9 / RHEL 系：预检、内存回退、用户与防火墙路径已做兼容；systemd 固有能力需真实服务器验证
- Alpine 3.20：预检、状态、磁盘扫描通过；无 systemd 时自动回滚、hostnamectl/timedatectl 会跳过或回退
- 不再支持 CentOS

## 应用市场

| 应用 | 端口 | 说明 |
|---|---|---|
| Nginx Proxy Manager | 81 | 反代与 SSL 证书管理 |
| AList | 5244 | 多存储文件列表 |
| qBittorrent | 8080 | BT 下载面板 |
| Cloudreve | 5212 | 私有云盘 |
| code-server | 8443 | Web VS Code |
| VS Code Docker | 8444 | OpenVSCode Server，Token 访问 |
| AdGuard Home | 3000 | DNS 去广告 |
| Memos | 5230 | 网页备忘录 |
| 青龙面板 | 5700 | 定时任务管理 |
| Uptime Kuma | 3001 | 可用性监控 |
| Portainer | 9443 | Docker 管理面板 |
| Nginx | 80 | 静态站点 |

## 脚本市场

外部脚本按分类登记，执行前展示来源、风险等级并要求确认：

- 测试：综合性能、IP 质量、流媒体解锁、三网测速、回程路由
- 节点：Sing-box、Xray、Hysteria2、Tuic、Juicity、Reality、X-UI、3X-UI、OpenVPN 等
- 面板：1Panel、aaPanel、宝塔、雷池 WAF、哪吒
- 甲骨文：实例保活、实例管理
- NAT：PVE、LXD、Incus 母鸡安装
- 重装：InstallNET
- 网络/内核：WARP、BBR3/tcpx

脚本使用 HTTPS 下载到 `data/scripts/`，支持可选 SHA256 校验；GitHub raw 不可达时自动切换 jsDelivr / gh-proxy 镜像。

## 安全设计

- 系统变更前确认，展示影响范围
- SSH 修改前备份配置并执行 `sshd -t` 校验；改端口采用新增而非替换
- 启用 UFW 前自动放行当前 SSH 端口
- 备份恢复要求输入 `RESTORE`，目标目录不存在时自动创建
- 建站环境卸载要求输入 `REMOVE`
- sysctl/limits 写入独立配置文件，不覆盖系统原有配置
- 第三方脚本统一登记来源与风险，不使用 `curl | bash` 直通
- root 密码通过 stdin 传递，不写入日志

## 目录结构

```text
stbox/
├── st.sh               # 入口
├── install.sh          # 安装脚本
├── core/               # 框架：界面组件、公共函数、配置、菜单、脚本市场
├── modules/            # 12 个功能模块
├── apps/               # Docker 应用插件
├── scripts/            # 第三方脚本清单
├── plugins/            # 用户扩展（apps/scripts）
├── docs/design.md      # 设计文档
├── config/             # 运行时配置
├── data/               # 备份、应用数据、脚本缓存
└── logs/               # 运行日志
```

## 扩展

新增模块：

```bash
# modules/demo.sh
sst_register_module demo "示例模块" "示例功能"
SST_MODULE_ITEMS[demo]=$'hello|打招呼\ninfo|查看信息'

demo_hello() { echo "hello"; }
demo_info() { echo "info"; }
```

新增应用：`apps/<name>/app.conf` + `app.sh`，实现 `app_<name>_install` / `app_<name>_remove`。

新增外部脚本：`scripts/<name>.conf`，填写 `SCRIPT_TITLE / SCRIPT_URL / SCRIPT_MODE / SCRIPT_RISK`。

语法检查：

```bash
bash -n st.sh install.sh core/*.sh modules/*.sh apps/*/app.sh scripts/*.conf
bash tests/ui.sh
bash tests/scripts.sh
bash tests/ai.sh
sudo bash tests/init_hardening.sh
```

## 文档

- [设计文档](docs/design.md)：架构、模块契约、应用/脚本插件、安全设计、命令规范

## 风险声明

- 脚本市场中的内容来自各自上游作者，版权归原作者所有
- 节点代理、NAT 母鸡、重装系统、面板安装等属于高风险操作，请确认用途合法并提前备份
- 生产环境执行系统升级、防火墙、SSH、磁盘操作前，建议先在测试机验证
