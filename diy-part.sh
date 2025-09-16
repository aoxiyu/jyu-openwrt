#!/bin/bash

# 进入 OpenWrt 目录
cd openwrt

# 设置工作路径变量
WORKPATH=$(pwd)
HOME=$(pwd)/..
CUSTOM_SH=".config"

# 删除部分默认包
echo "删除不需要的默认包..."
rm -rf feeds/luci/applications/luci-app-qbittorrent
rm -rf feeds/luci/applications/luci-app-openclash
rm -rf feeds/luci/themes/luci-theme-argon

# 显示 feeds.conf.default 内容
echo "feeds.conf.default 内容:"
cat feeds.conf.default

# 添加第三方软件包
echo "添加第三方软件包..."
git clone https://github.com/aoxijy/aoxi-package.git -b master package/aoxi-package

# 更新并安装源
echo "更新并安装 feeds..."
./scripts/feeds clean
./scripts/feeds update -a && ./scripts/feeds install -a -f

# 定制默认IP为172.18.18.222
echo "定制默认IP为172.18.18.222..."
NET="package/base-files/files/bin/config_generate"
sed -i 's#192.168.1.1#172.18.18.222#g' $NET

# 取消系统默认密码
echo "取消系统默认密码..."
sed -i 's@.*CYXluq4wUazHjmCDBCqXF*@#&@g' package/lean/default-settings/files/zzz-default-settings

# 增加自己个性名称
echo "增加个性名称..."
sed -i "s/LEDE /GanQuanRu build $(TZ=UTC-8 date "+%Y.%m.%d") @ LEDE /g" package/base-files/files/etc/banner

# 设置默认主题
echo "设置默认主题为argon..."
echo "uci set luci.main.mediaurlbase=/luci-static/argon" >> package/default-settings/files/zzz-default-settings

# 设置网络-旁路由模式
echo "设置旁路由模式..."
cat >> package/base-files/files/etc/uci-defaults/99-custom <<-EOF
#!/bin/sh

# 设置网络-旁路由模式
uci set network.lan.gateway='172.18.18.2'                  # 旁路由设置 IPv4 网关
uci set network.lan.dns='223.5.5.5 119.29.29.29'          # 旁路由设置 DNS
uci set dhcp.lan.ignore='1'                               # 旁路由关闭DHCP功能
uci delete network.lan.type                               # 旁路由桥接模式-禁用
uci set network.lan.delegate='0'                          # 去掉LAN口使用内置的 IPv6 管理
uci set dhcp.@dnsmasq[0].filter_aaaa='0'                  # 禁止解析 IPv6 DNS记录

# 设置防火墙-旁路由模式
uci set firewall.@defaults[0].syn_flood='0'               # 禁用 SYN-flood 防御
uci set firewall.@defaults[0].flow_offloading='0'         # 禁用基于软件的NAT分载
uci set firewall.@defaults[0].flow_offloading_hw='0'      # 禁用基于硬件的NAT分载
uci set firewall.@defaults[0].fullcone='0'                # 禁用 FullCone NAT
uci set firewall.@defaults[0].fullcone6='0'               # 禁用 FullCone NAT6
uci set firewall.@zone[0].masq='1'                        # 启用LAN口 IP 动态伪装

# 旁路IPV6需要全部禁用
uci del network.lan.ip6assign                             # IPV6分配长度-禁用
uci del dhcp.lan.ra                                       # 路由通告服务-禁用
uci del dhcp.lan.dhcpv6                                   # DHCPv6 服务-禁用
uci del dhcp.lan.ra_management                            # DHCPv6 模式-禁用

uci commit dhcp
uci commit network
uci commit firewall

exit 0
EOF

# 设置脚本权限
chmod +x package/base-files/files/etc/uci-defaults/99-custom

# 检查 OpenClash 是否启用编译
echo "检查 OpenClash 配置..."
if ! grep -q "CONFIG_PACKAGE_luci-app-openclash=y" .config; then
  echo "OpenClash 未启用编译"
  # 如果OpenClash未启用，确保删除相关文件
  rm -rf package/luci-app-openclash
  rm -rf feeds/luci/applications/luci-app-openclash
