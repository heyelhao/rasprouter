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

generate_clash_config(){
    echo "Generating clash config.yaml..."
    if [ ! -f $CLASH_CONFIG_PATH/config.yaml ]; then
        cp ./config.yaml $CLASH_CONFIG_PATH/
    fi
}

install_clash(){
    if [ ! -z $(uname -m |grep 'armv') ]; then
        echo "Downloading clash..."
        arc_info=$(uname -m |sed 's/ *l.*$//g')
        clash_version=$(curl --silent "https://api.github.com/repos/Dreamacro/clash/releases/latest"|grep '"tag_name"' |sed -E 's/.*"([^"]+)".*/\1/')
        clash_download_url="https://github.com/Dreamacro/clash/releases/latest/download/clash-linux-${arc_info}-${clash_version}.gz"

        download $clash_download_url clash-linux-${arc_info}-${clash_version}.gz
        gzip -d clash-linux-${arc_info}-${clash_version}.gz
        is_newer ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
        if [ $? = $TRUE ]; then
            cp ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
            chmod +x /usr/local/bin/clash
        fi
        rm ./clash-linux-${arc_info}-${clash_version}
        # Generating clash config.yaml
        generate_clash_config
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
        if [ $? = $TRUE ]; then
            tar -Jxf yacd.tar.xz
            mv public $CLASH_CONFIG_PATH/ui
        fi
        rm yacd.tar.xz yacd-old.tar.xz
        unset arc_info clash_version clash_download_url
    fi
}

add_clash_system_service(){
    echo "Creating system service for clash..."
    if [ -z "$(systemctl -a |grep clash.service)" ]; then
        # Generating the systemd configuration file of clash
        clash_service=/etc/systemd/system/clash.service
        if [ ! -f $clash_service ]; then
            touch $clash_service
            echo \
"[Unit]
Description=Clash daemon, A rule-based proxy in Go.
After=network.target
[Service]
Type=simple
Restart=always
ExecStart=$(which clash) -d ${CLASH_CONFIG_PATH}
[Install]
WantedBy=multi-user.target" > $clash_service
        fi
        systemctl enable clash
        unset clash_service
    fi
}

install_dhcp_server(){
    echo "Downloading dhcp server..."
    if [ -z "$(systemctl -a |grep isc-dhcp-server)" ]; then
        apt-get install isc-dhcp-server -y
        read -p "Please input raspberry-pi ip address (eg. 192.168.1.3): " static_ip
        read -p "Please input router ip address (eg. 192.168.1.2): " router_ip
        read -p "Please input ip range (eg. 192.168.1.4 192.168.1.254) : " ip_range
        subnet_ip=$(echo ${static_ip} |cut -d '.' -f 1,2,3)".0"
        cd /etc/
        if [ ! -f ./dhcpcd.conf.bak ]; then
            cp ./dhcpcd.conf ./dhcpcd.conf.bak
        else
            cp ./dhcpcd.conf.bak ./dhcpcd.conf
        fi
        sed -i "44,45s/#//g" ./dhcpcd.conf
        sed -i "45s/192\.168\.0\.10/${static_ip}/g" ./dhcpcd.conf
        sed -i "47s/#//g" ./dhcpcd.conf
        sed -i "47s/192\.168\.0\.1/${router_ip}/g" ./dhcpcd.conf
        cd ./dhcp
        if [ ! -f ./dhcpd.conf.bak ]; then
            cp ./dhcpd.conf ./dhcpd.conf.bak
        else
            cp ./dhcpd.conf.bak ./dhcpd.conf
        fi
        sed -i "21s/#//g" ./dhcpd.conf
        sed -i "8s/ns1.example.org, ns2.example.org/${static_ip}/g" ./dhcpd.conf
        echo "subnet ${subnet_ip} netmask 255.255.255.0{
  range ${ip_range};
  option routers ${static_ip};
}" >> ./dhcpd.conf
        cd -
        cd ./default
        if [ ! -f ./isc-dhcp-server.bak ]; then
            cp ./isc-dhcp-server ./isc-dhcp-server.bak
        else
            cp ./isc-dhcp-server.bak ./isc-dhcp-server
        fi
        sed -i "8s/#//g" ./isc-dhcp-server
        sed -i '17s/""/"eth0"/g' ./isc-dhcp-server
        cd -
        cd -
        unset static_ip router_ip ip_range subnet_ip
        kill $(ps -A |grep dhcp |tr -d ' ' |cut -d '?' -f 1)
        service isc-dhcp-server restart
    fi
}

add_reboot_cron(){
    echo "Adding crontab: OS reboot at 5:30am. everyday."
    echo "# Reboot raspbian OS at 5:30am everyday">>/etc/crontab
    echo "30 05 * * * root /usr/sbin/shutdown -r now">>/etc/crontab
}

add_version_check_cron(){
    if [ ! -f $CLASH_CONFIG_PATH/version.check.sh ]; then
        echo "Adding crontab: Version check 5:10am. every Monday."
        cp ./version.check.sh $CLASH_CONFIG_PATH/version.check.sh
        chmod +x $CLASH_CONFIG_PATH/version.check.sh
        cd /etc/cron.d
        touch clash
        echo "# Run the version check job at 5:10am. every Monday" > clash
        echo "SHELL=/bin/bash" >> clash
        echo "PATH=/sbin:/bin:/usr/sbin:/usr/bin" >> clash
        echo "10 05 * * 1 root ${CLASH_CONFIG_PATH}/version.check.sh 2> /dev/null" >> clash
        cd -
    fi
}

add_crontab(){
    add_reboot_cron
    add_version_check_cron
}

main(){
    if [ ! -d $CLASH_CONFIG_PATH ];then
        mkdir $CLASH_CONFIG_PATH
    fi
    install_clash
    add_clash_system_service
    add_crontab
    update_iptable_rules
    install_dhcp_server
    exit 0
}

main