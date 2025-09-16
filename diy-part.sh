#!/bin/bash

echo "执行自定义配置..."

# 进入OpenWrt目录
cd openwrt

# 添加自定义软件源
echo "src-git custom https://github.com/custom/packages.git" >> feeds.conf.default

# 添加自定义包
echo "CONFIG_PACKAGE_custom-package=y" >> .config

# 其他自定义操作
echo "自定义配置完成"
