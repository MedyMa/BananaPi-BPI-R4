#!/bin/bash
#
# Add a feed source
#echo 'src-git moruiris https://github.com/moruiris/openwrt-packages;immortalwrt' >>feeds.conf.default
git clone -b Immortalwrt https://github.com/shidahuilang/openwrt-package ./package/openwrt-packages
git clone --depth=1 https://github.com/fw876/helloworld ./package/openwrt-packages
# Add luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon ./package/openwrt-packages
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config ./package/openwrt-packages
