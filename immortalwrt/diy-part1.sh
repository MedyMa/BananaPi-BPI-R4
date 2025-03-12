#!/bin/bash
#
# Add a feed source
#echo 'src-git moruiris https://github.com/moruiris/openwrt-packages;immortalwrt' >>feeds.conf.default
#  Luci packages
git clone -b Immortalwrt https://github.com/shidahuilang/openwrt-package ./package/openwrt-packages
rm -rf ./package/openwrt-packages/relevance/alist 
rm -rf ./package/openwrt-packages/relevance/shadowsocks-libev
rm -rf ./package/openwrt-packages/relevance/internet-detector-mod-email
rm -rf ./package/openwrt-packages/luci-app-clouddrive2
rm -rf ./package/openwrt-packages/luci-app-floatip
rm -rf ./package/openwrt-packages/luci-app-nginx-pingos
rm -rf ./package/openwrt-packages/luci-app-syncthing
rm -rf ./package/openwrt-packages/luci-app-adguardhome
rm -rf ./package/openwrt-packages/relevance/adguardhome

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
rm -rf packege/base-files
pushd package
merge_package "-b openwrt-24.10 https://github.com/openwrt/openwrt" openwrt/package/base-files
popd

# Clone community packages to package/community
mkdir package/community
pushd package/community
git clone --depth=1 https://github.com/fw876/helloworld
# Add luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
merge_package https://github.com/kenzok8/jell jell/luci-app-fan
merge_package https://github.com/kenzok8/jell jell/adguardhome
merge_package https://github.com/kenzok8/jell jell/luci-app-adguardhome
merge_package https://github.com/kenzok8/jell jell/luci-app-serverchan
merge_package https://github.com/DHDAXCW/lede-rockchip lede-rockchip/package/wwan
merge_package "-b openwrt-24.10 https://github.com/openwrt/openwrt" openwrt/package/base-files
popd
