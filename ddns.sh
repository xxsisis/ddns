#!/bin/bash

# 输出字体颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[0;33m"
NC="\033[0m"
GREEN_ground="\033[42;37m" # 全局绿色
RED_ground="\033[41;37m"   # 全局红色
Info="${GREEN}[信息]${NC}"
Error="${RED}[错误]${NC}"
Tip="${YELLOW}[提示]${NC}"

cop_info(){
clear
echo -e "${GREEN}######################################
#       ${RED}DDNS 一键脚本${GREEN}               #
#         作者: ${YELLOW}AICM${GREEN}             #
#      ${GREEN}https://110.al${GREEN}             #
######################################${NC}"

}

# 检查系统是否为 Debian、Ubuntu 或 Alpine
if ! grep -qiE "debian|ubuntu|alpine" /etc/os-release; then
    echo -e "${RED}本脚本仅支持 Debian、Ubuntu 或 Alpine 系统，请在这些系统上运行。${NC}"
    exit 1
fi

# 检查是否为root用户
if [[ $(whoami) != "root" ]]; then
    echo -e "${Error}请以root身份执行该脚本！"
    exit 1
fi

# 检查是否安装 curl 和 GNU grep（仅 Alpine），如果没有安装，则安装它们
check_curl() {
    if ! command -v curl &>/dev/null; then
        echo -e "${YELLOW}未检测到 curl，正在安装 curl...${NC}"

        # 根据不同的系统类型选择安装命令
        if grep -qiE "debian|ubuntu" /etc/os-release; then
            apt update
            apt install -y curl
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Debian/Ubuntu 上安装 curl 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        elif grep -qiE "alpine" /etc/os-release; then
            apk update
            apk add curl
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Alpine 上安装 curl 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        fi
    fi

    # 仅在 Alpine 系统上检查是否为 GNU 版本的 grep，如果不是，则安装 GNU grep
    if grep -qiE "alpine" /etc/os-release; then
        if ! grep --version 2>/dev/null | grep -q "GNU"; then
            echo -e "${YELLOW}当前 grep 不是 GNU 版本，正在安装 GNU grep...${NC}"
            
            apk update
            apk add grep
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Alpine 上安装 GNU grep 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        else
            echo -e "${GREEN}GNU grep 已经安装。${NC}"
        fi
    fi
}

