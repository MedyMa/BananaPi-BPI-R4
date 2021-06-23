#!/bin/sh
opkg update
opkg install pv
opkg install gzip
cd /mnt/mmcblk0p3
rm -rf artifact openwrt-rockchip*.img.gz openwrt-rockchip*img*
echo -e '\e[92m准备下载升级文件\e[0m'
wget https://github.com/MedyMa/NanoPi-R4S/releases/download/$(date +%Y.%m.%d)-Lean/openwrt-rockchip-armv8-friendlyarm_nanopi-r4s-ext4-sysupgrade.img.gz
if [ -f /mnt/mmcblk0p3/openwrt-rockchip-armv8-friendlyarm_nanopi-r4s-ext4-sysupgrade.img.gz	]; then
	echo -e '\e[92m今天固件已下载，准备解压\e[0m'
else
	echo -e '\e[91m今天的固件还没更新，尝试下载昨天的固件\e[0m'
	wget https://github.com/MedyMa/NanoPi-R4S/releases/download/$(date -d "@$(( $(busybox date +%s) - 86400))" +%Y.%m.%d)-Lean/openwrt-rockchip-armv8-friendlyarm_nanopi-r4s-ext4-sysupgrade.img.gz
	if [ -f /mnt/mmcblk0p3/openwrt-rockchip-armv8-friendlyarm_nanopi-r4s-ext4-sysupgrade.img.gz ]; then
		echo -e '\e[92m昨天的固件已下载，准备解压\e[0m'
	else
		echo -e '\e[91m没找到最新的固件，脚本退出\e[0m'
		exit 1
	fi
fi
cd /mnt/mmcblk0p3
echo -e '\e[92m准备解压镜像文件\e[0m'
pv openwrt-rockchip-armv8-friendlyarm_nanopi-r4s-ext4-sysupgrade.img.gz | gunzip -dc > openwrt-rockchip-armv8-friendlyarm_nanopi-r4s-ext4-sysupgrade.img
if [ -f /mnt/mmcblk0p3/openwrt-rockchip-armv8-friendlyarm_nanopi-r4s-ext4-sysupgrade.img	]; then
	echo -e '\e[92m删除已下载文件\e[0m'
	rm -rf openwrt-rockchip-armv8-friendlyarm_nanopi-r4s-ext4-sysupgrade.img.gz
fi
echo -e '\e[92m开始升级固件\e[0m'
sleep 3s
sysupgrade -v /mnt/mmcblk0p3/openwrt-rockchip-armv8-friendlyarm_nanopi-r4s-ext4-sysupgrade.img