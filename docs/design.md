# STBOX（SSH Tool Box）设计文档

> 面向 Linux 服务器的模块化脚本工具箱，采用 **核心框架 + 内置模块 + 应用/脚本插件** 三层结构，
> 同时提供交互菜单与命令行调用。

版本基线：v0.5.0（已在 Debian 13 / J4125 完成主要功能实测）

---

## 1. 目标与非目标

### 目标

- 一条命令进入菜单，覆盖系统、网络、Docker、应用部署、安全优化、备份迁移。
- 同时支持交互菜单与命令行调用（`st <模块> <操作>`），便于 SSH 临时操作与自动化。
- 模块边界清晰：新增功能只加一个文件，不改入口脚本。
- 应用插件化：新应用只需 `apps/<name>/app.conf + app.sh`，自动出现在应用市场。
- 第三方能力可控：外部脚本统一登记、显式展示来源与风险、确认后执行，不做 `curl | bash` 直通。
- 变更类操作具备基本安全护栏：影响范围提示、配置备份、语法校验、失败回滚。

### 非目标（当前版本）

- 不做 Web 管理面板（可后续作为独立前端复用后端脚本）。
- 不实现完整包管理系统，只基于系统包管理器做最小依赖安装。
- 不内置第三方闭源脚本；应用安装只使用官方镜像与官方 Compose 定义。

---

## 2. 总体架构

```
                    ┌──────────────────────────┐
                    │          st.sh           │
                    └────────────┬─────────────┘
                                 │
   ┌──────────────┬──────────────┼──────────────┬──────────────┐
   ▼              ▼              ▼              ▼              ▼
core/common    core/menu      core/apps     core/scripts   core/config
基础能力       菜单/CLI       应用插件       第三方脚本市场  配置/更新
                    │              │              │
                    ▼              ▼              ▼
              modules/*.sh     apps/*/       scripts/*.conf
              内置模块          应用插件       脚本清单
                                 │
                         config/ data/ logs/
                         配置    备份/应用数据/脚本缓存  日志
```

### 分层职责

| 层 | 位置 | 职责 | 扩展方式 |
|---|---|---|---|
| 核心框架 | `core/` | 输出、权限、系统探测、菜单、插件加载、版本更新 | 修改框架 |
| 内置模块 | `modules/` | 一个业务域一个文件，注册菜单项并实现动作函数 | 新增 `modules/<name>.sh` |
| 应用插件 | `apps/`、`plugins/apps/` | 应用元数据 + Compose 生命周期 | 新增应用目录 |
| 脚本市场 | `scripts/`、`plugins/scripts/` | 第三方脚本登记、来源与风险展示、下载执行 | 新增 `<name>.conf` |

加载顺序由 `st.sh` 固定：`ui → common → config → apps → scripts → update → menu`，
然后 `sst_load_scripts` 扫描脚本清单，`sst_load_modules` 扫描 `modules/*.sh`，`sst_load_apps` 扫描应用目录。

---

## 3. 目录结构

