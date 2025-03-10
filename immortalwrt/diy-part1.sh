#!/bin/bash
#
# Add a feed source
#echo 'src-git moruiris https://github.com/moruiris/openwrt-packages;immortalwrt' >>feeds.conf.default
git clone -b Immortalwrt https://github.com/shidahuilang/openwrt-package ./package/openwrt-packages
rm -rf ./package/openwrt-packages/relevance/alist 
rm -rf ./package/openwrt-packages/relevance/shadowsocks-libev
rm -rf ./package/openwrt-packages/relevance/internet-detector-mod-email
rm -rf ./package/openwrt-packages/luci-app-clouddrive2
rm -rf ./package/openwrt-packages/luci-app-floatip
rm -rf ./package/openwrt-packages/luci-app-nginx-pingos
rm -rf ./package/openwrt-packages/luci-app-syncthing
# Clone community packages to package/community
mkdir package/community
pushd package/community
git clone --depth=1 https://github.com/fw876/helloworld
# Add luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
popd
