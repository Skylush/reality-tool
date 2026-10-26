#!/bin/sh

# Alpine 3.18 -> 3.24 upgrade toolbox
# Designed for an existing Alpine system, including OpenVZ/LXC and IPv6-only VPS.
# It upgrades one stable branch at a time and does not overwrite network config.

set -u

BACKUP_ROOT="/root/alpine-upgrade-backups"
REPO_FILE="/etc/apk/repositories"
RESOLV_FILE="/etc/resolv.conf"

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "请使用 root 执行"
}

current_version() {
    [ -f /etc/alpine-release ] || die "当前系统不是 Alpine，找不到 /etc/alpine-release"
    cut -d. -f1-2 /etc/alpine-release
}

next_version() {
    case "$1" in
        3.18) echo 3.19 ;;
        3.19) echo 3.20 ;;
        3.20) echo 3.21 ;;
        3.21) echo 3.22 ;;
        3.22) echo 3.23 ;;
        3.23) echo 3.24 ;;
        3.24) echo done ;;
        *) echo unsupported ;;
    esac
}

backup_config() {
    version="$1"
    stamp="$(date +%Y%m%d-%H%M%S)"
    dir="${BACKUP_ROOT}/${version}-${stamp}"

    mkdir -p "$dir"
    cp -a "$REPO_FILE" "$dir/repositories"
    [ -e "$RESOLV_FILE" ] && cp -aL "$RESOLV_FILE" "$dir/resolv.conf"
    [ -e /etc/apk/world ] && cp -a /etc/apk/world "$dir/world"
    [ -e /etc/network/interfaces ] && cp -a /etc/network/interfaces "$dir/interfaces"

    echo "$dir" > "${BACKUP_ROOT}/latest"
    echo "[OK] 配置备份目录: $dir"
}

show_status() {
    version="$(current_version)"
    next="$(next_version "$version")"

    echo
    echo "当前 Alpine 版本: $version"
    echo "下一版本: $next"
    echo "系统架构: $(uname -m)"
    echo "虚拟化类型: $(command -v virt-what >/dev/null 2>&1 && virt-what || echo unknown)"
    echo
    echo "当前软件源:"
    cat "$REPO_FILE"
}

set_ipv6_dns() {
    echo "将备份当前 DNS 后写入 IPv6 DNS。"
    backup_config "dns"

    printf '%s\n' \
        'nameserver 2a00:1098:2b::1' \
        'nameserver 2a01:4f9:c010:3f02::1' \
        'nameserver 2a01:4f8:c2c:123f::1' \
        'nameserver 2a00:1098:2c::1' \
        > "$RESOLV_FILE"

    cat "$RESOLV_FILE"
}

upgrade_one() {
    current="$(current_version)"
    next="$(next_version "$current")"

    [ "$next" != done ] || {
        echo "已经是 Alpine 3.24，无需继续升级。"
        return 0
    }
    [ "$next" != unsupported ] || die "不支持从 Alpine $current 自动升级"

    echo
    echo "准备从 Alpine $current 升级到 Alpine $next"
    echo "此操作会升级系统软件包，建议通过 VPS 控制台或 screen 执行。"
    printf "确认继续？输入 yes: "
    read answer
    [ "$answer" = yes ] || {
        echo "已取消"
        return 0
    }

    backup_config "$current"

    cp -a "$REPO_FILE" "${REPO_FILE}.before-${next}"
    sed -i "s#/v${current}/#/v${next}/#g" "$REPO_FILE"

    if grep -q "/v${current}/" "$REPO_FILE"; then
        cp -a "${REPO_FILE}.before-${next}" "$REPO_FILE"
        die "没有成功切换软件源到 v${next}"
    fi

    echo "[1/2] 更新软件源索引..."
    if ! apk update; then
        cp -a "${REPO_FILE}.before-${next}" "$REPO_FILE"
        die "apk update 失败，已恢复原软件源"
    fi

    echo "[2/2] 升级系统软件包..."
    if ! apk upgrade --available; then
        echo "[ERROR] apk upgrade 失败。软件源已切换到 v${next}，请先检查错误后再处理。"
        exit 1
    fi

    echo
    echo "[OK] 软件包已从 $current 升级到 $next"
    echo "当前版本: $(current_version)"

    # Alpine 3.21+ 的 OpenSSH 升级后必须重启 sshd。
    if command -v rc-service >/dev/null 2>&1 && [ -x /etc/init.d/sshd ]; then
        rc-service sshd restart || echo "[WARN] sshd 重启失败，请从控制台检查"
    fi

    echo
    echo "建议现在重启系统："
    echo "  sync && reboot"
    echo "重启后重新运行本工具箱，继续下一个版本。"
}

upgrade_all() {
    while :; do
        current="$(current_version)"
        next="$(next_version "$current")"

        [ "$next" != done ] || {
            echo "已经升级到 Alpine 3.24。"
            break
        }
        [ "$next" != unsupported ] || die "不支持从 Alpine $current 自动升级"

        upgrade_one
        echo
        echo "升级步骤完成。请重启后再次运行工具箱，避免连续升级后服务状态不一致。"
        break
    done
}

main_menu() {
    while :; do
        echo
        echo "========================================"
        echo " Alpine 3.18 -> 3.24 升级工具箱"
        echo "========================================"
        echo "1. 查看当前版本和软件源"
        echo "2. 配置 IPv6 DNS"
        echo "3. 升级到下一个 Alpine 大版本"
        echo "4. 自动执行一个升级步骤"
        echo "0. 退出"
        echo "========================================"
        printf "请选择: "
        read choice

        case "$choice" in
            1) show_status ;;
            2) set_ipv6_dns ;;
            3) upgrade_one ;;
            4) upgrade_all ;;
            0) exit 0 ;;
            *) echo "无效选项" ;;
        esac
    done
}

require_root
mkdir -p "$BACKUP_ROOT"
main_menu
