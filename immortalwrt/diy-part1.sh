#!/bin/bash
#
# Add a feed source
#echo 'src-git moruiris https://github.com/moruiris/openwrt-packages;immortalwrt' >>feeds.conf.default
git clone -b immortalwrt https://github.com/moruiris/openwrt-packages ./package/openwrt-packages
