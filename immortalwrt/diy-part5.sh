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
    local perl_status

    [ -f "$file_path" ] || return 0
    grep -qF "$old_text" "$file_path" || return 0

    PATCH_OLD_TEXT="$old_text" PATCH_NEW_TEXT="$new_text" \
        perl -0pi -e 'BEGIN { $old = $ENV{"PATCH_OLD_TEXT"}; $new = $ENV{"PATCH_NEW_TEXT"}; }
            $count = s/\Q$old\E/$new/g;
            END { exit($count > 0 ? 0 : 2); }' "$file_path"
    perl_status=$?

    [ "$perl_status" -eq 0 ] || {
        echo "Failed to apply literal patch to $file_path" >&2
        return "$perl_status"
      }
}

remove_patch_if_present() {
    local patch_path="$1"

    [ -f "$patch_path" ] || return 0
    rm -f "$patch_path"
}

apply_bpi_r4_sfp_patch_experiment() {
    local patch_dir="target/linux/mediatek/patches-6.6"
    local mode="${BPI_R4_SFP_PATCH_EXPERIMENT:-keep}"

    [ -d "$patch_dir" ] || return 0

    case "$mode" in
        keep)
            echo "BPI-R4 SFP patch experiment: keep vendor timing patches"
            ;;
        drop-2702)
            echo "BPI-R4 SFP patch experiment: removing 999-2702 only"
            remove_patch_if_present "$patch_dir/999-2702-net-ethernet-mtk_eth_soc-revise-xgmac-force-mode.patch"
            ;;
        drop-2602-2701-2702)
            echo "BPI-R4 SFP patch experiment: removing 999-2602, 999-2701 and 999-2702"
            remove_patch_if_present "$patch_dir/999-2602-net-pcs-mtk_usxgmii-add-pextp-reset.patch"
            remove_patch_if_present "$patch_dir/999-2701-net-ethernet-mtk_eth_soc-remove-pextp-reset.patch"
            remove_patch_if_present "$patch_dir/999-2702-net-ethernet-mtk_eth_soc-revise-xgmac-force-mode.patch"
            ;;
        drop-2601-2602-2701-2702)
            echo "BPI-R4 SFP patch experiment: removing 999-2601, 999-2602, 999-2701 and 999-2702"
            remove_patch_if_present "$patch_dir/999-2601-net-pcs-mtk-lynxi-add-pextp-reset.patch"
            remove_patch_if_present "$patch_dir/999-2602-net-pcs-mtk_usxgmii-add-pextp-reset.patch"
            remove_patch_if_present "$patch_dir/999-2701-net-ethernet-mtk_eth_soc-remove-pextp-reset.patch"
            remove_patch_if_present "$patch_dir/999-2702-net-ethernet-mtk_eth_soc-revise-xgmac-force-mode.patch"
            ;;
        *)
            echo "Unknown BPI_R4_SFP_PATCH_EXPERIMENT mode: $mode" >&2
            return 1
            ;;
    esac
}

rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-modemband
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}

# Clone community packages to package/community
mkdir -p package/community
pushd package/community
git clone --depth=1 https://github.com/fw876/helloworld
# rm -rf helloworld/{naiveproxy,shadowsocks-libev,shadowsocksr-libev,shadow-tls,simple-obfs,tcping,tuic-client,v2ray-plugin,xray-core,xray-plugin}
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
[ -f openwrt-passwall-packages/haproxy/Makefile ] && sed -i '/^[[:space:]]*ADDON+=USE_QUIC=1$/d' openwrt-passwall-packages/haproxy/Makefile
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
[ -f OpenWrt-nikki/nikki/Makefile ] && perl -0pi -e 's/define Build\/Compile\r?\n\r?\nendef/define Build\/Compile\n\nendef\n\ndefine Build\/InstallDev\n\nendef/' OpenWrt-nikki/nikki/Makefile
# rm -rf OpenWrt-nikki/{mihomo-meta,mihomo-alpha}
git clone --depth=1 https://github.com/1522042029/luci-app-socat
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
# git clone --depth=1 https://github.com/Siriling/5G-Modem-Support
# merge_package https://github.com/DHDAXCW/dhdaxcw-app dhdaxcw-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-fan
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-sfp-status
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-modemband
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
# merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/relevance/ddnsto
# merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages-luci" nas-packages-luci/luci/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages" nas-packages/network/services/ddnsto
popd

