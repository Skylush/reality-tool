# Reality Tool 项目文档

## 1. 项目概述

`reality_tool.sh` 是从原 `ssh_tool.sh` 中的「节点搭建合集 -> 老王Reality一键脚本」提取出的独立 Reality 管理脚本。

脚本目标是提供一个可直接远程调用的一键工具，用于 Reality 节点安装、卸载、端口变更、节点链接查询、实时客户端流量监控，以及按日期记录历史客户端流量。

目标调用方式：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/<你的用户名>/<仓库名>/main/reality_tool.sh)
```

## 2. PRD（产品需求）

### 2.1 产品目标

提供一个面向 VPS 用户的 Reality 节点管理脚本，用户无需进入复杂配置文件，即可完成安装、管理、查询和监控。

### 2.2 目标用户

- 需要快速搭建 Reality 节点的 VPS 用户
- 需要查看当前客户端连接情况的节点维护者
- 需要按日期统计客户端使用流量的节点管理员
- 需要通过 GitHub 托管脚本并一行命令远程调用的使用者

### 2.3 核心需求

| 编号 | 需求 | 说明 |
|---|---|---|
| PRD-01 | 安装 Reality | 支持随机端口或用户指定端口安装 |
| PRD-02 | 卸载 Reality | 清理 Xray/Reality 服务、进程、配置、统计规则和历史记录 |
| PRD-03 | 更换端口 | 修改当前 Reality 配置端口并重启服务 |
| PRD-04 | 查询节点链接 | 从当前配置生成最新 `vless://` Reality 链接 |
| PRD-05 | 实时监控 | 类似 `top` 的实时页面，展示在线客户端、流量和速度 |
| PRD-06 | 历史统计 | 按日期记录连接过的客户端流量 |
| PRD-07 | GitHub 托管 | 可通过 raw.githubusercontent.com 远程执行 |

## 3. FRD / RD（功能 / 研发设计）

### 3.1 菜单设计

```text
1. 安装Reality
2. 卸载Reality
3. 更换Reality端口
4. 查询Reality节点链接
5. 查看流量/连接/客户端归属地
6. 查看历史客户端流量（日统计）
0. 退出
```

### 3.2 功能说明

#### 1. 安装 Reality

- 检查端口是否占用
- 用户不输入端口时随机生成端口
- Alpine 使用容器/轻量分支脚本
- 常规 Linux 使用 Xray Reality 安装脚本

#### 2. 卸载 Reality

卸载时需要清理：

- Xray / Reality 进程
- systemd 服务
- Reality 配置文件
- Xray 日志和数据目录
- Alpine 下 `/root/app`
- 实时统计创建的 `iptables` / `ip6tables` 链
- 历史统计目录 `/var/lib/reality_tool`
- 临时文件 `/tmp/reality_traffic.*`、`/tmp/reality_history.*`

#### 3. 更换 Reality 端口

- 从当前配置读取配置文件路径
- 使用 `jq` 修改 `.inbounds[0].port`
- 重启 Xray 或 Alpine 下的 web 进程

#### 4. 查询 Reality 节点链接

- 读取当前配置文件
- 从 private key 推导 public key
- 自动获取服务器 IP
- 生成最新 `vless://` 节点链接
- 如果存在 `qrencode`，显示二维码

#### 5. 实时监控

展示内容：

```text
CLIENT        LOCATION        TOTAL        UP/s        DOWN/s
```

说明：

- `CLIENT`：当前连接客户端 IP
- `LOCATION`：客户端归属地
- `TOTAL`：从统计规则创建后累计流量
- `UP/s`：客户端上传到节点的实时速度
- `DOWN/s`：节点下发到客户端的实时速度

交互：

- 每 2 秒刷新一次
- 按 `q` 返回菜单
- 使用差分刷新，只更新变化行，减少整屏闪烁

#### 6. 历史客户端流量

历史文件位置：

```text
/var/lib/reality_tool/history-YYYY-MM-DD.tsv
/var/lib/reality_tool/counters.tsv
```

统计口径：

- 实时监控页运行时记录
- 每轮刷新写入本轮新增流量
- 按日期分配到当天历史文件
- 没有进入实时监控页时，脚本不会后台记录

## 4. TRD（技术细化）

### 4.1 主要文件

| 文件 | 说明 |
|---|---|
| `reality_tool.sh` | 主脚本 |
| `ssh_tool.sh` | 原始远程脚本备份 |
| `PROJECT.md` | 项目说明文档 |

### 4.2 配置文件路径

| 系统 | 配置路径 |
|---|---|
| 常规 Linux | `/usr/local/etc/xray/config.json` |
| Alpine | `/root/app/config.json` |

### 4.3 连接识别逻辑

使用 `ss` 查看当前已建立连接：

```bash
ss -Htan state established
```

按 Reality 当前监听端口匹配本地地址列，再提取客户端 IP。

### 4.4 每客户端流量统计

使用 `iptables` / `ip6tables` 创建统计链：

```text
REALITY_IN
REALITY_OUT
```

流量方向：

| 方向 | 含义 |
|---|---|
| `REALITY_IN` | 客户端上传到节点 |
| `REALITY_OUT` | 节点下发到客户端 |

### 4.5 实时速度计算

每轮保存上一轮计数：

```text
当前字节数 - 上轮字节数 = 本轮新增字节数
本轮新增字节数 / 时间间隔 = 实时速度
```

### 4.6 历史统计写入逻辑

每个 IP 的当前累计值会和 `/var/lib/reality_tool/counters.tsv` 中的上次值比较。

只把增量写入当天文件：

```text
/var/lib/reality_tool/history-YYYY-MM-DD.tsv
```

## 5. 开发实现

### 5.1 本地运行

```bash
sudo bash reality_tool.sh
```

### 5.2 语法检查

```bash
bash -n reality_tool.sh
```

### 5.3 给脚本执行权限

```bash
chmod +x reality_tool.sh
```

## 6. 托管到 GitHub

### 6.1 新建 GitHub 仓库

在 GitHub 创建一个公开仓库，例如：

```text
reality-tool
```

建议公开仓库，因为远程一行命令调用 raw 文件更方便。

### 6.2 初始化本地 Git

在当前项目目录执行：

```bash
git init
git add reality_tool.sh PROJECT.md
git commit -m "Initial Reality tool script"
```

### 6.3 绑定远程仓库

把下面的用户名和仓库名替换成你自己的：

```bash
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

### 6.4 远程调用脚本

GitHub Raw 地址格式：

```text
https://raw.githubusercontent.com/<你的用户名>/<仓库名>/main/reality_tool.sh
```

最终调用命令：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/<你的用户名>/<仓库名>/main/reality_tool.sh)
```

示例：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/yourname/reality-tool/main/reality_tool.sh)
```

## 7. 发布建议

### 7.1 README 调用说明

仓库首页建议放一个 `README.md`，最少包含：

````markdown
# Reality Tool

一键 Reality 管理脚本。

## 使用

```bash
bash <(curl -Ls https://raw.githubusercontent.com/<你的用户名>/<仓库名>/main/reality_tool.sh)
```
````

### 7.2 版本管理

如果后续要稳定发布，可以打 tag：

```bash
git tag v1.0.0
git push origin v1.0.0
```

指定版本调用：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/<你的用户名>/<仓库名>/v1.0.0/reality_tool.sh)
```

### 7.3 注意事项

- 脚本需要 root 权限运行
- 远程调用建议使用公开仓库
- 历史流量只有进入实时监控页后才开始记录
- 如果清空防火墙规则，客户端累计流量会重新开始
- 执行卸载会删除 Reality 相关服务、统计规则和历史数据