# 开始安装DDNS
install_ddns(){
    if [ ! -f "/usr/bin/ddns" ]; then
        curl -o /usr/bin/ddns https://raw.githubusercontent.com/xxsisis/shell/main/ddns.sh && chmod +x /usr/bin/ddns
    fi
    mkdir -p /etc/DDNS
    
    # 新增服务器名称配置
    echo -e "${Tip}请输入服务器标识名称（如：香港节点/AWS东京）"
    read -p "(默认：我的服务器): " server_name
    server_name=${server_name:-"我的服务器"}
    
    cat <<'EOF' > /etc/DDNS/DDNS
#!/bin/bash

# 引入环境变量文件
source /etc/DDNS/.config

# 保存旧的 IP 地址
Old_Public_IPv4="$Old_Public_IPv4"
Old_Public_IPv6="$Old_Public_IPv6"

for Domain in "${Domains[@]}"; do
    # 获取根域名（假设是二级域名，截取主域名部分）
    Root_domain=$(echo "$Domain" | awk -F '.' '{print $(NF-1)"."$NF}')

    # 使用Cloudflare API获取根域名的区域ID
    Zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$Root_domain" \
         -H "X-Auth-Email: $Email" \
         -H "X-Auth-Key: $Api_key" \
         -H "Content-Type: application/json" \
         | grep -Po '(?<="id":")[^"]*' | head -1)

    # 获取IPv4 DNS记录ID
    DNS_IDv4=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$Zone_id/dns_records?type=A&name=$Domain" \
         -H "X-Auth-Email: $Email" \
         -H "X-Auth-Key: $Api_key" \
         -H "Content-Type: application/json" \
         | grep -Po '(?<="id":")[^"]*' | head -1)

    # 更新IPv4 DNS记录
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$Zone_id/dns_records/$DNS_IDv4" \
         -H "X-Auth-Email: $Email" \
         -H "X-Auth-Key: $Api_key" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"A\",\"name\":\"$Domain\",\"content\":\"$Public_IPv4\"}" >/dev/null 2>&1
done

# -----------------------------
# 处理 IPv6 域名的 DNS 更新
# -----------------------------
if [ "$ipv6_set" = "true" ]; then
    for Domainv6 in "${Domainsv6[@]}"; do
        # 获取根域名（假设是二级域名，截取主域名部分）
        Root_domainv6=$(echo "$Domainv6" | awk -F '.' '{print $(NF-1)"."$NF}')

        # 使用Cloudflare API获取根域名的区域ID
        Zone_idv6=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$Root_domainv6" \
             -H "X-Auth-Email: $Email" \
             -H "X-Auth-Key: $Api_key" \
             -H "Content-Type: application/json" \
             | grep -Po '(?<="id":")[^"]*' | head -1)

        # 获取IPv6 DNS记录ID
        DNS_IDv6=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$Zone_idv6/dns_records?type=AAAA&name=$Domainv6" \
             -H "X-Auth-Email: $Email" \
             -H "X-Auth-Key: $Api_key" \
             -H "Content-Type: application/json" \
             | grep -Po '(?<="id":")[^"]*' | head -1)

        # 更新IPv6 DNS记录
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$Zone_idv6/dns_records/$DNS_IDv6" \
             -H "X-Auth-Email: $Email" \
             -H "X-Auth-Key: $Api_key" \
             -H "Content-Type: application/json" \
             --data "{\"type\":\"AAAA\",\"name\":\"$Domainv6\",\"content\":\"$Public_IPv6\"}" >/dev/null 2>&1
    done
fi

# 发送Telegram通知
if [[ -n "$Telegram_Bot_Token" && -n "$Telegram_Chat_ID" && (("$Public_IPv4" != "$Old_Public_IPv4" && -n "$Public_IPv4") || ("$Public_IPv6" != "$Old_Public_IPv6" && -n "$Public_IPv6")) ]]; then
    send_telegram_notification
fi

# 延迟3秒
sleep 3

# 保存当前的 IP 地址到配置文件，但只有当 IP 地址有变化时才进行更新
if [[ -n "$Public_IPv4" && "$Public_IPv4" != "$Old_Public_IPv4" ]]; then
    sed -i "s/^Old_Public_IPv4=.*/Old_Public_IPv4=\"$Public_IPv4\"/" /etc/DDNS/.config
fi

# 检查 IPv6 地址是否有效且发生变化
if [[ -n "$Public_IPv6" && "$Public_IPv6" != "$Old_Public_IPv6" ]]; then
    sed -i "s/^Old_Public_IPv6=.*/Old_Public_IPv6=\"$Public_IPv6\"/" /etc/DDNS/.config
fi
EOF

    # 修改后的配置文件模板
    cat <<EOF > /etc/DDNS/.config
# 服务器标识名称
Server_Name="$server_name"

# 多域名支持
Domains=("your_domain1.com" "your_domain2.com")     # 你要解析的IPv4域名数组
ipv6_set="setting"                                    # 开启 IPv6 解析
Domainsv6=("your_domainv6_1.com" "your_domainv6_2.com")  # 你要解析的IPv6域名数组
Email="your_email@gmail.com"                       # 你的 Cloudflare 注册邮箱
Api_key="your_api_key"                             # 你的 Cloudflare API 密钥

# Telegram Bot Token 和 Chat ID
Telegram_Bot_Token=""
Telegram_Chat_ID=""

# 获取公网IP地址
regex_pattern='^(eth|ens|eno|esp|enp)[0-9]+'

# 获取网络接口列表
InterFace=($(ip link show | awk -F': ' '{print $2}' | grep -E "\$regex_pattern" | sed "s/@.*//g"))

Public_IPv4=""
Public_IPv6=""
Old_Public_IPv4=""
Old_Public_IPv6=""
ipv4Regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
ipv6Regex="^([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])$"

# 检查操作系统类型
if grep -qiE "debian|ubuntu" /etc/os-release; then
    # Debian/Ubuntu系统的IP获取方法
    for i in "${InterFace[@]}"; do
        # 尝试通过第一个接口获取 IPv4 地址
        ipv4=$(curl -s4 --max-time 3 --interface "$i" ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)

        # 如果第一个接口的 IPv4 地址获取失败，尝试备用接口
        if [[ -z "$ipv4" ]]; then
            ipv4=$(curl -s4 --max-time 3 --interface "$i" https://api.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
        fi

        # 验证获取到的 IPv4 地址是否是有效的 IP 地址
        if [[ -n "$ipv4" && "$ipv4" =~ \$ipv4Regex ]]; then
            Public_IPv4="$ipv4"
        fi

        # 检查是否启用了 IPv6 解析
        if [[ "\$ipv6_set" == "true" ]]; then
            # 尝试通过第一个接口获取 IPv6 地址
            ipv6=$(curl -s6 --max-time 3 --interface "$i" ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)

            # 如果第一个接口的 IPv6 地址获取失败，尝试备用接口
            if [[ -z "$ipv6" ]]; then
                ipv6=$(curl -s6 --max-time 3 --interface "$i" https://api6.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
            fi

            # 验证获取到的 IPv6 地址是否是有效的 IP 地址
            if [[ -n "$ipv6" && "$ipv6" =~ \$ipv6Regex ]]; then
                Public_IPv6="$ipv6"
            fi
        fi
    done
else
    # Alpine系统的IP获取方法
    # 尝试获取 IPv4 地址
    ipv4=$(curl -s4 --max-time 3 ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)
    if [[ -z "$ipv4" ]]; then
        ipv4=$(curl -s4 --max-time 3 https://api.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
    fi

    # 验证获取到的 IPv4 地址是否是有效的 IP 地址
    if [[ -n "$ipv4" && "$ipv4" =~ \$ipv4Regex ]]; then
        Public_IPv4="$ipv4"
    fi

    # 检查是否启用了 IPv6 解析
    if [[ "\$ipv6_set" == "true" ]]; then
        # 尝试获取 IPv6 地址
        ipv6=$(curl -s6 --max-time 3 ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)
        if [[ -z "$ipv6" ]]; then
            ipv6=$(curl -s6 --max-time 3 https://api6.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
        fi

        # 验证获取到的 IPv6 地址是否是有效的 IP 地址
        if [[ -n "$ipv6" && "$ipv6" =~ \$ipv6Regex ]]; then
            Public_IPv6="$ipv6"
        fi
    fi
fi

# 发送 Telegram 通知函数
send_telegram_notification() {
    local message="🖥️ <b>${Server_Name}</b> 动态IP变更通知%0A%0A"
    
    # IPv4更新部分
    if [[ -n "\$Public_IPv4" && "\$Public_IPv4" != "\$Old_Public_IPv4" ]]; then
        message+="📡 <u>IPv4 变更记录</u> %0A"
        message+="🕒 时间: \$(date '+%Y-%m-%d %H:%M:%S') %0A"
        message+="📥 旧地址: \$Old_Public_IPv4 %0A"
        message+="📤 新地址: \$Public_IPv4 %0A%0A"
    fi

    # IPv6更新部分
    if [[ "\$ipv6_set" == "true" && -n "\$Public_IPv6" && "\$Public_IPv6" != "\$Old_Public_IPv6" ]]; then
        message+="📡 <u>IPv6 变更记录</u> %0A"
        message+="🕒 时间: \$(date '+%Y-%m-%d %H:%M:%S') %0A"
        message+="📥 旧地址: \$Old_Public_IPv6 %0A"
        message+="📤 新地址: \$Public_IPv6 %0A%0A"
    fi

    message=\${message%%%0A}

    if [[ -n "\$Telegram_Bot_Token" && "\$Telegram_Bot_Token" != "your_telegram_token" ]]; then
        curl -s --max-time 10 --retry 2 -X POST "https://api.telegram.org/bot\$Telegram_Bot_Token/sendMessage" \
            -d "chat_id=\$Telegram_Chat_ID" \
            -d "text=\$message" \
            -d "parse_mode=html"
    fi
}


EOF
    chmod +x /etc/DDNS/DDNS && chmod +x /etc/DDNS/.config
    echo -e "${Info}DDNS 安装完成！"
    echo
}

# 检查 DDNS 状态
check_ddns_status() {
    if grep -qiE "alpine" /etc/os-release; then
        # 检查 cron 任务是否存在
        if crontab -l | grep -q "/bin/bash /etc/DDNS/DDNS"; then
            ddns_status=running
        else
            ddns_status=dead
        fi
    else
        # 在 Debian/Ubuntu 上检查 systemd timer 状态
        if [[ -f "/etc/systemd/system/ddns.timer" ]]; then
            STatus=$(systemctl status ddns.timer | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
            if [[ $STatus =~ "waiting" || $STatus =~ "running" ]]; then
                ddns_status=running
            else
                ddns_status=dead
            fi
        else
            ddns_status=not_installed
        fi
    fi
}

# 后续操作
go_ahead(){
    echo -e "${Tip}选择一个选项：
  ${GREEN}0${NC}：退出
  ${GREEN}1${NC}：重启 DDNS
  ${GREEN}2${NC}：停止 DDNS
  ${GREEN}3${NC}：${RED}卸载 DDNS${NC}
  ${GREEN}4${NC}：修改要解析的域名
  ${GREEN}5${NC}：修改 Cloudflare Api
  ${GREEN}6${NC}：配置 Telegram 通知
  ${GREEN}7${NC}：更改 DDNS 运行时间
  ${GREEN}8${NC}：设置服务器名称"  # 新增设置服务器名称选项
    echo
    read -p "选项: " option
    until [[ "$option" =~ ^[0-8]$ ]]; do  # 更新有效选项范围
        echo -e "${Error}请输入正确的数字 [0-8]"
        echo
        exit 1
    done
    case "$option" in
        0)
            exit 1
        ;;
        1)
            restart_ddns
        ;;
        2)
            stop_ddns
        ;;
        3)
            if grep -qiE "alpine" /etc/os-release; then
                stop_ddns
                rm -rf /etc/DDNS /usr/bin/ddns
            else
                systemctl stop ddns.service >/dev/null 2>&1
                systemctl stop ddns.timer >/dev/null 2>&1
                rm -rf /etc/systemd/system/ddns.service /etc/systemd/system/ddns.timer /etc/DDNS /usr/bin/ddns
            fi
            echo -e "${Info}DDNS 已卸载！"
            echo
        ;;
        4)
            set_domain
            restart_ddns
            sleep 2
            check_ddns_install
        ;;
        5)
            set_cloudflare_api
            if grep -qiE "alpine" /etc/os-release; then
                restart_ddns
                sleep 2
            else
                if [ ! -f "/etc/systemd/system/ddns.service" ] || [ ! -f "/etc/systemd/system/ddns.timer" ]; then
                    run_ddns
                    sleep 2
                else
                    restart_ddns
                    sleep 2
                fi
            fi
            check_ddns_install
        ;;
        6)
            set_telegram_settings
            check_ddns_install
        ;;
        7)
            set_ddns_run_interval
            sleep 2
            check_ddns_install
        ;;
        8)
            set_server_name  # 新增设置服务器名称功能
            sleep 2
            check_ddns_install
        ;;
    esac
}