```
stbox/
├── st.sh                  # 入口命令
├── install.sh             # 部署到 /opt/ssh-tools + 注册 /usr/local/bin/st
├── VERSION
├── core/
│   ├── ui.sh              # 界面能力：配色、符号、宽度、面板、菜单组件
│   ├── common.sh          # 基础能力
│   ├── config.sh          # settings.conf 键值配置
│   ├── wizard.sh          # 开荒向导状态与报告
│   ├── apps.sh            # 应用插件框架
│   ├── scripts.sh         # 第三方脚本市场框架
│   ├── update.sh          # 版本与自更新
│   └── menu.sh            # 菜单与 CLI 分发
├── modules/
│   ├── init.sh            # 开荒向导：预检 / 磁盘 / 基础信息
│   ├── system.sh          # 系统概览 / 环境 / 负载 / 磁盘 / 清理
│   ├── network.sh         # 概览 / IP / 测速 / ping / 路由 / DNS / 端口
│   ├── tune.sh            # sysctl 优化 / SWAP / IPv4-6 优先级 / apt 换源
│   ├── bench.sh           # 内存 / 磁盘 / CPU / 第三方测试入口
│   ├── docker.sh          # 安装 / 状态 / 容器 / 镜像 / 网络 / 卷 / 清理
│   ├── apps.sh            # 应用市场
│   ├── site.sh            # 建站环境（静态站 / WordPress / 反代 / SSL）
│   ├── ai.sh              # Claude Code / Codex / Gemini / OpenCode 等 AI 工具
│   ├── tools.sh           # 磁盘挂载 / Git / Rclone / 探针面板代理入口
│   ├── components.sh      # 常用组件 / Python Node Go Java / tmux 工作区
│   ├── security.sh        # 防火墙 / SSH / BBR / Fail2ban
│   ├── backup.sh          # 备份 / 恢复 / 定时 / 远程
│   └── settings.sh        # 版本 / 更新 / 配置 / 日志
├── apps/
│   ├── portainer/         # Docker 面板
│   ├── uptime-kuma/       # 可用性监控
│   ├── nginx/             # 静态站点
│   ├── npm/ alist/        # 反代 / 网盘
│   ├── qbittorrent/       # BT 下载
│   ├── cloudreve/ memos/  # 网盘 / 备忘录
│   ├── code-server/       # Web VS Code
│   ├── vscode/            # OpenVSCode Server（VS Code Docker）
│   ├── adguardhome/       # DNS 去广告
│   └── qinglong/          # 定时任务面板
├── scripts/               # 第三方脚本清单
├── plugins/apps/          # 用户自定义应用（升级不覆盖）
├── plugins/scripts/       # 用户自定义脚本清单
├── config/                # settings.conf
├── data/
│   ├── backups/           # full-*.tar.gz + manifest，config/ 下配置备份
│   └── apps/<name>/       # 应用 Compose 文件与挂载目录
├── logs/sst.log
└── docs/design.md
```

---

## 4. 执行流程

### 交互

```
st
 └─ require_root（非 root 且可提权时 sudo 重执行）
     └─ 主菜单（模块列表）
         └─ 子菜单（模块内动作）
             └─ <module>_<action>() → 执行 → pause → 返回
```

### 命令行

```
st --yes --no-color system info
 └─ 解析全局开关
     └─ sst_dispatch：version/help 特殊处理 → 模块别名(app/net/sec) → sst_module_run
         └─ <module>_<action>(额外参数)
```

- 模块动作函数命名约定：`<module>_<action>`，例如 `system_info`、`security_bbr_on`。
- 动作需要额外参数时直接透传，例如 `st network speed 100`、`st backup create /etc /var/www`。
- `--yes` 只跳过普通确认；恢复备份仍需输入 `RESTORE`（非交互时例外）。

---

## 5. 模块契约

每个 `modules/<name>.sh` 在加载时注册一次：

```bash
sst_register_module system "系统信息" "CPU 内存 磁盘 流量 与环境"

SST_MODULE_ITEMS[system]=$'info|系统概览\nenv|系统环境\nload|资源负载'
```

- `sst_register_module`：写入标题/描述并追加到 `SST_MODULE_ORDER`，同名模块只注册一次。
- `SST_MODULE_ITEMS`：`动作|菜单标签`，换行分隔；动作名必须与函数 `<module>_<动作>` 对应。
- 模块可按需使用框架函数：`require_root / confirm / ask / info / warn / kv / have / pkg_install / svc_* / get_public_ip`。

新增一个模块不需要修改任何框架代码，只要保证文件名被 `modules/*.sh` 匹配、函数名符合约定。

---

## 6. 应用插件契约

目录：`apps/<name>/` 或 `plugins/apps/<name>/`

`app.conf`（shell 变量，加载时读取）：

