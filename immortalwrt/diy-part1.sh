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
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
# merge_package https://github.com/kenzok8/jell jell/luci-app-fan
merge_package https://github.com/DHDAXCW/dhdaxcw-app dhdaxcw-app/luci-app-adguardhome
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/relevance/ddnsto
merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/luci-app-ddnsto
popd

# add luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/v2ray-geodata
rm -rf feeds/packages/net/mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# add luci-app-OpenClash
mkdir package/OpenClash
pushd package/OpenClash
git clone --depth=1  https://github.com/vernesong/OpenClash
git config core.sparsecheckout true
popd

# wireless-regdb modification
# rm -rf package/firmware/wireless-regdb/patches/*.*
# rm -rf package/firmware/wireless-regdb/Makefile
# cp -f $GITHUB_WORKSPACE/patches/filogic/500-tx_power.patch package/firmware/wireless-regdb/patches/500-tx_power.patch
# cp -f $GITHUB_WORKSPACE/patches/filogic/regdb.Makefile package/firmware/wireless-regdb/Makefile
merge_package https://github.com/DHDAXCW/lede-rockchip lede-rockchip/package/wwan
merge_package "-b openwrt-24.10-6.6 https://github.com/padavanonly/immortalwrt-mt798x-6.6" immortalwrt-mt798x-6.6/package/mtk/applications/luci-app-Airpifanctrl
merge_package "-b openwrt-24.10-6.6 https://github.com/padavanonly/immortalwrt-mt798x-6.6" immortalwrt-mt798x-6.6/package/mtk/applications/Airpi-gpio-fan
merge_package "-b openwrt-24.10-6.6 https://github.com/padavanonly/immortalwrt-mt798x-6.6" immortalwrt-mt798x-6.6/package/mtk/applications/mtkhqos_util
./scripts/feeds update -a
