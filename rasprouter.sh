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
    # chmod o+w $CONFIG_PATH/config.yaml
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
    # chmod o+w $CONFIG_PATH/Country.mmdb
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
    # chmod o+x $CONFIG_PATH/second.sh
    if [ ! -f /etc/network/if-pre-up.d/clash ]; then
        cd /etc/network/if-pre-up.d/
        touch clash
        echo "#!/bin/bash" > ./clash
        echo "${second_file} --rule" >> ./clash
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
ExecStart=$(which clash) -d ${CONFIG_PATH}
[Install]
WantedBy=multi-user.target" > $clash_service
        fi
        systemctl enable clash
        unset clash_service
    fi
}

add_reboot_cron(){
    echo "Adding crontab: OS reboot at 5:30am. everyday."
    echo "# Reboot raspbian OS at 5:30am everyday">>/etc/crontab
    echo "30 05 * * * root /usr/sbin/shutdown -r now">>/etc/crontab
}

add_version_check_cron(){
    if [ ! -f $CONFIG_PATH/version.check.sh ]; then
        echo "Adding crontab: Version check 5:10am. every Monday."
        cp ./version.check.sh $CONFIG_PATH/version.check.sh
        chmod +x $CONFIG_PATH/version.check.sh
        cd /etc/cron.d
        touch clash
        echo "# Run the version check job at 5:10am. every Monday" > clash
        echo "SHELL=/bin/bash" >> clash
        echo "PATH=/sbin:/bin:/usr/sbin:/usr/bin" >> clash
        echo "10 05 * * 1 root ${CONFIG_PATH}/version.check.sh 2> /dev/null" >> clash
        cd -
    fi
}

add_crontab(){
    add_reboot_cron
    add_version_check_cron
}

config_router(){
    echo "Configurating static gateway and domain name servers..."
    read -p "Please input raspberry-pi router/gateway ip address (eg. 192.168.1.2): " router_ip
    cd /etc/
    if [ ! -f ./dhcpcd.conf.bak ];then
        cp ./dhcpcd.conf ./dhcpcd.conf.bak
    else
        cp ./dhcpcd.conf.bak ./dhcpcd.conf
    fi

    echo "
# eth0 static configuration
interface eth0
static routers=$router_ip
static domain_name_servers=$router_ip 1.1.1.1 8.8.8.8" >> ./dhcpcd.conf
    unset router_ip
}

change_privileges(){
    chgrp -R pi $HOME_PATH
    chown -R pi $HOME_PATH
}

main(){
    if [ ! -d $CONFIG_PATH ];then
        mkdir -p $CONFIG_PATH
    fi
    install_config
    install_country_database
    install_ui
    install_second_script
    change_privileges

    install_clash
    echo "Rasprouter is installed now."
    exit 0
}

main