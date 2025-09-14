#!/bin/sh
# 检查pre_install目录是否存在且包含文件
if [ -n "$(ls /etc/pre_install 2>/dev/null)" ]; then
    opkg install /etc/pre_install/*.ipk --force-depends # 使用opkg安装所有ipk，--force-depends可选，用于强制解决依赖
    rm -rf /etc/pre_install # 安装完成后删除目录和残留的ipk
fi
exit 0 # 必须返回0，表示脚本成功执行
