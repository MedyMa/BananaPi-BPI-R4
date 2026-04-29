#!/bin/bash

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

rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config

# Clone community packages to package/community
mkdir package/community
pushd package/community
git clone --depth=1 https://github.com/fw876/helloworld
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
git clone --depth=1 https://github.com/Siriling/5G-Modem-Support
# merge_package https://github.com/kenzok8/jell jell/luci-app-fan
merge_package https://github.com/DHDAXCW/dhdaxcw-app dhdaxcw-app/luci-app-adguardhome
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages-luci" nas-packages-luci/luci/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages" nas-packages/network/services/ddnsto
sed -i 's/^PKG_SOURCE_DATE:=.*/PKG_SOURCE_DATE:=4.0.7/' package/openwrt-packages/ddnsto/Makefile
sed -i 's/^PKG_HASH:=.*/PKG_HASH:=425cdb809f06e805e481e772e168309df44c591205be7f72f347f61c4200b42b/' package/openwrt-packages/ddnsto/Makefile
popd

# add luci-app-mosdns
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# add luci-app-OpenClash
mkdir package/OpenClash
pushd package/OpenClash
git clone --depth=1  https://github.com/vernesong/OpenClash
git config core.sparsecheckout true
popd

# wireless-regdb modification
rm -rf package/firmware/wireless-regdb/patches/*.*
rm -rf package/firmware/wireless-regdb/Makefile
cp -f $GITHUB_WORKSPACE/patches/filogic/500-tx_power.patch package/firmware/wireless-regdb/patches
cp -f $GITHUB_WORKSPACE/patches/filogic/regdb.Makefile package/firmware/wireless-regdb/Makefile
rm -rf package/network/config/wifi-scripts
rm -rf package/firmware/wireless-regdb
pushd  package/network/config
merge_package "-b openwrt-24.10 https://github.com/immortalwrt/immortalwrt" immortalwrt/package/network/config/wifi-scripts
popd
pushd  package/firmware
merge_package "-b openwrt-24.10 https://github.com/immortalwrt/immortalwrt" immortalwrt/package/firmware/wireless-regdb
popd
# cp -f $GITHUB_WORKSPACE/patches/filogic/lvts_enable.patch target/linux/mediatek/patches-6.6/lvts_enable.patch