else
  echo "OpenClash 已启用编译，准备下载内核..."
  # 判断系统架构
  arch=$(uname -m)
  case "$arch" in
    x86_64)
      arch="amd64"
      ;;
    aarch64|arm64)
      arch="arm64"
      ;;
    *)
      echo "不支持的架构: $arch，跳过OpenClash内核下载"
      arch=""
      ;;
  esac
  
  if [ -n "$arch" ]; then
    # OpenClash Meta 开始配置内核
    echo "正在执行：为OpenClash下载内核"
    mkdir -p $HOME/clash-core
    mkdir -p files/etc/openclash/core
    cd $HOME/clash-core
    
    # 下载Meta内核
    echo "下载OpenClash Meta内核..."
    wget -q https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-$arch.tar.gz
    if [ $? -eq 0 ]; then
      echo "OpenClash Meta内核压缩包下载成功，开始解压文件"
      tar -zxvf clash-linux-$arch.tar.gz
      if [ -f "$HOME/clash-core/clash" ]; then
        mv -f $HOME/clash-core/clash $WORKPATH/files/etc/openclash/core/clash_meta
        chmod +x $WORKPATH/files/etc/openclash/core/clash_meta
        echo "OpenClash Meta内核配置成功"
      else
        echo "OpenClash Meta内核配置失败"
      fi
    else
      echo "OpenClash Meta内核下载失败"
    fi
    
    # 清理临时文件
    rm -rf $HOME/clash-core
    cd $WORKPATH
  fi
fi

# 设置编译配置
echo "设置编译配置..."

# 编译x64固件:
cat >> .config <<EOF
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_Generic=y
EOF

# 设置固件大小:
cat >> .config <<EOF
CONFIG_TARGET_KERNEL_PARTSIZE=16
CONFIG_TARGET_ROOTFS_PARTSIZE=360
EOF

# 固件压缩:
cat >> .config <<EOF
CONFIG_TARGET_IMAGES_GZIP=y
EOF

# 编译UEFI固件:
cat >> .config <<EOF
CONFIG_EFI_IMAGES=y
EOF

# IPv6支持:
cat >> .config <<EOF
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
CONFIG_PACKAGE_ipv6helper=y
EOF

# 编译PVE/KVM、Hyper-V、VMware镜像以及镜像填充
cat >> .config <<EOF
CONFIG_QCOW2_IMAGES=n
CONFIG_VHDX_IMAGES=n
CONFIG_VMDK_IMAGES=n
CONFIG_TARGET_IMAGES_PAD=y
EOF

# 第三方插件选择:
cat >> .config <<EOF
# CONFIG_PACKAGE_luci-app-oaf=y #应用过滤
CONFIG_PACKAGE_luci-app-openclash=y #OpenClash客户端
CONFIG_PACKAGE_luci-app-nikki=y #nikki 客户端
# CONFIG_PACKAGE_luci-app-serverchan=y #微信推送
# CONFIG_PACKAGE_luci-app-eqos=y #IP限速
# CONFIG_PACKAGE_luci-app-control-weburl=y #网址过滤
# CONFIG_PACKAGE_luci-app-smartdns=y #smartdns服务器
# CONFIG_PACKAGE_luci-app-adguardhome=y #ADguardhome
CONFIG_PACKAGE_luci-app-poweroff=y #关机（增加关机功能）
# CONFIG_PACKAGE_luci-app-argon-config=y #argon主题设置
# CONFIG_PACKAGE_luci-app-autotimeset=y #定时重启系统，网络
# CONFIG_PACKAGE_luci-app-ddnsto=y #小宝开发的DDNS.to内网穿透
# CONFIG_PACKAGE_ddnsto=y #DDNS.to内网穿透软件包
EOF

# ShadowsocksR插件:
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-ssr-plus=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_SagerNet_Core is not set
EOF

# Passwall插件:
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-passwall=y
# CONFIG_PACKAGE_luci-app-passwall2=y
# CONFIG_PACKAGE_naiveproxy=y
CONFIG_PACKAGE_chinadns-ng=y
# CONFIG_PACKAGE_brook=y
CONFIG_PACKAGE_trojan-go=y
CONFIG_PACKAGE_xray-plugin=y
CONFIG_PACKAGE_shadowsocks-rust-sslocal=n
EOF

# Turbo ACC 网络加速:
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-turboacc=y
EOF

