#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 执行"
  exit 1
fi

echo "[1/2] 配置 IPv6 DNS"

if [ ! -e /etc/resolv.conf.bak ]; then
  cp /etc/resolv.conf /etc/resolv.conf.bak
fi

printf '%s\n' \
'nameserver 2a00:1098:2b::1' \
'nameserver 2a01:4f9:c010:3f02::1' \
'nameserver 2a01:4f8:c2c:123f::1' \
'nameserver 2a00:1098:2c::1' \
> /etc/resolv.conf

cat /etc/resolv.conf

echo "[2/2] 安装 Komari Agent"

stty sane </dev/tty
printf '请输入新的 Agent Token: '
stty -echo </dev/tty
IFS= read -r KOMARI_TOKEN </dev/tty
stty echo </dev/tty
printf '\n'

curl -6 -fsSL \
  https://raw.githubusercontent.com/komari-monitor/komari-agent/refs/heads/main/install.sh \
| sed 's/[[:space:]]curl / curl -6 /g' \
| sh -s -- \
  --install-version 1.2.13 \
  --install-service-name komari-agent \
  --install-no-mirror \
  -e 'https://komari.ysoo.de' \
  -t "$KOMARI_TOKEN" \
  --disable-auto-update \
  --month-rotate 1

unset KOMARI_TOKEN

echo
echo "安装完成，服务状态："
rc-service komari-agent status
