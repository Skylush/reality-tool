# Reality Tool

一键 Reality 管理脚本，支持安装、卸载、换端口、查询节点链接、实时客户端流量监控和按日期历史统计。

## 使用

把 `<你的用户名>` 和 `<仓库名>` 换成 GitHub 上的实际信息：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/<你的用户名>/<仓库名>/main/reality_tool.sh)
```

示例：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/yourname/reality-tool/main/reality_tool.sh)
```

## 功能

- 安装 Reality
- 卸载 Reality
- 更换 Reality 端口
- 查询 Reality 节点链接
- 实时查看客户端 IP、归属地、累计流量、上下行速度
- 按日期查看历史客户端流量

## 注意

- 请使用 root 权限运行。
- 历史流量从进入实时监控页后开始记录。
- 执行卸载会删除 Reality 服务、统计规则和历史记录。

## 项目文档

完整 PRD / FRD / TRD / GitHub 托管说明见 [PROJECT.md](PROJECT.md)。