```bash
APP_TITLE="Portainer"
APP_DESC="Docker 可视化管理面板"
APP_CATEGORY="面板"
APP_PORT="9443"
APP_URL="https://IP:9443"      # 展示时 IP 替换为公网 IP
```

`app.sh`（生命周期函数）：

```bash
app_<name>_install()   # 必填：部署/重新部署
app_<name>_remove()    # 必填：停止并移除容器
app_<name>_status()    # 可选：缺省使用 docker compose ps
```

> 应用目录名中的 `-` 在函数名中写作 `_`，例如 `apps/code-server/` 对应 `app_code_server_install()`。

Compose 助手（`core/apps.sh`）：

| 函数 | 说明 |
|---|---|
| `app_compose_up <name>` | 从 stdin 读取 YAML，写入 `data/apps/<name>/docker-compose.yml` 并 `up -d` |
| `app_compose_down <name>` | `down --remove-orphans`，不删除命名卷 |
| `app_compose_ps <name>` | 查看项目容器状态 |
| `app_data_dir <name>` | 返回应用数据目录 |
| `app_installed <name>` | 是否存在 Compose 文件（菜单“已部署”标记） |

约定：

- 应用安装前调用 `docker_require`，未安装 Docker 时给出安装入口。
- 数据统一落在命名卷或 `data/apps/<name>/`，移除容器不删数据。
- 端口固定写在 Compose 中并在 `app.conf` 声明；冲突由用户确认。

---

## 7. 第三方脚本市场

部分能力由外部脚本提供，直接内嵌会带来维护与安全问题。本工具箱的做法是：

1. **能原生实现的系统操作自己写**：SWAP、sysctl、gai.conf、apt 换源、磁盘挂载、内存/磁盘/CPU 测试。
2. **测试/节点/面板/代理类外部脚本统一登记到脚本市场**：保留能力，但不复制 `wget --no-check-certificate` 和“下载到 /root 直接运行”的做法。

### 清单格式

`scripts/<name>.conf` 或 `plugins/scripts/<name>.conf`：

```bash
SCRIPT_TITLE="SuperBench"
SCRIPT_DESC="CPU/内存/磁盘/网络综合测试"
SCRIPT_CATEGORY="测试"        # 测试 / 工具 / 面板 / 代理 / 内核
SCRIPT_URL="https://example.com/tool.sh"
SCRIPT_MODE="bash"            # bash | binary
SCRIPT_ARG=""                 # 固定参数，如 LemonBench 的 fast
SCRIPT_ROOT=1                 # 是否需要 root
SCRIPT_RISK="中"              # 低 / 中 / 高
SCRIPT_SHA256=""              # 可选，填写后下载会校验
SCRIPT_ARCH="x86_64"          # 可选，限定架构
```

### 执行流程与安全

```
scripts_run <name>
 ├─ 展示名称、说明、来源 URL、风险等级
 ├─ 需要 root 则先提权
 ├─ 用户确认（--yes 可跳过，但仍打印来源）
 ├─ curl HTTPS 下载到 data/scripts/<name>-<arch>
 ├─ 可选 SHA256 校验
 ├─ bash 文件 / 直接执行二进制，参数显式传入
 └─ 记录退出码，保留脚本缓存
```

安全策略：不使用 `--no-check-certificate`；不通过管道直接执行；不把脚本散落到 `/root`；不静默执行高风险面板/代理安装。

网络回退：原始地址 15 秒内不可达时，GitHub raw 自动切换 `cdn.jsdelivr.net` 或 `gh-proxy.com` 镜像，避免国内服务器长时间卡住（Debian 13 实测 raw.githubusercontent.com 不可达，jsDelivr 可用）。

### 分类

