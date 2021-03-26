#!/bin/bash
# It will periodly update the clash releated files like clash, Country.mmdb
# 2021/03/18 Shawn

TRUE=0
FALSE=1
CLASH_CONFIG_PATH="/etc/clash"
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
    clash_download_url="https://github.com/Dreamacro/clash/releases/latest/download/clash-linux-${arc_info}-${clash_version}.gz"
    cd /tmp
    download $clash_download_url clash-linux-${arc_info}-${clash_version}.gz
    gzip -d clash-linux-${arc_info}-${clash_version}.gz
    is_newer ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
    if [ $? = $TRUE ]; then
        $UPDATED=0
        echo "Updating Clash to the new version..."
        mv /usr/local/bin/clash ./clash-old
        cp ./clash-linux-${arc_info}-${clash_version} /usr/local/bin/clash
        chmod +x /usr/local/bin/clash
        rm ./clash-old
    fi
    rm ./clash-linux-${arc_info}-${clash_version}
    unset arc_info clash_version clash_download_url
    cd -
}

check_country_version(){
    cd /tmp
    download https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb Country.mmdb
    is_newer ./Country.mmdb $CLASH_CONFIG_PATH/Country.mmdb
    if [ $? = $TRUE ]; then
        $UPDATED=0
        echo "Updating Country.mmdb to the new version..."
        mv $CLASH_CONFIG_PATH/Country.mmdb ./Country-old.mmdb
        cp Country.mmdb $CLASH_CONFIG_PATH/
        rm ./Country-old.mmdb
    fi
    rm ./Country.mmdb
    cd -
}

main(){
    echo "Checking clash new version..."
    check_clash_version
    check_country_version
    if [ $UPDATED = $TRUE ]; then
        service clash stop
        service clash start
    fi
    echo "Checking clash new version done."
}

main