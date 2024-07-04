#!/bin/bash
#=================================================
# File name: hook-feeds.sh
# Author: SuLingGG
# Blog: https://mlapp.cn
#=================================================
# Svn checkout packages from immortalwrt's repository

# Set to local feeds
pushd customfeeds/packages
rm -rf net/adguardhome
git clone --depth=1 https://github.com/linkease/nas-packages
rm -rf nas-packages/multimedia
rm -rf nas-packages/network/services/{linkease,quickstart,unishare,webdav2}
rm -rf net/{xray-core,v2ray-core,v2ray-geodata,sing-box}
export packages_feed="$(pwd)"
popd
pushd customfeeds/luci
# git clone --depth=1 https://github.com/jerrykuku/lua-maxminddb.git
# git clone --depth=1 https://github.com/MilesPoupart/luci-app-vssr
# git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall
# git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages
# git clone --depth=1 https://github.com/fw876/helloworld
git clone --depth=1 https://github.com/linkease/nas-packages-luci
git clone --depth=1 https://github.com/sbwml/luci-app-alist
git clone --depth=1 https://github.com/MedyMa/luci-app-adguardhome
rm -rf nas-packages-luci/luci/{luci-app-istorex,luci-app-linkease,luci-app-quickstart,luci-app-unishare,luci-lib-iform}
export luci_feed="$(pwd)"
popd
sed -i '/src-git packages/d' feeds.conf.default
echo "src-link packages $packages_feed" >> feeds.conf.default
sed -i '/src-git luci/d' feeds.conf.default
echo "src-link luci $luci_feed" >> feeds.conf.default

# Update feeds
./scripts/feeds update -a
