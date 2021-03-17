#!/bin/bash
# It makes raspbian to be router that lets you access the blocked sites by the clash
# 2021/03/15 Shawn

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

CLASH_CONFIG_PATH="/etc/clash"

function update_iptable_rules(){
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
}

function get_file_sha256(){
    sha256 $1 |head -c 64
}

function is_newer(){
    if [ ! -f $2 ]; then
        RETURN 0
    else
       [ get_file_sha256 $1 != get_file_sha256 $2 ]
    fi
}

function download_clash(){
    if [ ! -z $(uname -m |grep 'armv') ]; then
        echo "Downloading clash..."
        arc_info=$(uname -m |sed 's/ *l.*$//g')
        clash_version=$(curl --silent "https://api.github.com/repos/Dreamacro/clash/releases/latest"|grep '"tag_name"' |sed -E 's/.*"([^"]+)".*/\1/')
        clash_download_url="https://github.com/Dreamacro/clash/releases/latest/download/clash-linux-${arc_info}-${clash_version}.gz"
        cd /tmp
        wget $clash_download_url
        gzip -d clash-linux-${arc_info}-${clash_version}.gz
        if [ is_newer ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash ]; then
            cp ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
        fi
        echo "Downloading clash configuration files like Country.mmdb, ui(yacd)..."
        if [ ! -d $CLASH_CONFIG_PATH ];then
            mkdir $CLASH_CONFIG_PATH
        fi
        # Download Country.mmdb
        wget https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb
        if [ is_newer ./Country.mmdb $CLASH_CONFIG_PATH/Country.mmdb ]; then
            mv Country.mmdb $CLASH_CONFIG_PATH/
        fi
        # Download ui(yacd)
        wget https://github.com/haishanh/yacd/releases/latest/download/yacd.tar.xz
        if [ -f $CLASH_CONFIG_PATH/ui ]; then
            tar -Jcf ./yacd-old.tar.xz $CLASH_CONFIG_PATH/ui
        fi
        if [ is_newer ./yacd.tar.xz ./yacd-old.tar.xz ];then
            tar -Jxf yacd.tar.xz
            mv public $CLASH_CONFIG_PATH/ui
            rm yacd.tar.xz yacd-old.tar.xz
        fi
        if [ ! -f $CLASH_CONFIG_PATH/config.yaml ]; then
            wget https://raw.githubusercontent.com/erheisw/rasprouter/config.yaml
        fi
        unset arc_info clash_version clash_download_url
        cd -
    fi
}