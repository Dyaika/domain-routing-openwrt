#!/bin/sh

HIRKN=/etc/init.d/hirkn
DUMP=/tmp/dump.txt

checkpoint_true() {
    printf "\033[32;1m[\342\234\223] $1\033[0m\n"
}

checkpoint_false() {
    printf "\033[31;1m[x] $1\033[0m\n"
}

output_21() {
    if [ "$VERSION_ID" -eq 21 ]; then
        echo "You are using OpenWrt 21.02. This check does not support it"
    fi
}

# System Details
MODEL=$(grep machine /proc/cpuinfo | cut -d ':' -f 2)
RELEASE=$(grep OPENWRT_RELEASE /etc/os-release | awk -F '"' '{print $2}')
printf "\033[34;1mModel:$MODEL\033[0m\n"
printf "\033[34;1mVersion: $RELEASE\033[0m\n"

VERSION_ID=$(grep VERSION_ID /etc/os-release | awk -F '"' '{print $2}' | awk -F. '{print $1}')
RAM=$(free -m | grep Mem: | awk '{print $2}')
if [[ "$VERSION_ID" -ge 22 && "$RAM" -lt 150000 ]]
then 
   echo "Your router has less than 256MB of RAM. I recommend using only the vpn_domains list"
fi

# Check packages
DNSMASQ=$(opkg list-installed | grep dnsmasq-full | awk -F "-" '{print $3}' | tr -d '.' )
if [ $DNSMASQ -ge 287 ]; then
    checkpoint_true "Dnsmasq-full package"
else
    checkpoint_false "Dnsmasq-full package"
    echo "If you don't use vpn_domains set, it's OK"
    echo "Check version: opkg list-installed | grep dnsmasq-full"
    echo "Required version >= 2.87. For openwrt 22.03 follow manual: https://t.me/itdoginfo/12"
    if [ "$VERSION_ID" -eq 21 ]; then
        echo "You are using OpenWrt 21.02. This check does not support it"
        echo "Manual for openwrt 21.02: https://t.me/itdoginfo/8"
    fi
fi

WIREGUARD=$(opkg list-installed | grep -c wireguard-tools )
if [ $WIREGUARD -eq 1 ]; then
    checkpoint_true "Wireguard-tools package"
else
    checkpoint_false "Wireguard-tools package"
    echo "If you don't use WG, but OpenVPN for example, it's OK"
    echo "Install: opkg install wireguard-tools"
fi

CURL=$(opkg list-installed | grep -c curl)
if [ $CURL -eq 2 ]; then
    checkpoint_true "Curl package"
else
    checkpoint_false "Curl package"
    echo "Install: opkg install curl"
fi