# The current 24.10-based tree lacks the xcrypt package block that defines libcrypt-compat.
git clone --depth=1 --filter=blob:none --sparse -b openwrt-25.12 https://github.com/immortalwrt/immortalwrt.git immortalwrt-core
git -C immortalwrt-core sparse-checkout set package/libs/xcrypt
mkdir -p package/libs
rm -rf package/libs/xcrypt
cp -a immortalwrt-core/package/libs/xcrypt package/libs/
rm -rf immortalwrt-core

# Restore ImmortalWrt's status overview helpers and override tempinfo for mt_wifi7.
git clone --depth=1 --filter=blob:none --sparse -b openwrt-24.10 https://github.com/immortalwrt/immortalwrt.git immortalwrt-autocore
git -C immortalwrt-autocore sparse-checkout set package/emortal/autocore
mkdir -p package/emortal
rm -rf package/emortal/autocore
cp -a immortalwrt-autocore/package/emortal/autocore package/emortal/
cp -f $GITHUB_WORKSPACE/scripts/tempinfo package/emortal/autocore/files/tempinfo
chmod 0755 package/emortal/autocore/files/tempinfo
rm -rf immortalwrt-autocore


# add luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# add luci-app-OpenClash
mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1  https://github.com/vernesong/OpenClash
git config core.sparsecheckout true
popd

# wireless-regdb modification
# rm -rf package/firmware/wireless-regdb/patches/*.*
# rm -rf package/firmware/wireless-regdb/Makefile
# cp -f $GITHUB_WORKSPACE/patches/filogic/500-tx_power.patch package/firmware/wireless-regdb/patches/500-tx_power.patch
# cp -f $GITHUB_WORKSPACE/patches/filogic/regdb.Makefile package/firmware/wireless-regdb/Makefile
# merge_package "-b openwrt-24.10-6.6 https://github.com/padavanonly/immortalwrt-mt798x-6.6" immortalwrt-mt798x-6.6/package/mtk/applications/mtkhqos_util

# BPi-R4 SFP on openwrt-24.10 can still need an explicit USXGMII RX polarity hint.
cp -f $GITHUB_WORKSPACE/patches/filogic/995-bpi-r4-sfp-usxgmii-polarity-24.10.patch \
    target/linux/mediatek/patches-6.6/995-arm64-dts-mediatek-mt7988a-bpi-r4-fix-usxgmii-polarity.patch

# Vendor mt7988a.dtsi still leaves LVTS disabled, which hides CPU thermal_zone0.
cp -f $GITHUB_WORKSPACE/patches/filogic/lvts_enable.patch \
    target/linux/mediatek/patches-6.6/996-arm64-dts-mediatek-mt7988a-enable-lvts.patch

# Retry BPi-R4 SFP links once after netifd brings the device up.
mkdir -p target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface
cp -f $GITHUB_WORKSPACE/patches/filogic/99-bpi-r4-sfp-retrain \
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/99-bpi-r4-sfp-retrain
chmod 0755 target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/99-bpi-r4-sfp-retrain

./scripts/feeds update -a

# openwrt-24.10 compatibility fixes for floating packages feed metadata.
patch_makefile_dep \
    feeds/packages/lang/python/python-ubus/Makefile \
    'PKG_BUILD_DEPENDS:=python-setuptools/host' \
    'PKG_BUILD_DEPENDS:=python3/host'
patch_makefile_dep \
    package/feeds/packages/python-ubus/Makefile \
    'PKG_BUILD_DEPENDS:=python-setuptools/host' \
    'PKG_BUILD_DEPENDS:=python3/host'

patch_makefile_dep \
    feeds/packages/admin/zabbix/Makefile \
    'libnetsnmp-ssl' \
    'libnetsnmp'
patch_makefile_dep \
    package/feeds/packages/zabbix/Makefile \
    'libnetsnmp-ssl' \
    'libnetsnmp'
    
# Shrink the BPI-R4 U-Boot autoboot wait so boot time is not dominated by a 30s delay.
patch_makefile_dep \
    package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch \
    'CONFIG_BOOTDELAY=30' \
    'CONFIG_BOOTDELAY=10'

    
./scripts/feeds install -a
