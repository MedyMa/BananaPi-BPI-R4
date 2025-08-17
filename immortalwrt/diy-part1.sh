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
git clone --depth=1 https://github.com/DHDAXCW/dhdaxcw-app
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
# merge_package https://github.com/kenzok8/jell jell/luci-app-fan
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/relevance/ddnsto
merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/luci-app-ddnsto
popd

# add luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang
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
rm- rf target/linux/mediatek/files-6.6/drivers/net
merge_package "-b openwrt-24.10-6.6 https://github.com/padavanonly/immortalwrt-mt798x-6.6" immortalwrt-mt798x-6.6/target/linux/mediatek/files-6.6/drivers/net
merge_package "-b openwrt-24.10-6.6 https://github.com/padavanonly/immortalwrt-mt798x-6.6" immortalwrt-mt798x-6.6/package/mtk
rm -rf package/mtk/applications/5g-modem
cp -f $GITHUB_WORKSPACE/patches/filogic/9996-get-rid-of-stupid-mtd-NAND-warnings.patch target/linux/mediatek/patches-6.6/9996-get-rid-of-stupid-mtd-NAND-warnings.patch
cp -f $GITHUB_WORKSPACE/patches/filogic/9997-hnat.patch target/linux/mediatek/patches-6.6/9997-hnat.patch
cp -f $GITHUB_WORKSPACE/patches/filogic/9998-dsa-hnat.patch target/linux/mediatek/patches-6.6/9998-dsa-hnat.patch
cp -f $GITHUB_WORKSPACE/patches/filogic/9999-dsa-exthnat-fix.patch target/linux/mediatek/patches-6.6/9999-dsa-exthnat-fix.patch