| 分类 | 内容 |
|---|---|
| 测试 | 综合性能、流媒体解锁、IP 质量、三网测速、回程路由 |
| 节点 | Sing-box、Xray、Hysteria2、Tuic、Juicity、Reality、X-UI、3X-UI、OpenVPN 等 |
| 面板 | 1Panel、aaPanel、宝塔、雷池 WAF、哪吒 |
| 甲骨文 | 实例保活、实例管理 |
| NAT | PVE、LXD、Incus 母鸡安装 |
| 重装 | InstallNET 重装/DD 系统 |
| 网络/内核 | WARP、BBR3/tcpx 管理 |

> 节点代理、NAT 母鸡、重装系统属于高风险操作，执行前需要确认用途合法、已有备份，并接受第三方脚本的行为。

---

## 8. 命令规范（v0.5.0）

```
st                                  交互主菜单
st help                             帮助
st version                          版本与路径
st --plain version                  无色 + ASCII 边框输出

st system   info | env | load | memory | disk | clean | update | clean_deep
            dns [地址...] | timezone [时区] | hostname [名称] | rootpass
            portscan [目标] [端口数] | cron [list|add|remove] | shortcut [字母]
st init     wizard | preflight | disk [scan] | basics | accounts
            ssh [keep|rollback|status] | firewall | hardening | status | report | reset
st network  info | ip | speed [MB] | ping [host] | route [host] | dns | port | listen
st tune     status | sysctl [status|on|off] | swap [status|create|remove]
            ipv6 [status|4|6] | mirror [aliyun|tuna|ustc|163|restore]
st bench    memtest | diskbench [MB] | cpu | nodequality | tcpquality | scripts | <脚本名>
st docker   status | install | ps | logs [容器] | restart|start|stop|exec [容器]
            images | networks | volumes | prune | compose | uninstall
st apps     list | menu | install <名称> | remove <名称> | status <名称>
st site     install | status | add | wordpress | proxy | ssl | list | remove | backup | update | uninstall
st ai       status | list | install | claude | codex | gemini | qoder | codebuddy | opencode | ccswitch
st tools    disk_mount | git | rclone | fclone | scripts | probes | panels | nodes | proxy | kernel
            warp | bbr3 | oracle | reinstall | nat | <脚本名>
st components list | install | install_all | remove | custom
            python | nodejs | golang | java | uninstall_env | workspace
st security status | firewall_status | firewall_allow <端口> | firewall_enable | firewall_disable
            ssh_status | ssh_port <端口> | ssh_password | ssh_password_on | ssh_root
            bbr_status | bbr_on | bbr_off | fail2ban_status | fail2ban_install
st backup   list | create [路径...] | restore [文件] [目标] | schedule [remove] | remote [all]
st settings version | update | config | log
```

别名：`app→apps`、`net→network`、`sec→security`。

---

## 9. 配置与数据

- `config/settings.conf`：`KEY=VALUE`，权限 600。当前使用：
  - `BACKUP_DIR`（默认 `data/backups`）
  - `BACKUP_TARGETS`（默认 `/etc /var/www`）
  - `BACKUP_RETENTION`（默认 0/7，定时备份时写入）
- `data/backups/full-<时间戳>.tar.gz` + `.manifest`；配置备份在 `data/backups/config/`。恢复时目标目录不存在会自动创建；非交互模式必须显式指定备份文件。
- `data/scripts/<name>-<arch>`：脚本市场下载缓存，重复执行不必重新下载。
- `data/backups/site-<时间戳>.tar.gz`：建站环境文件与全量数据库备份。
- `/home/web`：建站环境目录（`html/` 站点、`conf/` Apache 配置、`certs/` 证书、`compose.yml`、`.env`）。
- `data/public_ip`：公网 IP 10 分钟缓存，减少外网请求。
- `logs/sst.log`：所有 info/ok/warn/error 落盘（不记录交互输入内容）。
- 定时任务：`/etc/cron.d/sst-backup`，调用 `st --yes backup create`；数据库导出仅交互执行，避免 cron 误触。

---

## 10. 安全设计

