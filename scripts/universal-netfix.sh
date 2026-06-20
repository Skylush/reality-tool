#!/usr/bin/env bash
set -u

# Universal Linux DNS/network quick repair script for common IDC VPS images.
# Default behavior: detect network/DNS state, repair DNS resolver configuration,
# then retest. It does not replace package manager repositories.

LOG="/root/netfix-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="/root/netfix-backup-$(date +%Y%m%d-%H%M%S)"
DNS_SERVERS="${DNS_SERVERS:-1.1.1.1 8.8.8.8 9.9.9.9 208.67.222.222}"
TEST_DOMAINS="${TEST_DOMAINS:-google.com ip.sb deb.debian.org security.debian.org github.com raw.githubusercontent.com}"
DRY_RUN=0
FORCE=0

usage() {
  cat <<EOF
Usage: bash $0 [--dry-run] [--force] [--dns "1.1.1.1 8.8.8.8"]

Environment:
  DNS_SERVERS="1.1.1.1 8.8.8.8 9.9.9.9"  Override DNS servers.
  TEST_DOMAINS="google.com ip.sb github.com"       Override test domains.

Examples:
  bash $0
  bash $0 --dry-run
  bash $0 --force
  DNS_SERVERS="8.8.8.8 1.1.1.1" bash $0
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --dns) shift; DNS_SERVERS="${1:-$DNS_SERVERS}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
  shift
done

exec > >(tee -a "$LOG") 2>&1

section() {
  echo
  echo "========== $* =========="
}

run() {
  echo "+ $*"
  if [ "$DRY_RUN" -eq 0 ]; then
    "$@"
  fi
}

run_sh() {
  echo "+ $*"
  if [ "$DRY_RUN" -eq 0 ]; then
    sh -c "$*"
  fi
}

have() {
  command -v "$1" >/dev/null 2>&1
}

is_active() {
  have systemctl && systemctl is-active --quiet "$1" 2>/dev/null
}

backup_file() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  mkdir -p "$BACKUP_DIR"
  cp -a "$1" "$BACKUP_DIR/" 2>/dev/null || true
}

detect_os() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
    OS_NAME="${PRETTY_NAME:-unknown}"
  else
    OS_ID="unknown"
    OS_LIKE=""
    OS_NAME="unknown"
  fi
}

