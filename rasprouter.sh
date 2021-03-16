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