| 风险 | 处理 |
|---|---|
| 误用 root 权限 | 变更操作前 `require_root`，打印影响范围并确认；自动化需 `--yes` |
| SSH 改配置锁死 | 修改前备份到 `data/backups/config/`；`sshd -t` 校验；重启失败提示回滚路径 |
| 改端口后失联 | **新增端口而非替换**，旧端口保留；提示新开终端验证 |
| 禁用密码登录 | 先检查存在非空 `authorized_keys`，否则拒绝执行 |
| 防火墙开启锁死 | 启用 UFW 前自动放行当前 SSH 端口 |
| 防火墙类型不兼容 | nftables/iptables 不静默持久化，提示安装 ufw |
| 备份恢复误覆盖 | 展示 manifest 与目标路径，要求输入 `RESTORE` |
| Docker 清理误删数据 | 分三步确认；数据卷清理单独确认并标注风险 |
| 应用插件不受控 | 插件为本地 shell，等同管理员权限；只从可信来源放入 `plugins/apps/` |
| 第三方脚本不受控 | 统一展示来源/风险、HTTPS 下载、不管道执行、支持 SHA256、缓存到数据目录 |
| 磁盘挂载误格式化 | 显示设备清单、拒绝系统盘、无文件系统时必须输入 `FORMAT`、写入 fstab 前备份 |
| sysctl 覆盖系统配置 | 写入独立 `99-sst-*.conf` 与 `limits.d`，不覆盖 `sysctl.conf`/`limits.conf`，支持一键还原 |
| 建站环境端口冲突 | 安装前检查 80/443；已有 `sst-web` 运行时跳过冲突检查；面板类应用在描述中标明端口 |
| 建站环境卸载误删 | 卸载必须输入 `REMOVE`；数据目录删除单独确认 |
| 面板/节点脚本风险 | 均为第三方脚本，执行前展示来源、风险等级并要求确认；节点/重装/NAT 标注高风险 |
| root 密码修改 | 密码通过 stdin 传给 `chpasswd`，不落日志、不出现在命令行参数 |
| 端口扫描滥用 | 执行前提示仅扫描有权限的主机；默认目标为本机公网 IP |

日志中不写入密码；MySQL 密码通过 `MYSQL_PWD` 传递，不出现在命令行参数。

---

## 11. 安装与验证

```bash
# 在仓库目录
sudo bash install.sh      # 部署到 /opt/ssh-tools，注册 st
st                        # 交互菜单
st --no-color version
```

安装后会解析 `st` 软链接，确保入口始终指向真实安装目录；`data/`、`config/`、`logs/` 权限为 700、属主 root。安装脚本最后会用 `st` 命令做入口自检。

静态检查（开发机）：

```bash
bash -n st.sh core/*.sh modules/*.sh apps/*/app.sh install.sh
bash tests/ui.sh
bash tests/scripts.sh
bash tests/ai.sh
# 可选：shellcheck -x st.sh core/*.sh modules/*.sh
```

`tests/init_hardening.sh` 会临时修改 sysctl 与 BBR 配置，需要 root 运行，退出时自动恢复现场。

只读验证（无需 Docker/防火墙）：

```bash
st version
st system info
st system cron list
st network ip
st app list
st tune status
st site status
st components list
st bench scripts    # 进入第三方测试清单后选 0 返回
st help
```

真实功能验证建议在测试 VPS 上按“只读 → 系统优化/磁盘 → Docker → 建站环境 → 安全 → 备份 → 第三方脚本”的顺序进行，SSH 变更需保留两个会话。

---

## 12. 后续迭代

1. **建站扩展**：Discuz、Typecho、Halo、可道云、发卡站等 CMS 一键部署，多 PHP 版本与站点隔离。
2. **脚本市场校验**：逐步为常用脚本补充固定 SHA256 或版本化镜像，减少上游变更风险。
3. **应用市场扩容**：Emby、OnlyOffice、RocketChat、Poste.io、Zentao 等更多 Docker 面板。
4. **迁移能力**：rclone 远端存储、整机迁移、恢复演练（dry-run）。
5. **可观测性**：定时体检报告、异常告警（邮件/Telegram/Webhook）。
6. **安全增强**：防火墙规则持久化抽象（nftables）、SSH 配置差异预览。
7. **分发方式**：`curl | bash` 在线安装、版本检查与增量更新、签名校验。
8. **可选 Web 面板**：复用模块函数，前端只做参数拼装与输出渲染。

