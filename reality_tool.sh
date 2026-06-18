#!/bin/bash
export LANG=en_US.UTF-8

re='\e[0m'
red='\e[1;91m'
green='\e[1;32m'
yellow='\e[1;33m'
purple='\e[1;35m'
skyblue='\e[1;96m'
state_dir="/var/lib/reality_tool"

[[ $EUID -ne 0 ]] && echo -e "${red}注意: 请在root用户下运行脚本${re}" && sleep 1 && exit 1

install() {
    if [ $# -eq 0 ]; then
        echo -e "${red}未提供软件包参数!${re}"
        return 1
    fi

    for package in "$@"; do
        if command -v "$package" &>/dev/null; then
            continue
        fi

        echo -e "${yellow}正在安装 ${package}...${re}"
        if command -v apt &>/dev/null; then
            DEBIAN_FRONTEND=noninteractive apt install -y "$package"
        elif command -v dnf &>/dev/null; then
            dnf install -y "$package"
        elif command -v yum &>/dev/null; then
            yum install -y "$package"
        elif command -v apk &>/dev/null; then
            apk add "$package"
        else
            echo -e "${red}暂不支持你的系统!${re}"
            return 1
        fi
    done
}

break_end() {
    echo -e "${green}执行完成${re}"
    echo -e "${yellow}按任意键返回...${re}"
    read -n 1 -s -r -p ""
    echo ""
    clear
}

get_ip() {
    local server_ip
    server_ip=$(curl -s --max-time 3 ipv4.ip.sb 2>/dev/null)
    if [[ -z "$server_ip" ]]; then
        server_ip=$(curl -s --max-time 3 ipv6.ip.sb 2>/dev/null)
        [[ -n "$server_ip" ]] && server_ip="[$server_ip]"
    fi
    if [[ -z "$server_ip" ]]; then
        server_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    fi
    if [[ -z "$server_ip" ]]; then
        server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    echo "$server_ip"
}

get_isp() {
    local isp
    isp=$(curl -sm 3 -H "User-Agent: Mozilla/5.0" "https://api.ip.sb/geoip" | tr -d '\n' | awk -F\" '{c="";i="";for(x=1;x<=NF;x++){if($x=="country_code")c=$(x+2);if($x=="isp")i=$(x+2)};if(c&&i)print c"-"i}' | sed 's/ /_/g')
    [[ -z "$isp" ]] && isp=$(curl -sm 3 "https://speed.cloudflare.com/meta" | awk -F\" '{print $26"-"$18}' | sed 's/ /_/g')
    [[ -z "$isp" ]] && isp="Reality"
    echo "$isp"
}

human_bytes() {
    local bytes="$1"
    awk -v b="$bytes" 'BEGIN {
        split("B KB MB GB TB PB", unit, " ");
        i = 1;
        while (b >= 1024 && i < 6) {
            b = b / 1024;
            i++;
        }
        if (i == 1) {
            printf "%d %s", b, unit[i];
        } else {
            printf "%.2f %s", b, unit[i];
        }
    }'
}

term_cols() {
    local cols
    cols=$(tput cols 2>/dev/null)
    [[ -z "$cols" ]] && cols=80
    echo "$cols"
}

repeat_char() {
    local char="$1"
    local count="$2"
    awk -v c="$char" -v n="$count" 'BEGIN {for (i=0; i<n; i++) printf c}'
}

fit_text() {
    local text="$1"
    local width="$2"
    awk -v s="$text" -v w="$width" 'BEGIN {
        if (w <= 0) {
            print "";
        } else if (length(s) > w) {
            print substr(s, 1, w - 1) ".";
        } else {
            print s;
        }
    }'
}

render_diff_frame() {
    local frame="$1"
    local cols="$2"
    local i line old max_lines

    mapfile -t new_frame <<< "$frame"
    max_lines=${#new_frame[@]}
    [[ ${#old_frame[@]} -gt $max_lines ]] && max_lines=${#old_frame[@]}

    for ((i = 0; i < max_lines; i++)); do
        line="${new_frame[$i]}"
        old="${old_frame[$i]}"
        if [[ "$line" != "$old" ]]; then
            tput cup "$i" 0 2>/dev/null || true
            printf "%b" "$line"
            printf "\033[K"
        fi
    done

    old_frame=("${new_frame[@]}")
}

traffic_values() {
    local iface rx tx
    iface=$(default_interface)
    if [[ -z "$iface" || ! -r /proc/net/dev ]]; then
        echo "unknown 0 0"
        return
    fi

    rx=$(awk -F'[: ]+' -v dev="$iface" '$2 == dev {print $3}' /proc/net/dev)
    tx=$(awk -F'[: ]+' -v dev="$iface" '$2 == dev {print $11}' /proc/net/dev)
    echo "$iface ${rx:-0} ${tx:-0}"
}

ensure_state_dir() {
    mkdir -p "$state_dir"
}

state_file() {
    echo "$state_dir/counters.tsv"
}

history_file() {
    local day="${1:-$(date +%F)}"
    echo "$state_dir/history-${day}.tsv"
}

safe_field() {
    echo "$1" | tr '\t' ' ' | tr -d '\r\n'
}

default_interface() {
    local iface
    iface=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
    [[ -z "$iface" ]] && iface=$(awk -F: 'NR > 2 && $1 !~ /lo/ {gsub(/ /, "", $1); print $1; exit}' /proc/net/dev 2>/dev/null)
    echo "$iface"
}

show_traffic_stats() {
    local iface rx tx
    iface=$(default_interface)

    if [[ -z "$iface" || ! -r /proc/net/dev ]]; then
        echo -e "${red}无法读取网卡流量统计。${re}"
        return
    fi

    rx=$(awk -F'[: ]+' -v dev="$iface" '$2 == dev {print $3}' /proc/net/dev)
    tx=$(awk -F'[: ]+' -v dev="$iface" '$2 == dev {print $11}' /proc/net/dev)

    echo -e "${green}流量统计（网卡累计，系统启动后）:${re}"
    echo -e "网卡: ${yellow}${iface}${re}"
    echo -e "接收: ${yellow}$(human_bytes "${rx:-0}")${re}"
    echo -e "发送: ${yellow}$(human_bytes "${tx:-0}")${re}"
}

reality_port() {
    local config
    config=$(config_path)
    [[ ! -f "$config" ]] && return 1
    jq -r '.inbounds[0].port // empty' "$config"
}

normalize_remote_ip() {
    local remote="$1"

    if [[ "$remote" == \[*\]:* ]]; then
        remote=${remote#\[}
        remote=${remote%\]:*}
    elif [[ "$remote" == *:* && "$remote" != *::* ]]; then
        remote=${remote%:*}
    fi

    if [[ "$remote" == ::ffff:* ]]; then
        remote=${remote#::ffff:}
    fi

    echo "$remote"
}

client_ips_by_port() {
    local port="$1"
    ss -Htan state established 2>/dev/null | awk -v port="$port" '
        {
            local_addr = $3
            if (local_addr ~ ":" port "$") {
                print $4
            }
        }
    ' | while read -r remote; do
        normalize_remote_ip "$remote"
    done | sed '/^$/d' | sort -u
}

firewall_cmd_for_ip() {
    local ip="$1"
    if [[ "$ip" == *:* ]]; then
        command -v ip6tables 2>/dev/null
    else
        command -v iptables 2>/dev/null
    fi
}

ensure_firewall_tool() {
    if command -v iptables &>/dev/null; then
        return 0
    fi

    install iptables
    command -v iptables &>/dev/null
}

ensure_traffic_chain() {
    local port="$1"
    local cmd="$2"
    local in_chain="REALITY_IN"
    local out_chain="REALITY_OUT"

    "$cmd" -N "$in_chain" 2>/dev/null || true
    "$cmd" -N "$out_chain" 2>/dev/null || true

    "$cmd" -C INPUT -p tcp --dport "$port" -j "$in_chain" 2>/dev/null || "$cmd" -I INPUT -p tcp --dport "$port" -j "$in_chain"
    "$cmd" -C OUTPUT -p tcp --sport "$port" -j "$out_chain" 2>/dev/null || "$cmd" -I OUTPUT -p tcp --sport "$port" -j "$out_chain"
}

cleanup_traffic_chains() {
    local cmd port

    for cmd in iptables ip6tables; do
        command -v "$cmd" &>/dev/null || continue

        for port in $(reality_port 2>/dev/null); do
            [[ -z "$port" ]] && continue
            while "$cmd" -C INPUT -p tcp --dport "$port" -j REALITY_IN 2>/dev/null; do
                "$cmd" -D INPUT -p tcp --dport "$port" -j REALITY_IN 2>/dev/null || break
            done
            while "$cmd" -C OUTPUT -p tcp --sport "$port" -j REALITY_OUT 2>/dev/null; do
                "$cmd" -D OUTPUT -p tcp --sport "$port" -j REALITY_OUT 2>/dev/null || break
            done
        done

        "$cmd" -S INPUT 2>/dev/null | awk '/-j REALITY_IN/ {sub(/^-A/, "-D"); print}' | while read -r rule; do
            "$cmd" $rule 2>/dev/null || true
        done
        "$cmd" -S OUTPUT 2>/dev/null | awk '/-j REALITY_OUT/ {sub(/^-A/, "-D"); print}' | while read -r rule; do
            "$cmd" $rule 2>/dev/null || true
        done

        "$cmd" -F REALITY_IN 2>/dev/null || true
        "$cmd" -F REALITY_OUT 2>/dev/null || true
        "$cmd" -X REALITY_IN 2>/dev/null || true
        "$cmd" -X REALITY_OUT 2>/dev/null || true
    done

    rm -f /tmp/reality_traffic.*
    rm -f /tmp/reality_history.*
}

ensure_client_counter() {
    local port="$1"
    local ip="$2"
    local cmd

    cmd=$(firewall_cmd_for_ip "$ip")
    [[ -z "$cmd" ]] && return 1

    ensure_traffic_chain "$port" "$cmd"
    "$cmd" -C REALITY_IN -s "$ip" -p tcp --dport "$port" -j RETURN 2>/dev/null || "$cmd" -A REALITY_IN -s "$ip" -p tcp --dport "$port" -j RETURN
    "$cmd" -C REALITY_OUT -d "$ip" -p tcp --sport "$port" -j RETURN 2>/dev/null || "$cmd" -A REALITY_OUT -d "$ip" -p tcp --sport "$port" -j RETURN
}

counter_bytes() {
    local chain="$1"
    local ip="$2"
    local direction="$3"
    local cmd

    cmd=$(firewall_cmd_for_ip "$ip")
    [[ -z "$cmd" ]] && echo 0 && return

    if [[ "$direction" == "in" ]]; then
        "$cmd" -nvxL "$chain" 2>/dev/null | awk -v ip="$ip" '$8 == ip {print $2; found=1; exit} END {if (!found) print 0}'
    else
        "$cmd" -nvxL "$chain" 2>/dev/null | awk -v ip="$ip" '$9 == ip {print $2; found=1; exit} END {if (!found) print 0}'
    fi
}

record_client_history() {
    local ip="$1"
    local geo="$2"
    local up="$3"
    local down="$4"
    local now="$5"
    local state history tmp prev_up prev_down delta_up delta_down clean_geo

    ensure_state_dir
    state=$(state_file)
    history=$(history_file)
    tmp=$(mktemp /tmp/reality_history.XXXXXX)
    clean_geo=$(safe_field "$geo")

    touch "$state" "$history"

    read -r prev_up prev_down < <(awk -F'\t' -v ip="$ip" '$1 == ip {print $2, $3; found=1; exit} END {if (!found) print "0 0"}' "$state")

    if [[ "$up" -ge "$prev_up" ]]; then
        delta_up=$((up - prev_up))
    else
        delta_up=0
    fi

    if [[ "$down" -ge "$prev_down" ]]; then
        delta_down=$((down - prev_down))
    else
        delta_down=0
    fi

    awk -F'\t' -v OFS='\t' -v ip="$ip" -v up="$up" -v down="$down" -v ts="$now" '
        $1 == ip {
            print ip, up, down, ts;
            done=1;
            next;
        }
        {print}
        END {
            if (!done) print ip, up, down, ts;
        }
    ' "$state" > "$tmp" && mv "$tmp" "$state"

    if [[ "$delta_up" -eq 0 && "$delta_down" -eq 0 ]]; then
        return
    fi

    tmp=$(mktemp /tmp/reality_history.XXXXXX)
    awk -F'\t' -v OFS='\t' -v ip="$ip" -v geo="$clean_geo" -v du="$delta_up" -v dd="$delta_down" -v ts="$now" '
        $1 == ip {
            print ip, geo, ($3 + du), ($4 + dd), ts;
            done=1;
            next;
        }
        {print}
        END {
            if (!done) print ip, geo, du, dd, ts;
        }
    ' "$history" > "$tmp" && mv "$tmp" "$history"
}

is_private_ip() {
    local ip="$1"
    [[ "$ip" =~ ^10\. ]] && return 0
    [[ "$ip" =~ ^127\. ]] && return 0
    [[ "$ip" =~ ^192\.168\. ]] && return 0
    [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && return 0
    [[ "$ip" =~ ^169\.254\. ]] && return 0
    [[ "$ip" =~ ^::1$|^fc|^fd|^fe80: ]] && return 0
    return 1
}

geo_lookup() {
    local ip="$1"
    local data status country region city isp message

    if is_private_ip "$ip"; then
        echo "private/local"
        return
    fi

    data=$(curl -sm 5 "http://ip-api.com/json/${ip}?lang=en&fields=status,message,country,regionName,city,isp,query" 2>/dev/null)
    status=$(echo "$data" | jq -r '.status // empty' 2>/dev/null)

    if [[ "$status" != "success" ]]; then
        message=$(echo "$data" | jq -r '.message // "查询失败"' 2>/dev/null)
        echo "$message"
        return
    fi

    country=$(echo "$data" | jq -r '.country // ""' 2>/dev/null)
    region=$(echo "$data" | jq -r '.regionName // ""' 2>/dev/null)
    city=$(echo "$data" | jq -r '.city // ""' 2>/dev/null)
    isp=$(echo "$data" | jq -r '.isp // ""' 2>/dev/null)
    echo "${country} ${region} ${city} ${isp}" | sed 's/  */ /g; s/^ //; s/ $//'
}

show_reality_stats() {
    clear
    install jq curl
    command -v ss &>/dev/null || install iproute2

    local port clients total unique key interval now elapsed ip geo up down total_bytes up_speed down_speed
    local cols content_width line iface rx tx ip_w geo_w used_w up_w down_w fixed_w sep summary
    local frame row last_cols client_count
    port=$(reality_port)

    if [[ -z "$port" ]]; then
        echo -e "${red}未找到 Reality 配置或端口。${re}"
        echo -e "${yellow}请先安装 Reality。${re}"
        return
    fi

    if ! ensure_firewall_tool; then
        echo -e "${red}未找到 iptables，无法统计每个客户端的流量。${re}"
        return
    fi

    interval=2
    declare -A prev_up
    declare -A prev_down
    declare -A prev_time
    declare -A geo_cache
    declare -a old_frame

    tput civis 2>/dev/null || true
    tput smcup 2>/dev/null || true
    clear
    while true; do
        cols=$(term_cols)
        content_width=$((cols - 1))
        [[ $content_width -lt 40 ]] && content_width=40
        if [[ -n "$last_cols" && "$last_cols" -ne "$cols" ]]; then
            clear
            old_frame=()
        fi
        last_cols=$cols
        line=$(repeat_char "-" "$content_width")
        read -r iface rx tx <<< "$(traffic_values)"

        now=$(date +%s)
        total=$(ss -Htan state established 2>/dev/null | awk -v port="$port" '$3 ~ ":" port "$" {count++} END {print count+0}')
        clients=$(client_ips_by_port "$port")
        unique=$(echo "$clients" | sed '/^$/d' | wc -l | tr -d ' ')

        frame=""
        frame+="${green}Reality Monitor${re} ${skyblue}(q: return, refresh: ${interval}s)${re}"$'\n'
        summary="port $port | conn $total | clients $unique | iface $iface | rx $(human_bytes "$rx") | tx $(human_bytes "$tx")"
        frame+="${yellow}$(fit_text "$summary" "$content_width")${re}"$'\n'
        frame+="$line"$'\n\n'

        if [[ -z "$clients" ]]; then
            frame+="${yellow}No established clients.${re}"$'\n\n'
            frame+="${skyblue}Press q to return. Auto refresh every ${interval}s.${re}"
            render_diff_frame "$frame" "$cols"
            read -r -s -n 1 -t "$interval" key
            [[ "$key" == "q" || "$key" == "Q" ]] && break
            continue
        fi

        ip_w=16
        used_w=12
        up_w=12
        down_w=12
        fixed_w=$((ip_w + used_w + up_w + down_w + 8))
        geo_w=$((content_width - fixed_w))
        if [[ $geo_w -lt 14 ]]; then
            geo_w=14
            ip_w=15
            used_w=10
            up_w=10
            down_w=10
        fi
        sep=$(repeat_char "-" "$content_width")

        printf -v row "%-${ip_w}s  %-${geo_w}s  %${used_w}s  %${up_w}s  %${down_w}s" "CLIENT" "LOCATION" "TOTAL" "UP/s" "DOWN/s"
        frame+="$row"$'\n'
        frame+="$sep"$'\n'
        client_count=0

        while read -r ip; do
            [[ -z "$ip" ]] && continue
            client_count=$((client_count + 1))
            ensure_client_counter "$port" "$ip"

            up=$(counter_bytes REALITY_IN "$ip" in)
            down=$(counter_bytes REALITY_OUT "$ip" out)
            total_bytes=$((up + down))

            if [[ -n "${prev_time[$ip]}" ]]; then
                elapsed=$((now - prev_time[$ip]))
                [[ $elapsed -lt 1 ]] && elapsed=1
                up_speed=$(((up - prev_up[$ip]) / elapsed))
                down_speed=$(((down - prev_down[$ip]) / elapsed))
                [[ $up_speed -lt 0 ]] && up_speed=0
                [[ $down_speed -lt 0 ]] && down_speed=0
            else
                up_speed=0
                down_speed=0
            fi

            prev_up[$ip]=$up
            prev_down[$ip]=$down
            prev_time[$ip]=$now

            if [[ -z "${geo_cache[$ip]}" ]]; then
                geo_cache[$ip]=$(geo_lookup "$ip")
            fi
            geo=${geo_cache[$ip]}
            record_client_history "$ip" "$geo" "$up" "$down" "$now"

            printf -v row "%-${ip_w}s  %-${geo_w}s  %${used_w}s  %${up_w}s  %${down_w}s" \
                "$(fit_text "$ip" "$ip_w")" \
                "$(fit_text "$geo" "$geo_w")" \
                "$(fit_text "$(human_bytes "$total_bytes")" "$used_w")" \
                "$(fit_text "$(human_bytes "$up_speed")/s" "$up_w")" \
                "$(fit_text "$(human_bytes "$down_speed")/s" "$down_w")"
            frame+="$row"$'\n'
        done <<< "$clients"

        frame+=$'\n'
        frame+="$line"$'\n'
        frame+="${yellow}$(fit_text "TOTAL starts when counter rules are created. UP: client -> node, DOWN: node -> client." "$content_width")${re}"$'\n'
        frame+="${skyblue}Press q to return. Auto refresh every ${interval}s.${re}"
        render_diff_frame "$frame" "$cols"
        read -r -s -n 1 -t "$interval" key
        [[ "$key" == "q" || "$key" == "Q" ]] && break
    done

    tput rmcup 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    clear
}

show_history_stats() {
    clear
    ensure_state_dir

    local files file day has_data ip geo up down last total
    files=$(ls "$state_dir"/history-*.tsv 2>/dev/null)

    if [[ -z "$files" ]]; then
        echo -e "${yellow}暂无历史流量记录。${re}"
        echo -e "${yellow}进入菜单 5 后，脚本会开始按日期记录客户端流量。${re}"
        return
    fi

    echo -e "${green}Reality 历史客户端流量（日统计）${re}"
    echo ""

    for file in $files; do
        [[ -s "$file" ]] || continue
        day=$(basename "$file" | sed 's/^history-//; s/\.tsv$//')
        has_data=0

        while IFS=$'\t' read -r ip geo up down last; do
            [[ -z "$ip" ]] && continue
            if [[ "$has_data" -eq 0 ]]; then
                echo -e "${purple}${day}${re}"
                printf "%-18s  %-32s  %12s  %12s  %12s  %-19s\n" "CLIENT" "LOCATION" "UP" "DOWN" "TOTAL" "LAST_SEEN"
                printf "%-18s  %-32s  %12s  %12s  %12s  %-19s\n" "------" "--------" "--" "----" "-----" "---------"
                has_data=1
            fi

            total=$((up + down))
            printf "%-18s  %-32s  %12s  %12s  %12s  %-19s\n" \
                "$(fit_text "$ip" 18)" \
                "$(fit_text "$geo" 32)" \
                "$(human_bytes "$up")" \
                "$(human_bytes "$down")" \
                "$(human_bytes "$total")" \
                "$(date -d "@$last" "+%F %T" 2>/dev/null || date -r "$last" "+%F %T" 2>/dev/null || echo "$last")"
        done < "$file"

        [[ "$has_data" -eq 1 ]] && echo ""
    done

    echo -e "${yellow}说明: 历史流量从菜单 5 启动统计后开始记录，按当天增量写入。${re}"
}

config_path() {
    if [ -f "/etc/alpine-release" ]; then
        echo "/root/app/config.json"
    else
        echo "/usr/local/etc/xray/config.json"
    fi
}

xray_bin() {
    if [ -x "/usr/local/bin/xray" ]; then
        echo "/usr/local/bin/xray"
    elif [ -x "/root/app/web" ]; then
        echo "/root/app/web"
    else
        echo ""
    fi
}

public_key_from_private_key() {
    local private_key="$1"
    local bin
    bin=$(xray_bin)

    [[ -z "$bin" || -z "$private_key" ]] && return 1
    "$bin" x25519 -i "$private_key" 2>/dev/null | awk '/Password \(PublicKey\):|Public key:/ {print $NF; exit}'
}

query_reality_link() {
    clear
    install jq curl

    local config
    config=$(config_path)

    if [ ! -f "$config" ]; then
        echo -e "${red}未找到 Reality 配置文件: $config${re}"
        if [ -f "/root/app/list.txt" ]; then
            echo -e "${yellow}检测到历史节点文件，内容如下:${re}"
            cat /root/app/list.txt
        fi
        return
    fi

    local port uuid flow sni short_id private_key public_key ip isp url
    port=$(jq -r '.inbounds[0].port // empty' "$config")
    uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$config")
    flow=$(jq -r '.inbounds[0].settings.clients[0].flow // "xtls-rprx-vision"' "$config")
    sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$config")
    short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$config")
    private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$config")
    public_key=$(public_key_from_private_key "$private_key")

    if [[ -z "$port" || -z "$uuid" || -z "$sni" || -z "$short_id" || -z "$public_key" ]]; then
        echo -e "${red}配置文件字段不完整，无法生成节点链接。${re}"
        echo -e "${yellow}配置文件: $config${re}"
        return
    fi

    ip=$(get_ip)
    isp=$(get_isp)
    url="vless://${uuid}@${ip}:${port}?encryption=none&flow=${flow}&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${isp}"

    echo -e "${green}Reality 节点链接:${re}"
    echo ""
    echo -e "${green}${url}${re}"
    echo ""

    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 -m 2 -s 2 -o - "$url"
    else
        echo -e "${yellow}提示: 安装 qrencode 后可显示二维码。${re}"
    fi
}

install_reality() {
    clear
    install lsof
    clear

    local port
    read -p $'\033[1;35m请输入reality节点端口(nat小鸡请输入可用端口范围内的端口),回车跳过则使用随机端口：\033[0m' port
    [[ -z "$port" ]] && port=$(shuf -i 2000-65000 -n 1)

    until [[ -z $(lsof -i :"$port" 2>/dev/null) ]]; do
        echo -e "${red}${port}端口已经被其他程序占用，请更换端口重试${re}"
        read -p $'\033[1;35m设置 reality 端口[1-65535]（回车跳过将使用随机端口）：\033[0m' port
        [[ -z "$port" ]] && port=$(shuf -i 2000-65000 -n 1)
    done

    if [ -f "/etc/alpine-release" ]; then
        PORT=$port bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/test.sh)"
    else
        PORT=$port bash -c "$(curl -L https://raw.githubusercontent.com/eooce/xray-reality/master/reality.sh)"
    fi
}

uninstall_reality() {
    clear
    cleanup_traffic_chains

    if [ -f "/etc/alpine-release" ]; then
        pkill -f '/root/app/web'
        pkill -f '/root/app/npm'
        pkill -f '[w]eb -c .*config.json'
        pkill -f '[n]pm -s '
        rm -rf /root/app
    else
        systemctl disable --now xray 2>/dev/null
        systemctl stop xray 2>/dev/null
        pkill -f '/usr/local/bin/xray'
        rm -f /usr/local/bin/xray
        rm -f /etc/systemd/system/xray.service
        rm -f /etc/systemd/system/xray@.service
        rm -f /usr/local/etc/xray/config.json
        rm -f /usr/local/share/xray/geoip.dat
        rm -f /usr/local/share/xray/geosite.dat
        systemctl daemon-reload 2>/dev/null
        systemctl reset-failed xray 2>/dev/null
        rm -rf /usr/local/etc/xray
        rm -rf /usr/local/share/xray
        rm -rf /var/log/xray /var/lib/xray
    fi

    rm -rf "$state_dir"

    echo -e "${green}Reality及脚本统计相关进程/规则已卸载${re}"
}

change_reality_port() {
    clear
    install jq lsof

    local new_port config
    config=$(config_path)
    if [ ! -f "$config" ]; then
        echo -e "${red}未找到 Reality 配置文件: $config${re}"
        return
    fi

    read -p $'\033[1;35m设置 reality 端口[1-65535]（回车跳过将使用随机端口）：\033[0m' new_port
    [[ -z "$new_port" ]] && new_port=$(shuf -i 2000-65000 -n 1)

    until [[ -z $(lsof -i :"$new_port" 2>/dev/null) ]]; do
        echo -e "${red}${new_port}端口已经被其他程序占用，请更换端口重试${re}"
        read -p $'\033[1;35m设置reality端口[1-65535]（回车跳过将使用随机端口）：\033[0m' new_port
        [[ -z "$new_port" ]] && new_port=$(shuf -i 2000-65000 -n 1)
    done

    jq --argjson new_port "$new_port" '.inbounds[0].port = $new_port' "$config" > /tmp/reality_config.json && mv /tmp/reality_config.json "$config"

    if [ -f "/etc/alpine-release" ]; then
        pkill -f '[w]eb'
        cd /root/app && nohup ./web -c config.json >/dev/null 2>&1 &
    else
        systemctl restart xray.service
    fi

    echo -e "${green}Reality端口已更换成$new_port${re}"
    echo -e "${yellow}可返回菜单选择“查询Reality节点链接”获取新链接。${re}"
}

main_menu() {
    while true; do
        clear
        echo "--------------"
        echo -e "${green}1. 安装Reality${re}"
        echo -e "${red}2. 卸载Reality${re}"
        echo -e "${yellow}3. 更换Reality端口${re}"
        echo -e "${purple}4. 查询Reality节点链接${re}"
        echo -e "${purple}5. 查看流量/连接/客户端归属地${re}"
        echo -e "${purple}6. 查看历史客户端流量（日统计）${re}"
        echo "--------------"
        echo -e "${skyblue}0. 退出${re}"
        echo "--------------"
        read -p $'\033[1;91m请输入你的选择: \033[0m' sub_choice

        case "$sub_choice" in
            1) install_reality; break_end ;;
            2) uninstall_reality; break_end ;;
            3) change_reality_port; break_end ;;
            4) query_reality_link; break_end ;;
            5) show_reality_stats ;;
            6) show_history_stats; break_end ;;
            0) exit 0 ;;
            *) echo -e "${red}无效的输入!${re}"; sleep 1 ;;
        esac
    done
}

main_menu