# Check internet connection
CHECK_INTERNET=$(curl -Is https://community.antifilter.download/ | grep -c 200)

if [ $CHECK_INTERNET -ne 0 ]; then
    checkpoint_true "Check Internet"
    else
    checkpoint_false "Check Internet"
    if [ $CURL -lt 2 ]; then
        echo "Install curl: opkg install curl"
    else
        echo "Check internet connection. If ok, check date on router. Details: https://cli.co/2EaW4rO"
        echo "For more info run: curl -Is https://community.antifilter.download/"
    fi
fi

# Check WG
WG_PING=$(ping -c 1 -q -I wg0 itdog.info | grep -c "1 packets received")
if [ $WG_PING -eq 1 ]; then
    checkpoint_true "Wireguard"
else
    checkpoint_false "Wireguard"
    WG_TRACE=$(traceroute -i wg0 itdog.info -m 1 | grep ms | awk '{print $2}' | grep -c -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
    if [ $WG_TRACE -eq 1 ]; then
        echo "Tunnel to wg server is work, but routing to internet doesn't work. Check server configuration. Details: https://cli.co/RSCvOxI"
    else
        echo "Bad news: WG tunnel isn't work, check your WG configuration. Details: https://cli.co/hGUUXDs"
        echo "If you don't use WG, but OpenVPN for example, it's OK"
    fi
fi

# Check WG route_allowed_ips
if uci show network | grep -q ".route_allowed_ips='1'"; then
    checkpoint_false "Wireguard route_allowed_ips"
    echo "All traffic goes into the tunnel. Read more at: https://cli.co/SaxBzH7"
else
    checkpoint_true "Wireguard route_allowed_ips"
fi

# Check route table
ROUTE_TABLE=$(ip route show table vpn | grep -c "default dev wg0 scope link" )
if [ $ROUTE_TABLE -eq 1 ]; then
    checkpoint_true "Route table VPN"
else
    checkpoint_false "Route table VPN"
    echo "Details: https://cli.co/Atxr6U3"
fi

# Check sets

# vpn_domains set
vpn_domain_ipset_id=$(uci show firewall | grep -E '@ipset.*vpn_domains' | awk -F '[][{}]' '{print $2}' | head -n 1)
vpn_domain_ipset_string=$(uci show firewall.@ipset[$vpn_domain_ipset_id] | grep -c "name='vpn_domains'\|match='dst_net'")
vpn_domain_rule_id=$(uci show firewall | grep -E '@rule.*vpn_domains' | awk -F '[][{}]' '{print $2}' | head -n 1)
vpn_domain_rule_string=$(uci show firewall.@rule[$vpn_domain_rule_id] | grep -c "name='mark_domains'\|src='lan'\|dest='*'\|proto='all'\|ipset='vpn_domains'\|set_mark='0x1'\|target='MARK'\|family='ipv4'")

if [ $((vpn_domain_ipset_string + vpn_domain_rule_string)) -eq 10 ]; then
    checkpoint_true "vpn_domains set"
else
    checkpoint_false "vpn_domains set"
    echo "If you don't use vpn_domains set, it's OK"
    echo "But if you want use, check config: https://cli.co/AwUGeM6"
fi

# vpn_ip set
vpn_ip_ipset_id=$(uci show firewall | grep -E '@ipset.*vpn_ip' | awk -F '[][{}]' '{print $2}' | head -n 1)
vpn_ip_ipset_string=$(uci show firewall.@ipset[$vpn_ip_ipset_id] | grep -c "name='vpn_ip'\|match='dst_net'\|loadfile='/tmp/lst/ip.lst'")
vpn_ip_rule_id=$(uci show firewall | grep -E '@rule.*vpn_ip' | awk -F '[][{}]' '{print $2}' | head -n 1)
vpn_ip_rule_string=$(uci show firewall.@rule[$vpn_ip_rule_id] | grep -c "name='mark_ip'\|src='lan'\|dest='*'\|proto='all'\|ipset='vpn_ip'\|set_mark='0x1'\|target='MARK'\|family='ipv4'")

if [ $((vpn_ip_ipset_string + vpn_ip_rule_string)) -eq 11 ]; then
    checkpoint_true "vpn_ip set"
else
    checkpoint_false "vpn_ip set"
    echo "If you don't use vpn_ip set, it's OK"
    echo "But if you want use, check config: https://cli.co/AwUGeM6"
fi

# vpn_subnet set
vpn_subnet_ipset_id=$(uci show firewall | grep -E '@ipset.*vpn_subnet' | awk -F '[][{}]' '{print $2}' | head -n 1)
vpn_subnet_ipset_string=$(uci show firewall.@ipset[$vpn_subnet_ipset_id] | grep -c "name='vpn_subnets'\|match='dst_net'\|loadfile='/tmp/lst/subnet.lst'")
vpn_subnet_rule_id=$(uci show firewall | grep -E '@rule.*vpn_subnet' | awk -F '[][{}]' '{print $2}' | head -n 1)
vpn_subnet_rule_string=$(uci show firewall.@rule[$vpn_subnet_rule_id] | grep -c "name='mark_subnet'\|src='lan'\|dest='*'\|proto='all'\|ipset='vpn_subnets'\|set_mark='0x1'\|target='MARK'\|family='ipv4'")

if [ $((vpn_subnet_ipset_string + vpn_subnet_rule_string)) -eq 11 ]; then
    checkpoint_true "vpn_subnet set"
else
    checkpoint_false "vpn_subnet set"
    echo "If you don't use vpn_subnet set, it's OK"
    echo "But if you want use, check config: https://cli.co/AwUGeM6"
fi

# vpn_community set
vpn_community_ipset_id=$(uci show firewall | grep -E '@ipset.*vpn_community' | awk -F '[][{}]' '{print $2}' | head -n 1)
vpn_community_ipset_string=$(uci show firewall.@ipset[$vpn_community_ipset_id] | grep -c "name='vpn_community'\|match='dst_net'\|loadfile='/tmp/lst/community.lst'")
vpn_community_rule_id=$(uci show firewall | grep -E '@rule.*vpn_community' | awk -F '[][{}]' '{print $2}' | head -n 1)
vpn_community_rule_string=$(uci show firewall.@rule[$vpn_community_rule_id] | grep -c "name='mark_community'\|src='lan'\|dest='*'\|proto='all'\|ipset='vpn_community'\|set_mark='0x1'\|target='MARK'\|family='ipv4'")

if [ $((vpn_community_ipset_string + vpn_community_rule_string)) -eq 11 ]; then
    checkpoint_true "vpn_community set"
else
    checkpoint_false "vpn_community set"
    echo "If you don't use vpn_community set, it's OK"
    echo "But if you want use, check config: https://cli.co/AwUGeM6"
    output_21
fi

# Check IPs in sets

# force resolve for vpn_domains
nslookup zona.media 127.0.0.1 > /dev/null

VPN_DOMAINS_IP=$(nft list ruleset | grep -A 10 vpn_domains | grep -c -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
if [ $VPN_DOMAINS_IP -ge 1 ]; then
    checkpoint_true "IPs in vpn_domains"
else
    checkpoint_false "IPs in vpn_domains"
    echo "If you don't use vpn_domains, it's OK"
    echo "But if you want use, check configs"
    output_21
fi

VPN_IP_IP=$(nft list ruleset | grep -A 10 vpn_ip | grep -c -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
if [ $VPN_IP_IP -ge 1 ]; then
    checkpoint_true "IPs in vpn_ip"
else
    checkpoint_false "IPs in vpn_ip"
    echo "If you don't use vpn_ip, it's OK"
    echo "But if you want use, check configs"
    output_21
fi

VPN_IP_SUBNET=$(nft list ruleset | grep -A 10 vpn_subnet | grep -c -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
if [ $VPN_IP_SUBNET -ge 1 ]; then
    checkpoint_true "IPs in vpn_subnet"
else
    checkpoint_false "IPs in vpn_subnet"
    echo "If you don't use vpn_subnet, it's OK"
    echo "But if you want use, check configs"
    output_21
fi

VPN_COMMUNITY_IP=$(nft list ruleset | grep -A 10 vpn_community | grep -c -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
if [ $VPN_COMMUNITY_IP -ge 1 ]; then
    checkpoint_true "IPs in vpn_community"
else
    checkpoint_false "IPs in vpn_community"
    echo "If you don't use vpn_community, it's OK"
    echo "But if you want use, check configs"
    output_21
fi

# Check dnsmasq

DNSMASQ_RUN=$(service dnsmasq status | grep -c 'running')
if [ $DNSMASQ_RUN -eq 1 ]; then
    checkpoint_true "Dnsmasq service"
else
    checkpoint_false "Dnsmasq service"
    echo "Check config /etc/config/dhcp"
    output_21
fi

# Check hirkn script
if [ -s "$HIRKN" ]; then
    checkpoint_true "Script hirkn"
else
    checkpoint_false "Script hirkn"
    echo "Script don't exists in $HIRKN"
fi

HIRKN_CRON=$(crontab -l | grep -c "/etc/init.d/hirkn")
if [ $HIRKN_CRON -eq 1 ]; then
    checkpoint_true "Script hirkn in crontab"
else
    checkpoint_false "Script hirkn in crontab"
    echo "Script is not enabled in crontab. Check: crontab -l"
fi

# DNSCrypt
DNSCRYPT=$(opkg list-installed | grep -c dnscrypt-proxy2 )
if [ $DNSCRYPT -eq 1 ]; then
    checkpoint_true "Dnscrypt-proxy2 package"
else
    checkpoint_false "Dnscrypt-proxy2 package"
    echo "If you don't use Dnscrypt, it's OK"
    echo "But if you want use, install: opkg install dnscrypt-proxy2"
fi

DNSCRYPT_RUN=$(service dnscrypt-proxy status | grep -c 'running')
if [ $DNSCRYPT_RUN -eq 1 ]; then
    checkpoint_true "DNSCrypt service"
else
    checkpoint_false "DNSCrypt service"
    echo "If you don't use Dnscrypt, it's OK"
    echo "But if you want use, check config: https://cli.co/wN-tc_S"
    output_21
fi

DNSMASQ_NETWORK_STRING=$(uci show network.wan.peerdns | grep -c "peerdns='0'")
if [ $DNSMASQ_NETWORK_STRING -eq 1 ]; then
    checkpoint_true "Network config for DNSCrypt"
else
    checkpoint_false "Network config for DNSCrypt"
    echo "If you don't use Dnscrypt, it's OK"
    echo "But if you want use, check peerdns='0' in /etc/config/network"
fi

DNSMASQ_STRING=$(uci show dhcp.@dnsmasq[0] | grep -c "127.0.0.53#53\|noresolv='1'")
if [ $DNSMASQ_STRING -eq 2 ]; then
    checkpoint_true "Dnsmasq config for DNSCrypt"
else
    checkpoint_false "Dnsmasq config for DNSCrypt"
    echo "If you don't use Dnscrypt, it's OK"
    echo "But if you want use, check config: https://cli.co/rooc0uz"
fi

# Create dump
if [[ "$1" == dump ]]; then
    printf "\033[36;1mCreate dump without private variables\033[0m\n"
    date > $DUMP
    /etc/init.d/hirkn start >> $DUMP 2>&1
    uci show firewall >> $DUMP
    uci show network | sed -r 's/(.*private_key=|.*preshared_key=|.*public_key=|.*endpoint_host=|.*wan.ipaddr=|.*wan.netmask=|.*wan.gateway=|.*wan.dns|.*.macaddr=).*/\1REMOVED/' >> $DUMP

    echo "Dump is here: $DUMP"
    echo "For download Linux/Mac use:"
    echo "scp root@IP_ROUTER:$DUMP ."
    echo "For Windows use PSCP or WSL"
fi

# Info
echo -e "\nTelegram channel: https://t.me/itdoginfo"
echo "Telegram chat: https://t.me/itdogchat"
