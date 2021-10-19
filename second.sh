#!/bin/bash
# It provide below functions:
# 1. iptables and route rules
# 2. Check CLASH and Country database version and update it
# 2021/10/19 Heyel

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

del_iproute_rules(){
    ip rule flush table 200
    ip route flush table 200
}

add_iproute_rules(){
    echo "Add ip route rules..."
    ip rule add fwmark 1 table 200
    ip route add local default dev lo table 200
    echo "Done."
}

update_iproute_rules(){
    del_iproute_rules
    add_iproute_rules
}

del_iptable_rules(){
    iptables -t mangle -D PREROUTING -j CLASH
    iptables -t mangle -F CLASH
    iptables -t mangle -X CLASH
    
    iptables -t nat -D PREROUTING -j CLASH
    iptables -t nat -F CLASH
    iptables -t nat -X CLASH
}

add_iptable_rules(){
    echo "Add iptable rules..."
    # Add the rules
    iptables -t mangle -N CLASH
    iptables -t mangle -A CLASH -d 0.0.0.0/8 -j RETURN
    iptables -t mangle -A CLASH -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A CLASH -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A CLASH -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A CLASH -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A CLASH -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A CLASH -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A CLASH -d 240.0.0.0/4 -j RETURN
    # prevent dns redirect
    iptables -t mangle -A CLASH -p udp --dport 53 -j RETURN
    iptables -t mangle -A CLASH -j RETURN -m mark --mark 0xff
    # prevent zerotier redirect
    iptables -t mangle -A CLASH -p udp -j TPROXY --on-port 7893 --tproxy-mark 1
    iptables -t mangle -A CLASH -p tcp -j TPROXY --on-port 7893 --tproxy-mark 1
    # REDIRECT
    iptables -t mangle -A PREROUTING -j CLASH
    # Redirect DNS requests to CLASH DNS
    iptables -t nat -N CLASH
    iptables -t nat -A CLASH -p udp --dport 53 -j REDIRECT --to-port 7853
    iptables -t nat -A PREROUTING -j CLASH
    echo "Done."
}

update_iptable_rules(){
    # Remove them if the rules exists
    del_iptable_rules
    # Add rules
    add_iptable_rules
}

update_rules(){
    case ${1} in
        "iproute")
            update_iproute_rules
            ;;
        "iptable")
            update_iptable_rules
            ;;
        "")
            update_iproute_rules
            update_iptable_rules
            ;;
        *)
            echo "Usage --rule ${1} {iproute|iptable|empty(all)}"
    esac
}

TRUE=0
FALSE=1
CLASH_CONFIG_PATH="/home/pi/.config/clash"
UPDATED=1
is_newer(){
    if [ ! -f $2 ]; then
        return 0
    else
        new_version=$(sha256sum $1 |head -c 64)
        old_version=$(sha256sum $2 |head -c 64)
       [ $new_version != $old_version ]
    fi
}

download(){
    until [ -e $2 ]
    do
        wget $1
    done
}

check_clash_version(){
    arc_info=$(uname -m |sed 's/ *l.*$//g')
    clash_version=$(curl --silent "https://api.github.com/repos/Dreamacro/clash/releases/latest"|grep '"tag_name"' |sed -E 's/.*"([^"]+)".*/\1/')
    old_version=$(clash -v |cut -d ' ' -f2)
    if [ ${clash_version}!=${old_version} ];then
        clash_download_url="https://github.com/Dreamacro/clash/releases/latest/download/clash-linux-${arc_info}-${clash_version}.gz"
        cd /tmp
        download $clash_download_url clash-linux-${arc_info}-${clash_version}.gz
        gzip -d clash-linux-${arc_info}-${clash_version}.gz
        is_newer ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
        if [ $? = $TRUE ]; then
            $UPDATED=0
            echo "Updating Clash to the new version..."
            # mv /usr/local/bin/clash ./clash-old
            cp ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
            # chmod +x /usr/local/bin/clash
            # rm ./clash-old
        fi
        rm ./clash-linux-${arc_info}-${clash_version}
        unset arc_info clash_version clash_download_url
        cd -
    fi
}

check_country_version(){
    cd /tmp
    download https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb Country.mmdb
    is_newer ./Country.mmdb $CLASH_CONFIG_PATH/Country.mmdb
    if [ $? = $TRUE ]; then
        $UPDATED=0
        echo "Updating Country.mmdb to the new version..."
        # mv $CLASH_CONFIG_PATH/Country.mmdb ./Country-old.mmdb
        cp Country.mmdb $CLASH_CONFIG_PATH/
        # rm ./Country-old.mmdb
    fi
    rm ./Country.mmdb
    cd -
}

update_clash(){
    echo "Checking for updates about clash and country.mmdb..."
    check_clash_version
    check_country_version
    if [ $UPDATED = $TRUE ]; then
        service clash stop
        service clash start
    fi
    echo "Done."
}

case ${1} in
    "--rule")
        update_rules ${2}
        ;;
    "--clash")
        update_clash
        ;;
    *)
        echo "Usage ${0} {--rule|--clash)"
        ;;
esac
