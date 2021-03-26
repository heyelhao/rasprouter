# Rasprouter

基于全家设备科学上网的目的，希望能够在路由设备上实现代理，所以想到了两种方式：

A. 路由设备配置代理

B. 加一个设备，做为旁路由提供代理功能

由于路由增加代理功能，一般需要刷机，并且路由刷机有风险，同时系统可能不稳定，所以放弃[A](#A)方案。刚好我手头有个老旧的树莓派，于是采用方案B。

那么，旁路由如何实现这个功能的呢，大概如下图所示：

- 1 --> 2 所有设备请求发送到树莓派上，树莓派根据代理规则决定是否科学上网

- 3 --> 4 --> 5 非中国IP的请求经代理服务器发送

- 3 --> 6 中国IP的请求直接发送

```Diagram
        Phone/PC/Pad
            |
            1
            |
        -----------                 -------------
       |           |------2------->|             |
       |    WiFi   |    China IP   | RaspberryPi |
       |   路由器   |<-----3--------| ProxySwitch |
       |           |  Non China IP |             |
        -----------                 -------------
        |         |
        |         |                -----------
        4          ------6------->| China Lan |
        |                          -----------
        V
      --------------               ---------------
     | Proxy Server |-----5------>| Non China Lan |
      --------------               ---------------
```

那么在树莓派上需要提供以下功能：

1. 代理功能

2. DNS功能

3. 简单的DHCP功能

根据以上要求，以及搜索的网络资料，决定在运行*Raspbian*系统的树莓派上安装如下软件

- **Clash**提供代理和DNS功能

- **ISC-DHCP-Server**提供DHCP功能

当然，除了这些还需要配置**iptables**规则，如下：

```Shell
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
```

关闭Wi-Fi路由器的DHCP功能，在配置好**Clash**和**DHCP**后，启动这两个服务，然后设备重新连接Wi-Fi，设备即可科学上网。

鉴于相关配置较多，所以将相关操作步骤写成了**Shell**脚本，远程登录树莓派，然后[下载](https://github.com/erheisw/rasprouter/releases)，解压并执行以下命令：

```Shell
sudo sh ./rasprouter.sh
```

## 提示：树莓派最好设置为静态IP，方便相关操作