raw_ip_ok() {
  for ip in 1.1.1.1 8.8.8.8 9.9.9.9; do
    if ping -4 -c 1 -W 2 "$ip" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

dns_ok() {
  for host in google.com ip.sb deb.debian.org github.com; do
    if getent hosts "$host" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

resolved_manages_resolv_conf() {
  [ -L /etc/resolv.conf ] || return 1
  readlink -f /etc/resolv.conf 2>/dev/null | grep -q '^/run/systemd/resolve/'
}

resolved_has_uplink_dns() {
  have resolvectl || return 1
  resolvectl dns 2>/dev/null | grep -Eq '([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-fA-F]{0,4}:[0-9a-fA-F:]+'
}

resolved_needs_persistent_fix() {
  is_active systemd-resolved || return 1
  resolved_manages_resolv_conf || return 1
  resolved_has_uplink_dns && return 1
  return 0
}

show_basic_info() {
  section "BASIC"
  date -Is
  hostname 2>/dev/null || true
  whoami 2>/dev/null || true
  uname -a
  echo "$OS_NAME"

  section "IP / ROUTE"
  ip -br addr 2>/dev/null || ifconfig -a 2>/dev/null || true
  echo
  ip route 2>/dev/null || route -n 2>/dev/null || true
  echo
  ip -6 route 2>/dev/null || true

  section "DNS CONFIG"
  ls -l /etc/resolv.conf 2>/dev/null || true
  echo "--- /etc/resolv.conf ---"
  cat /etc/resolv.conf 2>/dev/null || true
  echo
  echo "--- systemd-resolved ---"
  if have systemctl; then
    systemctl is-active systemd-resolved 2>/dev/null || true
  fi
  resolvectl status 2>/dev/null || systemd-resolve --status 2>/dev/null || true
  echo
  echo "--- NetworkManager ---"
  if have systemctl; then
    systemctl is-active NetworkManager 2>/dev/null || true
  fi
  nmcli dev show 2>/dev/null | sed -n '1,120p' || true
}

show_tests() {
  section "CONNECTIVITY: RAW IP"
  for ip in 1.1.1.1 8.8.8.8 9.9.9.9 208.67.222.222; do
    echo "--- ping $ip ---"
    ping -4 -c 2 -W 2 "$ip" || true
  done

  section "CONNECTIVITY: DNS"
  for host in $TEST_DOMAINS; do
    echo "--- getent $host ---"
    getent hosts "$host" || true
    if have nslookup; then
      echo "--- nslookup $host ---"
      nslookup "$host" 2>&1 || true
    fi
    echo "--- ping $host ---"
    ping -4 -c 1 -W 2 "$host" || true
  done

  section "CURL TESTS"
  if have curl; then
    for url in https://ip.sb https://google.com https://deb.debian.org https://github.com; do
      echo "--- curl $url ---"
      curl -4 -I -L --connect-timeout 8 -m 20 "$url" 2>&1 | sed -n '1,25p' || true
    done
  else
    echo "curl not installed"
  fi

  section "PACKAGE MANAGER TEST"
  if have apt-get; then
    apt-get update -o Acquire::http::Timeout=8 -o Acquire::https::Timeout=8 -o Acquire::Retries=0 2>&1 | sed -n '1,120p' || true
  elif have dnf; then
    dnf -y makecache --setopt=timeout=8 2>&1 | sed -n '1,120p' || true
  elif have yum; then
    yum -y makecache --setopt=timeout=8 2>&1 | sed -n '1,120p' || true
  elif have zypper; then
    zypper --non-interactive refresh 2>&1 | sed -n '1,120p' || true
  else
    echo "No supported package manager found"
  fi

  section "FIREWALL / PROXY"
  env | grep -Ei '^(http_proxy|https_proxy|all_proxy|no_proxy)=' || true
  iptables -S 2>/dev/null | sed -n '1,120p' || true
  nft list ruleset 2>/dev/null | sed -n '1,160p' || true
}

fix_with_resolved() {
  section "FIX: systemd-resolved"
  backup_file /etc/systemd/resolved.conf
  mkdir -p /etc/systemd/resolved.conf.d
  backup_file /etc/systemd/resolved.conf.d/99-netfix-dns.conf

  if [ "$DRY_RUN" -eq 0 ]; then
    {
      echo "[Resolve]"
      echo "DNS=$DNS_SERVERS"
      echo "FallbackDNS=$DNS_SERVERS"
      echo "DNSSEC=no"
    } > /etc/systemd/resolved.conf.d/99-netfix-dns.conf
  else
    echo "Would write /etc/systemd/resolved.conf.d/99-netfix-dns.conf"
  fi

  run systemctl enable systemd-resolved
  run systemctl restart systemd-resolved

  backup_file /etc/resolv.conf
  run rm -f /etc/resolv.conf
  if [ -e /run/systemd/resolve/resolv.conf ]; then
    run ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
  else
    run ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  fi

  resolvectl flush-caches 2>/dev/null || true
  if have ip; then
    for dev in $(ip -o link show | awk -F': ' '{print $2}' | grep -Ev '^(lo|docker|br-|veth|virbr|tun|tap)'); do
      resolvectl dns "$dev" $DNS_SERVERS 2>/dev/null || true
      resolvectl default-route "$dev" yes 2>/dev/null || true
    done
  fi
}

fix_with_networkmanager() {
  section "FIX: NetworkManager"
  [ "$DRY_RUN" -eq 0 ] && mkdir -p "$BACKUP_DIR"
  if have nmcli; then
    nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | while IFS=: read -r con dev; do
      [ -n "$con" ] || continue
      [ "$dev" = "lo" ] && continue
      echo "+ nmcli connection modify '$con' ipv4.dns '$DNS_SERVERS' ipv4.ignore-auto-dns yes"
      if [ "$DRY_RUN" -eq 0 ]; then
        nmcli connection modify "$con" ipv4.dns "$DNS_SERVERS" ipv4.ignore-auto-dns yes 2>/dev/null || true
        nmcli connection up "$con" 2>/dev/null || true
      fi
    done
    run systemctl restart NetworkManager
  fi
}

fix_static_resolv() {
  section "FIX: static /etc/resolv.conf"
  backup_file /etc/resolv.conf
  if [ "$DRY_RUN" -eq 0 ]; then
    rm -f /etc/resolv.conf
    {
      for dns in $DNS_SERVERS; do
        echo "nameserver $dns"
      done
      echo "options timeout:2 attempts:3 rotate"
    } > /etc/resolv.conf
  else
    echo "Would replace /etc/resolv.conf with static DNS servers: $DNS_SERVERS"
  fi
}

fix_dhcp_client_hooks() {
  section "FIX: DHCP client DNS override hooks"
  if [ -d /etc/dhcp/dhclient.conf ] || [ -f /etc/dhcp/dhclient.conf ]; then
    backup_file /etc/dhcp/dhclient.conf
    if [ "$DRY_RUN" -eq 0 ]; then
      sed -i '/^supersede domain-name-servers /d' /etc/dhcp/dhclient.conf 2>/dev/null || true
      echo "supersede domain-name-servers $(echo "$DNS_SERVERS" | sed 's/ /, /g');" >> /etc/dhcp/dhclient.conf
    else
      echo "Would add supersede domain-name-servers to /etc/dhcp/dhclient.conf"
    fi
  fi
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    exit 1
  fi

  detect_os
  section "START"
  echo "Log: $LOG"
  echo "Backup dir: $BACKUP_DIR"
  echo "OS: $OS_NAME"
  echo "DNS servers: $DNS_SERVERS"
  [ "$DRY_RUN" -eq 1 ] && echo "Mode: dry-run"
  [ "$FORCE" -eq 1 ] && echo "Mode: force repair"

  show_basic_info
  show_tests

  section "DIAGNOSIS"
  if raw_ip_ok; then
    echo "Raw IPv4 connectivity: OK"
  else
    echo "Raw IPv4 connectivity: FAILED"
    echo "DNS repair may not help. Check IDC security group, gateway, route, NIC, or upstream block."
  fi

  REPAIR_REASON=""
  if [ "$FORCE" -eq 1 ]; then
    REPAIR_REASON="force repair requested"
  elif ! dns_ok; then
    REPAIR_REASON="DNS resolution failed"
  elif resolved_needs_persistent_fix; then
    REPAIR_REASON="systemd-resolved is active but has no persistent upstream DNS"
  fi

  if [ -z "$REPAIR_REASON" ]; then
    echo "DNS resolution: OK"
    echo "Persistent DNS configuration: OK"
    echo "No DNS repair needed."
  else
    if dns_ok; then
      echo "DNS resolution: OK"
    else
      echo "DNS resolution: FAILED"
    fi
    echo "Applying DNS repair: $REPAIR_REASON"

    if have systemctl && { is_active systemd-resolved || systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; }; then
      fix_with_resolved
    elif is_active NetworkManager || have nmcli; then
      fix_with_networkmanager
      fix_static_resolv
    else
      fix_static_resolv
      fix_dhcp_client_hooks
    fi
  fi

  section "RETEST AFTER FIX"
  sleep 2
  show_basic_info
  show_tests

  section "RESULT"
  if dns_ok; then
    echo "DNS repair result: OK"
  else
    echo "DNS repair result: FAILED"
    echo "Next checks: IDC panel network status, security group outbound UDP/TCP 53, custom firewall, and provider DNS hijack/filtering."
  fi
  echo "Log saved to: $LOG"
  echo "Backup saved to: $BACKUP_DIR"
}

main "$@"