# 新增设置服务器名称函数
set_server_name() {
    clear
    current_name=$(grep '^Server_Name=' /etc/DDNS/.config | cut -d '"' -f2)
    echo -e "${GREEN}当前服务器名称：${YELLOW}${current_name}${NC}"
    read -p "请输入新服务器名称：" new_name
    if [[ -n "$new_name" ]]; then
        sed -i "s/^Server_Name=.*/Server_Name=\"$new_name\"/" /etc/DDNS/.config
        echo -e "${GREEN}服务器名称已更新！${NC}"
    else
        echo -e "${RED}输入不能为空！${NC}"
    fi
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 以下保持原有函数不变（set_cloudflare_api、set_domain、set_telegram_settings等）

# 运行DDNS服务
run_ddns() {
    if grep -qiE "alpine" /etc/os-release; then
        # 在 Alpine Linux 上使用 cron
        echo -e "${Info}设置 ddns 脚本每两分钟运行一次..."

        # 检查 cron 任务是否已存在，防止重复添加
        if ! crontab -l | grep -q "/bin/bash /etc/DDNS/DDNS >/dev/null 2>&1"; then
            # 设置 cron 任务
            (crontab -l; echo "*/2 * * * * /bin/bash /etc/DDNS/DDNS >/dev/null 2>&1") | crontab -
            echo -e "${Info}ddns 脚本已设置为每两分钟运行一次！"
        else
            echo -e "${Tip}ddns 脚本的 cron 任务已存在，无需再次创建！"
        fi
    else
        # 在 Debian/Ubuntu 上使用 systemd
        service='[Unit]
Description=ddns
After=network.target

[Service]
Type=simple
WorkingDirectory=/etc/DDNS
ExecStart=bash DDNS

[Install]
WantedBy=multi-user.target'

        timer='[Unit]
Description=ddns timer

[Timer]
OnUnitActiveSec=60s
Unit=ddns.service

[Install]
WantedBy=multi-user.target'

        if [ ! -f "/etc/systemd/system/ddns.service" ] || [ ! -f "/etc/systemd/system/ddns.timer" ]; then
            echo -e "${Info}创建 ddns 定时任务..."
            echo "$service" >/etc/systemd/system/ddns.service
            echo "$timer" >/etc/systemd/system/ddns.timer
            echo -e "${Info}ddns 定时任务已创建，每1分钟执行一次！"
            systemctl enable --now ddns.service >/dev/null 2>&1
            systemctl enable --now ddns.timer >/dev/null 2>&1
        else
            echo -e "${Tip}服务和定时器单元文件已存在，无需再次创建！"
        fi
    fi
}

# 检查是否安装DDNS
check_ddns_install(){
    if [ ! -f "/etc/DDNS/.config" ]; then
        cop_info
        echo -e "${Tip}DDNS 未安装，现在开始安装..."
        echo
        install_ddns
        set_cloudflare_api
        set_domain
        set_telegram_settings
        run_ddns
        echo -e "${Info}执行 ${GREEN}ddns${NC} 可呼出菜单！"
    else
        cop_info
        check_ddns_status
        if [[ "$ddns_status" == "running" ]]; then
            echo -e "${Info}DDNS：${GREEN}已安装${NC} 并 ${GREEN}已启动${NC}"
        else
            echo -e "${Tip}DDNS：${GREEN}已安装${NC} 但 ${RED}未启动${NC}"
            echo -e "${Tip}请选择 ${GREEN}4${NC} 重新配置 Cloudflare Api 或 ${GREEN}5${NC} 配置 Telegram 通知"
        fi
        echo
        go_ahead
    fi
}

check_curl
check_ddns_install
