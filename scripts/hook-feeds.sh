#!/bin/bash
#=================================================
# File name: hook-feeds.sh
# Author: SuLingGG
# Blog: https://mlapp.cn
#=================================================
# Svn checkout packages from immortalwrt's repository

# Merge_package
function merge_package(){
    repo=`echo $1 | rev | cut -d'/' -f 1 | rev`
    pkg=`echo $2 | rev | cut -d'/' -f 1 | rev`
    # find package/ -follow -name $pkg -not -path "package/openwrt-packages/*" | xargs -rt rm -rf
    git clone --depth=1 --single-branch $1
    [ -d package/openwrt-packages ] || mkdir -p package/openwrt-packages
    mv $2 package/openwrt-packages/
    rm -rf $repo
}

# Set to local feeds
# rm -rf package/wwan/*
pushd customfeeds/packages
rm -rf net/adguardhome
git clone --depth=1 https://github.com/linkease/nas-packages
rm -rf nas-packages/multimedia
rm -rf nas-packages/network/services/{linkease,quickstart,unishare,webdav2}
# rm -rf net/{xray-core,v2ray-core,v2ray-geodata,sing-box}
export packages_feed="$(pwd)"
popd
pushd customfeeds/luci
git clone --depth=1 https://github.com/jerrykuku/lua-maxminddb.git
git clone --depth=1 https://github.com/MilesPoupart/luci-app-vssr
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages
git clone --depth=1 https://github.com/fw876/helloworld
rm -rf helloworld/gn
git clone --depth=1 https://github.com/linkease/nas-packages-luci
git clone --depth=1 https://github.com/sbwml/luci-app-alist
git clone --depth=1 https://github.com/MedyMa/luci-app-adguardhome
rm -rf nas-packages-luci/luci/{luci-app-istorex,luci-app-linkease,luci-app-quickstart,luci-app-unishare,luci-lib-iform}
# merge_package https://github.com/MedyMa/OpenWRT_x86_x64 OpenWRT_x86_x64/package/luci-app-fan
# merge_package https://github.com/DHDAXCW/lede-rockchip lede-rockchip/package/wwan
export luci_feed="$(pwd)"
popd
sed -i '/src-git packages/d' feeds.conf.default
echo "src-link packages $packages_feed" >> feeds.conf.default
sed -i '/src-git luci/d' feeds.conf.default
echo "src-link luci $luci_feed" >> feeds.conf.default

# Update feeds
./scripts/feeds update -a
