#!/bin/bash
# It makes raspbian to be router that lets you access the blocked sites by the clash
# 2021/03/15 Shawn

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

TRUE=0
FALSE=1

CLASH_CONFIG_PATH="/etc/clash"

update_iptable_rules(){
    if [ ! -f $CLASH_CONFIG_PATH/iptables.up.rules ];then
        echo "Updating iptable rules..."
        iptables -t nat -N CLASH
        iptables -t nat -A CLASH -d 10.0.0.0/8 -j RETURN
        iptables -t nat -A CLASH -d 127.0.0.0/8 -j RETURN
        iptables -t nat -A CLASH -d 169.254.0.0/16 -j RETURN
        iptables -t nat -A CLASH -d 172.16.0.0/12 -j RETURN
        iptables -t nat -A CLASH -d 192.168.0.0/16 -j RETURN
        iptables -t nat -A CLASH -d 224.0.0.0/4 -j RETURN
        iptables -t nat -A CLASH -d 240.0.0.0/4 -j RETURN
        iptables -t nat -A CLASH -p tcp -j REDIRECT --to-ports 7892
        iptables -t nat -I PREROUTING -p tcp -j CLASH

        iptables_clash=$CLASH_CONFIG_PATH/iptables.up.rules
        iptables-save > $iptables_clash

        preup_clash=/etc/network/if-pre-up.d/clash
        touch $preup_clash
        echo "#!/bin/sh
        /sbin/iptables-restore < $iptables_clash" |tee $preup_clash>/dev/null
        chmod +x $preup_clash
        unset iptables_clash preup_clash
    fi
}

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

download_clash(){
    if [ ! -z $(uname -m |grep 'armv') ]; then
        echo "Downloading clash..."
        arc_info=$(uname -m |sed 's/ *l.*$//g')
        clash_version=$(curl --silent "https://api.github.com/repos/Dreamacro/clash/releases/latest"|grep '"tag_name"' |sed -E 's/.*"([^"]+)".*/\1/')
        clash_download_url="https://github.com/Dreamacro/clash/releases/latest/download/clash-linux-${arc_info}-${clash_version}.gz"
        cd /tmp
        download $clash_download_url clash-linux-${arc_info}-${clash_version}.gz
        gzip -d clash-linux-${arc_info}-${clash_version}.gz
        is_newer ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
        if [ $? ]; then
            cp ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
            chmod +x /usr/local/bin/clash
        fi
        rm ./clash-linux-${arc_info}-${clash_version}
        echo "Downloading clash configuration files like Country.mmdb, ui(yacd)..."
        # Download Country.mmdb
        download https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb Country.mmdb
        is_newer ./Country.mmdb $CLASH_CONFIG_PATH/Country.mmdb
        if [ $? = $TRUE ]; then
            cp Country.mmdb $CLASH_CONFIG_PATH/
        fi
        rm ./Country.mmdb
        # Download ui(yacd)
        download https://github.com/haishanh/yacd/releases/latest/download/yacd.tar.xz yacd.tar.xz
        if [ -f $CLASH_CONFIG_PATH/ui ]; then
            tar -Jcf ./yacd-old.tar.xz $CLASH_CONFIG_PATH/ui
        fi
        is_newer ./yacd.tar.xz ./yacd-old.tar.xz
        if [ $? = $TURE ];then
            tar -Jxf yacd.tar.xz
            mv public $CLASH_CONFIG_PATH/ui
        fi
        rm yacd.tar.xz yacd-old.tar.xz

        # download https://raw.githubusercontent.com/erheisw/rasprouter/config.yaml config.yaml
        # if [ ! -f $CLASH_CONFIG_PATH/config.yaml ]; then
        #     mv config.yaml $/CLASH_CONFIG_PATH/config.yaml
        # fi
        # rm config.yaml
        unset arc_info clash_version clash_download_url
        cd -
    fi
}

add_clash_system_service(){
    echo "Creating system service for clash..."
    if [ -z "$(systemctl -a |grep clash.service)" ]; then
        # Generating the systemd configuration file of clash
        clash_service=/etc/systemd/system/clash.service
        if [ ! -f $clash_service ]; then
            touch $clash_service
            echo "[Unit]
            Description=Clash daemon, A rule-based proxy in Go.
            After=network.target
            
            [Service]
            Type=simple
            Restart=always
            ExecStart=$(which clash) -d ${CLASH_CONFIG_PATH}
            
            [Install]
            WantedBy=multi-user.target" |tee $clash_service>/dev/null
            systemctl enable clash
        fi
        unset clash_service
    fi
}

install_dhcp_server(){
    echo "Downloading dhcp server..."
    if [ -z "$(systemctl -a |grep isc-dhcp-server)" ]; then
        apt-get install isc-dhcp-server -y
        read -p "Please input ip address (eg. 192.168.1.3): " static_ip
        read -p "Please input router ip address (eg. 192.168.1.2): " router_ip
        read -p "Please input subnet ip (eg. 192.168.1.0) : " subnet_ip
        read -p "Please input netmask (eg. 255.255.255.0) : " netmask
        read -p "Please input ip range (eg. 192.168.1.4 192.168.1.254) : " ip_range
        read -p "Please input broadcast ip (eg. 192.168.1.255) : " broadcast_ip
        cd /etc/
        if [ ! -f ./dhcpcd.conf.bak ]; then
            cp ./dhcpcd.conf ./dhcpcd.conf.bak
            cat ./dhcpcd.conf.bak |sed 's/^#.*//g' |sed '/^$/d' > ./dhcpcd.conf
            echo "interface eth0
            static ip_address=${static_ip}/24
            static routers=${router_ip}" |tee -a ./dhcpcd.conf>/dev/null
        fi
        cd ./dhcp
        if [ ! -f ./dhcpd.conf.bak ]; then
            cp ./dhcpd.conf ./dhcpd.conf.bak
            cat ./dhcpd.conf.bak |sed 's/^#.*//g' |sed '/^$/d' > ./dhcpd.conf
            sed -i "1s/example.org/home/g" ./dhcpd.conf
            sed -i "2s/.*/option domain-name-servers ${static_ip};/g" ./dhcpd.conf
            echo 'subnet ${subnet_ip} netmask ${netmask} {
                range ${ip_range};
                option routers ${static_ip};
                option broadcast-address ${broadcast_ip};
                }' | tee -a ./dhcpd.conf>/dev/null
        fi
        cd -
        cd -
    fi
}

main(){
    if [ ! -d $CLASH_CONFIG_PATH ];then
        mkdir $CLASH_CONFIG_PATH
    fi
    download_clash
    add_clash_system_service
    install_dhcp_server
    update_iptable_rules
    exit 0
}

main