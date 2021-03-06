#!/bin/bash
# It makes raspbian to be router that lets you access the blocked sites by the clash
# 2021/03/15 Shawn

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

TRUE=0
FALSE=1

HOME_PATH="/home/pi"
CONFIG_PATH="${HOME_PATH}/.config/clash"

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

install_config(){
    echo "Install clash config.yaml..."
    is_newer ./config.yaml $CONFIG_PATH/config.yaml
    if [ $? = $TRUE ]; then
        cp ./config.yaml $CONFIG_PATH/
    fi
    echo "Done."
}

install_country_database(){
    echo "Download country.mmdb for clash..."
    # Download Country.mmdb
    download https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb ./Country.mmdb
    is_newer ./Country.mmdb $CONFIG_PATH/Country.mmdb
    if [ $? = $TRUE ]; then
        cp Country.mmdb $CONFIG_PATH/
    fi
    rm ./Country.mmdb
    echo "Done."
}

install_ui(){
    echo "Download ui(yacd) for clash..."
    # Download ui(yacd)
    download https://github.com/haishanh/yacd/releases/latest/download/yacd.tar.xz ./yacd.tar.xz
    if [ -f $CONFIG_PATH/ui ]; then
        tar -Jcf ./yacd-old.tar.xz $CONFIG_PATH/ui
    fi
    is_newer ./yacd.tar.xz ./yacd-old.tar.xz
    if [ $? = $TRUE ]; then
        tar -Jxf yacd.tar.xz
        mv public $CONFIG_PATH/ui
    fi
    rm yacd.tar.xz yacd-old.tar.xz
    echo "Done."
}

install_second_script(){
    echo "Install second script about clash rules and check for updates..."
    second_file=$CONFIG_PATH/second.sh
    is_newer ./second.sh $second_file
    if [ $? = $TRUE ]; then
        cp ./second.sh $second_file
    fi
    if [ ! -f /etc/network/if-pre-up.d/clash ]; then
        cd /etc/network/if-pre-up.d/
        touch clash
        echo "#!/bin/bash" > ./clash
        echo "${second_file} rule" >> ./clash
        cd - 
    fi
    echo "Done."
    unset second_file
}

install_clash(){
    if [ ! -z $(uname -m |grep 'armv') ]; then
        echo "Download clash..."
        arc_info=$(uname -m |sed 's/ *l.*$//g')
        clash_version=$(curl --silent "https://api.github.com/repos/Dreamacro/clash/releases/latest"|grep '"tag_name"' |sed -E 's/.*"([^"]+)".*/\1/')
        clash_download_url="https://github.com/Dreamacro/clash/releases/latest/download/clash-linux-${arc_info}-${clash_version}.gz"

        download $clash_download_url clash-linux-${arc_info}-${clash_version}.gz
        gzip -d clash-linux-${arc_info}-${clash_version}.gz
        is_newer ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
        if [ $? = $TRUE ]; then
            cp ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
            chmod u+x /usr/local/bin/clash
        fi
        rm ./clash-linux-${arc_info}-${clash_version}
        echo "Done."
        unset arc_info clash_version clash_download_url
    fi
}

add_clash_systemd(){
    echo "Create system service for clash..."
    if [ -z "$(systemctl -a |grep clash.service)" ]; then
        clash_service=/etc/systemd/system/clash.service
        if [ -f $clash_service ]; then
            systemctl disable clash
            rm $clash_service
        fi

        # Generate the systemd configuration file of clash
        touch $clash_service
        echo "[Unit]">>$clash_service
        echo "Description=Clash daemon, A rule-based proxy in Go.">>$clash_service
        echo "After=network.target">>$clash_service
        echo "[Service]">>$clash_service
        echo "Type=simple">>$clash_service
        echo "Restart=always">>$clash_service
        echo "ExecStart=$(which clash) -d ${CONFIG_PATH}">>$clash_service
        echo "[Install]">>$clash_service
        echo "WantedBy=multi-user.target">>$clash_service
        systemctl enable clash
        unset clash_service
    fi
    echo "Done."
}

add_reboot_cron(){
    echo "Adding crontab: OS reboot at 5:30am. everyday."
    echo "# Reboot raspbian OS at 5:30am everyday">>/etc/crontab
    echo "30 05 * * * root /usr/sbin/shutdown -r now">>/etc/crontab
}

add_updates_cron(){
    echo "Add crontab: Check for updates about clash at 5:10am. every Monday."
    cd /etc/cron.d
    if [ ! -f ./clash ]; then
        touch ./clash
        echo "# Run the version check job at 5:10am. every Monday" > ./clash
        echo "SHELL=/bin/bash" >> ./clash
        echo "PATH=/sbin:/bin:/usr/sbin:/usr/bin" >> ./clash
        echo "10 05 * * 1 root ${CONFIG_PATH}/second.sh update 2> /dev/null" >> ./clash
    fi
    cd -
    echo "Done."
}

add_crons(){
    add_updates_cron
}

change_privileges(){
    chgrp -R pi $HOME_PATH
    chown -R pi $HOME_PATH
}

update_router(){
    echo "Configure static gateway and domain name servers..."
    read -p "Please input raspberry-pi router/gateway ip address (eg. 192.168.1.2): " router_ip
    cd /etc/
    if [ ! -f ./dhcpcd.conf.bak ];then
        cp ./dhcpcd.conf ./dhcpcd.conf.bak
    else
        cp ./dhcpcd.conf.bak ./dhcpcd.conf
    fi

    echo "# eth0 static configuration" >>./dhcpcd.conf
    echo "interface eth0" >>./dhcpcd.conf
    echo "static routers=$router_ip" >>./dhcpcd.conf
    echo "static domain_name_servers=$router_ip 1.1.1.1 8.8.8.8" >>./dhcpcd.conf
    echo "Done."
    cd -
    unset router_ip
}

main(){
    echo "Install rasprouter..."
    if [ ! -d $CONFIG_PATH ];then
        mkdir -p $CONFIG_PATH
    fi
    install_config
    install_country_database
    install_ui
    install_second_script
    change_privileges
    update_router

    install_clash
    add_clash_systemd
    add_crons
    echo "Install rasprouter done."
    exit 0
}

main