---

## 13. 开荒向导

新 VPS / 新服务器初始化向导，入口为 `st init`，主菜单第一项。

### 13.1 当前实现

| 步骤 | 内容 |
|---|---|
| 预检 | 系统、CPU/内存/磁盘、SWAP、公网 IP、SSH 端口与登录策略、防火墙、Docker、BBR、密钥状态 |
| 磁盘 | 只读扫描设备/分区/文件系统/UUID/SSD-HDD/系统盘链路；协助挂载已有文件系统 |
| 基础信息 | 时区、主机名、时间同步、DNS、更新策略 |
| 账户 | root 密码、管理用户 + sudo + 密钥 |
| SSH | 新增非 22 端口并保留旧端口、密码登录、root 登录、10 分钟自动回滚 |
| 防火墙 | UFW/firewalld、放行全部 SSH 端口、可选 80/443、Fail2ban |
| 系统加固 | 安全 sysctl、可选严格 rp_filter、SWAP、BBR |
| 报告 | 进度写入 `data/init/state.conf`，报告写入 `data/init/report-*.md`（600 权限） |

命令：

```bash
st init
st init preflight
st init disk [scan]
st init basics
st init accounts
st init ssh [keep|rollback|status]
st init firewall
st init hardening
st init status
st init report
st init reset
```

磁盘安全约定：

- 不提供格式化，只在已有文件系统上挂载
- 拒绝系统盘、swap、LVM、RAID、LUKS
- 自动备份 `/etc/fstab`，使用 UUID + `nofail`
- 挂载失败自动恢复 fstab 并卸载

### 13.2 安全默认与 SSH 回滚

- SSH 改端口：新增随机高位端口并保留旧端口，验证通过后再决定清理
- 禁用密码登录前检查可用 `authorized_keys`
- 禁止 root SSH 前必须验证管理用户密钥与 sudo
- 防火墙启用前放行全部 SSH 端口，默认只开 SSH，80/443 按需选择
- SSH 变更默认启用 10 分钟自动回滚：
  - 变更前备份 `/etc/ssh/sshd_config` 与 `sshd_config.d`
  - `systemd-run` 创建一次性定时器
  - `st init ssh keep` 取消定时器并确认保留
  - `st init ssh rollback` 立即恢复备份
  - 超时未确认则自动恢复并重启 sshd
- 自动安全更新由用户选择，不默认开启
- 支持范围：Debian/Ubuntu、RHEL/Fedora/Rocky/Alma、Alpine 尽量覆盖；不再支持 CentOS

### 13.3 系统加固

- 安全 sysctl 写入 `/etc/sysctl.d/99-stbox-security.conf`，启用后可用 `4) 移除`
- 默认项：syncookies、禁 ICMP 重定向/源路由、忽略广播 ICMP、记录 martians、硬链接/软链接保护
- 可选严格 `rp_filter`，会提示 VPN/多网卡/非对称路由风险
- SWAP 创建独立 `/swapfile`，大小可选 1G/2G/4G/自定义，写入 fstab 与 swappiness
- btrfs/ZFS 根分区不自动创建 SWAP
- BBR 可选启用/关闭，写入独立 sysctl 文件
- 非 systemd 系统（Alpine）生成 `/etc/local.d` 启动脚本加载 sysctl

### 13.4 后续

- 真实 RHEL/Alpine 服务器上的 SSH、防火墙与用户路径验证
- 失败场景的更多自动化测试（端口冲突、sshd 校验失败、防火墙失败）
- 站点/应用与开荒向导之间的联动
