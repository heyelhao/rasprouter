#!/bin/bash
# It generates iptable's rules that let all requests of clients and local be handled by CLASH

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

add_iproute_rules(){
    echo "Add ip route rules..."
    ip rule flush table 200
    ip rule add fwmark 1 table 200
    ip route flush table 200
    ip route add local default dev lo table 200
    echo "Done."
}

remove_iptable_rules(){
    iptables -t mangle -D PREROUTING -j CLASH
    iptables -t mangle -F CLASH
    iptables -t mangle -X CLASH
    
    iptables -t nat -D PREROUTING -j CLASH
    iptables -t nat -F CLASH
    iptables -t nat -X CLASH

    iptables -t mangle -D OUTPUT -j CLASH_MASK
    iptables -t mangle -F CLASH_MASK
    iptables -t mangle -X CLASH_MASK
}
add_iptable_client_rules(){
    # LOCAL CLIENTS
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

    iptables -t nat -N CLASH
    iptables -t nat -A CLASH -p udp --dport 53 -j REDIRECT --to-port 7853
    iptables -t nat -A PREROUTING -j CLASH
}

add_iptable_local_rules(){
    # LOCAL MACHINE
    iptables -t mangle -N CLASH_MASK
    iptables -t mangle -A CLASH_MASK -d 0.0.0.0/8 -j RETURN
    iptables -t mangle -A CLASH_MASK -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A CLASH_MASK -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A CLASH_MASK -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A CLASH_MASK -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A CLASH_MASK -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A CLASH_MASK -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A CLASH_MASK -d 240.0.0.0/4 -j RETURN
    iptables -t mangle -A CLASH_MASK -d 255.255.255.255/32 -j RETURN
    iptables -t mangle -A CLASH_MASK -p udp --dport 53 -j REDIRECT --to-port 7853
    iptables -t mangle -A CLASH_MASK -j RETURN -m mark --mark 0xff
    iptables -t mangle -A CLASH_MASK -p udp -j MARK --set-mark 1
    iptables -t mangle -A CLASH_MASK -p tcp -j MARK --set-mark 1
    # REDIRECT OUTPUT CHAIN
    iptables -t mangle -A OUTPUT -j CLASH_MASK
}

add_iptable_rules(){
    echo "Add iptable rules..."
    remove_iptable_rules
    add_iptable_client_rules
    echo "Done."
}

case ${1} in
    "iptable")
        add_iptable_rules
        ;;
    "iproute")
        add_iproute_rules
        ;;
    "all")
        add_iproute_rules
        add_iptable_rules
        ;;
    *)
        echo "Usage ${0} {iptable|iproute|all)"
        ;;
esac
