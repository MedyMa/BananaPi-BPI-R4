#!/bin/bash
#
# Add a feed source
#echo 'src-git moruiris https://github.com/moruiris/openwrt-packages;immortalwrt' >>feeds.conf.default
git clone -b Immortalwrt https://github.com/shidahuilang/openwrt-package ./package/openwrt-packages
git clone --depth=1 https://github.com/fw876/helloworld ./package/openwrt-packages
