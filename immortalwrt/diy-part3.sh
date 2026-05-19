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

patch_makefile_dep() {
    local file_path="$1"
    local old_text="$2"
    local new_text="$3"

    [ -f "$file_path" ] || return 0
    grep -qF "$old_text" "$file_path" || return 0
    sed -i "s|$old_text|$new_text|g" "$file_path"
}

sparse_checkout_copy() {
    local repo_url="$1"
    local repo_branch="$2"
    local source_path="$3"
    local dest_path="$4"
    local checkout_dir="$5"
    rm -rf "$checkout_dir"
    git clone --depth=1 --filter=blob:none --sparse -b "$repo_branch" "$repo_url" "$checkout_dir"
    git -C "$checkout_dir" sparse-checkout set "$source_path"

    rm -rf "$dest_path"
    mkdir -p "$(dirname "$dest_path")"
    cp -a "$checkout_dir/$source_path" "$dest_path"
    rm -rf "$checkout_dir"
}


rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-modemband
rm -rf feeds/luci/applications/luci-app-adguardhome
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
# Clone community packages to package/community
mkdir -p package/community
pushd package/community
git clone --depth=1 https://github.com/fw876/helloworld
# rm -rf helloworld/{naiveproxy,shadowsocks-libev,shadowsocksr-libev,shadow-tls,simple-obfs,tcping,tuic-client,v2ray-plugin,xray-core,xray-plugin}
rm -rf helloworld/{naiveproxy}
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
git clone --depth=1 https://github.com/1522042029/luci-app-socat
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-fan
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-sfp-status
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-modemband
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages-luci" nas-packages-luci/luci/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages" nas-packages/network/services/ddnsto
popd

# Import the MTK vendor 6.6 package tree that is not shipped in ImmortalWrt openwrt-24.10.
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    package/mtk \
    package/mtk \
    vendor-mtk

# datconf is selected by the MT7988 defconfig and expects its vendor tarball to
# already exist under dl/ because the package Makefile has no source URL.
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    dl/datconf-757f9679.tar.bz2 \
    dl/datconf-757f9679.tar.bz2 \
    vendor-mtk-dl

# MTK HNAT is not present in the upstream 24.10 mediatek target, but the
# imported MTK WiFi/WARP stack selects and depends on it.
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat \
    vendor-mtk-hnat
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/files-6.6/include/net/ra_nat.h \
    target/linux/mediatek/files-6.6/include/net/ra_nat.h \
    vendor-mtk-hnat-header
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-2713-net-ethernet-mtk_eth_soc-refactor-SER-monitor.patch \
    target/linux/mediatek/patches-6.6/999-2713-net-ethernet-mtk_eth_soc-refactor-SER-monitor.patch \
    vendor-mtk-hnat-patch-2713
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-2741-mtkhnat-add-support-for-virtual-interface-a.patch \
    target/linux/mediatek/patches-6.6/999-2741-mtkhnat-add-support-for-virtual-interface-a.patch \
    vendor-mtk-hnat-patch-2741
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-2742-mtkhnat-tnl-interface-offload-check.patch.patch \
    target/linux/mediatek/patches-6.6/999-2742-mtkhnat-tnl-interface-offload-check.patch.patch \
    vendor-mtk-hnat-patch-2742
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-2743-mtkhnat-ipv6-fix-pskb-expand-head-limitatio.patch \
    target/linux/mediatek/patches-6.6/999-2743-mtkhnat-ipv6-fix-pskb-expand-head-limitatio.patch \
    vendor-mtk-hnat-patch-2743
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-2745-mtkhnat-add-mtkhnat-driver-support.patch \
    target/linux/mediatek/patches-6.6/999-2745-mtkhnat-add-mtkhnat-driver-support.patch \
    vendor-mtk-hnat-patch-2745
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-2746-mtkhnat-add-support-ppe-flow-check-interrupt.patch \
    target/linux/mediatek/patches-6.6/999-2746-mtkhnat-add-support-ppe-flow-check-interrupt.patch \
    vendor-mtk-hnat-patch-2746
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-2747-crypto-eth-inline.patch \
    target/linux/mediatek/patches-6.6/999-2747-crypto-eth-inline.patch \
    vendor-mtk-hnat-patch-2747-crypto
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-2747-net-ethernet-mtk_eth_soc-add-proprietary-SER-flow.patch \
    target/linux/mediatek/patches-6.6/999-2747-net-ethernet-mtk_eth_soc-add-proprietary-SER-flow.patch \
    vendor-mtk-hnat-patch-2747-ser
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-3020-flow-offload-add-mtkhnat-macvlan-support.patch \
    target/linux/mediatek/patches-6.6/999-3020-flow-offload-add-mtkhnat-macvlan-support.patch \
    vendor-mtk-hnat-patch-3020
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/999-3007-net-ethernet-mtk_ppe-add-roaming-handler.patch \
    target/linux/mediatek/patches-6.6/999-3007-net-ethernet-mtk_ppe-add-roaming-handler.patch \
    vendor-mtk-hnat-patch-3007
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/9991-dsa-hnat.patch \
    target/linux/mediatek/patches-6.6/9991-dsa-hnat.patch \
    vendor-mtk-hnat-patch-9991
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/9992-dsa-exthnat-fix.patch \
    target/linux/mediatek/patches-6.6/9992-dsa-exthnat-fix.patch \
    vendor-mtk-hnat-patch-9992
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/9996-ext-hnat.patch \
    target/linux/mediatek/patches-6.6/9996-ext-hnat.patch \
    vendor-mtk-hnat-patch-9996
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/9999-reset.patch \
    target/linux/mediatek/patches-6.6/9999-reset.patch \
    vendor-mtk-hnat-patch-9999
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    target/linux/mediatek/patches-6.6/99999-hnat-extdevice-fix-fdberr.patch \
    target/linux/mediatek/patches-6.6/99999-hnat-extdevice-fix-fdberr.patch \
    vendor-mtk-hnat-patch-99999