# 常用LuCI插件:
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-adbyby-plus=n #adbyby去广告
CONFIG_PACKAGE_luci-app-webadmin=n #Web管理页面设置
CONFIG_PACKAGE_luci-app-ddns=n #DDNS服务
CONFIG_DEFAULT_luci-app-vlmcsd=n #KMS激活服务器
CONFIG_PACKAGE_luci-app-filetransfer=y #系统-文件传输
CONFIG_PACKAGE_luci-app-autoreboot=n #定时重启
CONFIG_PACKAGE_luci-app-upnp=n #通用即插即用UPnP(端口自动转发)
CONFIG_PACKAGE_luci-app-arpbind=n #IP/MAC绑定
CONFIG_PACKAGE_luci-app-accesscontrol=n #上网时间控制
CONFIG_PACKAGE_luci-app-wol=n #网络唤醒
CONFIG_PACKAGE_luci-app-nps=n #nps内网穿透
CONFIG_PACKAGE_luci-app-frpc=y #Frp内网穿透
CONFIG_PACKAGE_luci-app-nlbwmon=n #宽带流量监控
CONFIG_PACKAGE_luci-app-wrtbwmon=n #实时流量监测
CONFIG_PACKAGE_luci-app-haproxy-tcp=n #Haproxy负载均衡
CONFIG_PACKAGE_luci-app-diskman=n #磁盘管理磁盘信息
CONFIG_PACKAGE_luci-app-transmission=n #Transmission离线下载
CONFIG_PACKAGE_luci-app-qbittorrent=n #qBittorrent离线下载
CONFIG_PACKAGE_luci-app-amule=n #电驴离线下载
CONFIG_PACKAGE_luci-app-xlnetacc=n #迅雷快鸟
CONFIG_PACKAGE_luci-app-zerotier=n #zerotier内网穿透
CONFIG_PACKAGE_luci-app-hd-idle=n #磁盘休眠
CONFIG_PACKAGE_luci-app-unblockmusic=n #解锁网易云灰色歌曲
CONFIG_PACKAGE_luci-app-airplay2=n #Apple AirPlay2音频接收服务器
CONFIG_PACKAGE_luci-app-music-remote-center=n #PCHiFi数字转盘遥控
CONFIG_PACKAGE_luci-app-usb-printer=n #USB打印机
CONFIG_PACKAGE_luci-app-sqm=n #SQM智能队列管理
CONFIG_PACKAGE_luci-app-jd-dailybonus=n #京东签到服务
CONFIG_PACKAGE_luci-app-uugamebooster=n #UU游戏加速器
CONFIG_PACKAGE_luci-app-dockerman=n #Docker管理
CONFIG_PACKAGE_luci-app-ttyd=n #ttyd
CONFIG_PACKAGE_luci-app-wireguard=n #wireguard端
#
# VPN相关插件(禁用):
#
CONFIG_PACKAGE_luci-app-v2ray-server=n #V2ray服务器
CONFIG_PACKAGE_luci-app-pptp-server=n #PPTP VPN 服务器
CONFIG_PACKAGE_luci-app-ipsec-vpnd=n #ipsec VPN服务
CONFIG_PACKAGE_luci-app-openvpn-server=n #openvpn服务
CONFIG_PACKAGE_luci-app-softethervpn=n #SoftEtherVPN服务器
#
# 文件共享相关(禁用):
#
CONFIG_PACKAGE_luci-app-minidlna=n #miniDLNA服务
CONFIG_PACKAGE_luci-app-vsftpd=n #FTP 服务器
CONFIG_PACKAGE_luci-app-samba=n #网络共享
CONFIG_PACKAGE_autosamba=n #网络共享
CONFIG_PACKAGE_samba36-server=n #网络共享
EOF

# LuCI主题:
cat >> .config <<EOF
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-theme-edge=n
EOF

# 常用软件包:
cat >> .config <<EOF
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_nano=y
# CONFIG_PACKAGE_screen=y
# CONFIG_PACKAGE_tree=y
# CONFIG_PACKAGE_vim-fuller=y
CONFIG_PACKAGE_wget=y
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_snmpd=y
CONFIG_PACKAGE_libcap=y
CONFIG_PACKAGE_libcap-bin=y
CONFIG_PACKAGE_ip6tables-mod-nat=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_vsftpd=y
CONFIG_PACKAGE_openssh-sftp-server=y
CONFIG_PACKAGE_qemu-ga=y
CONFIG_PACKAGE_autocore-x86=y
EOF

# 其他软件包:
cat >> .config <<EOF
CONFIG_HAS_FPU=y
EOF

echo "diy-part.sh 执行完成"