if ! grep -q 'KernelPackage/mediatek_hnat' target/linux/mediatek/modules.mk; then
cat >> target/linux/mediatek/modules.mk <<'EOF'

define KernelPackage/mediatek_hnat
    SUBMENU:=Network Devices
    TITLE:=MediaTek hardware NAT support
    DEPENDS:=@TARGET_mediatek +kmod-nf-conntrack +kmod-ipt-nat
    KCONFIG:=CONFIG_NET_MEDIATEK_HNAT
    FILES:=$(LINUX_DIR)/drivers/net/ethernet/mediatek/mtk_hnat/mtkhnat.ko
    AUTOLOAD:=$(call AutoProbe,mtkhnat)
endef

define KernelPackage/mediatek_hnat/description
    MediaTek hardware NAT support for the NETSYS/PPE offload path.
endef

$(eval $(call KernelPackage,mediatek_hnat))
EOF
fi

# The current 24.10-based tree lacks the xcrypt package block that defines libcrypt-compat.
sparse_checkout_copy \
    https://github.com/immortalwrt/immortalwrt \
    openwrt-25.12 \
    package/libs/xcrypt \
    package/libs/xcrypt \
    immortalwrt-core

# Restore ImmortalWrt's status overview helpers and override tempinfo for mt_wifi7.
sparse_checkout_copy \
    https://github.com/immortalwrt/immortalwrt \
    openwrt-24.10 \
    package/emortal/autocore \
    package/emortal/autocore \
    immortalwrt-autocore
cp -f $GITHUB_WORKSPACE/scripts/tempinfo package/emortal/autocore/files/tempinfo
chmod 0755 package/emortal/autocore/files/tempinfo

# add luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# add luci-app-OpenClash
mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash
git config core.sparsecheckout true
popd

# wireless-regdb modification
# rm -rf package/firmware/wireless-regdb/patches/*.*
# rm -rf package/firmware/wireless-regdb/Makefile
# cp -f $GITHUB_WORKSPACE/patches/filogic/500-tx_power.patch package/firmware/wireless-regdb/patches/500-tx_power.patch
# cp -f $GITHUB_WORKSPACE/patches/filogic/regdb.Makefile package/firmware/wireless-regdb/Makefile

# BPi-R4 SFP can fall back to a broken link on both 24.10 and 25.12
# when the USXGMII PCS polarity is left at the default board-agnostic setting.
if [ -d target/linux/mediatek/patches-6.12 ]; then
    cp -f $GITHUB_WORKSPACE/patches/filogic/995-bpi-r4-sfp-usxgmii-polarity.patch \
        target/linux/mediatek/patches-6.12/995-arm64-dts-mediatek-mt7988a-bpi-r4-fix-usxgmii-polarity.patch
elif [ -d target/linux/mediatek/patches-6.6 ]; then
    cp -f $GITHUB_WORKSPACE/patches/filogic/995-bpi-r4-sfp-usxgmii-polarity-24.10.patch \
        target/linux/mediatek/patches-6.6/995-arm64-dts-mediatek-mt7988a-bpi-r4-fix-usxgmii-polarity.patch
fi

# Some BPi-R4 SFP links come up without carrier until they are retrained once.
mkdir -p target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface   
cp -f $GITHUB_WORKSPACE/patches/filogic/99-bpi-r4-sfp-retrain \
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/99-bpi-r4-sfp-retrain
chmod 0755 target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/99-bpi-r4-sfp-retrain
    
# Shrink the BPI-R4 U-Boot autoboot wait so boot time is not dominated by a 30s delay.
patch_makefile_dep \
    package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch \
    'CONFIG_BOOTDELAY=30' \
    'CONFIG_BOOTDELAY=10'
    
./scripts/feeds update -a
