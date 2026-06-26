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

apply_workspace_patch() {
    local patch_file="$1"

    [ -f "$patch_file" ] || return 0

    if git apply --recount --ignore-space-change --ignore-whitespace --reverse --check "$patch_file" >/dev/null 2>&1; then
        return 0
    fi

    git apply --recount --ignore-space-change --ignore-whitespace "$patch_file"
}

install_kernel_patch() {
    local patch_file="$1"
    local patch_name="$2"
    local patch_dir="target/linux/mediatek/patches-6.6"
    local target_patch="$patch_dir/$patch_name"

    [ -f "$patch_file" ] || return 0
    [ -d "$patch_dir" ] || return 0

    if [ -f "$target_patch" ] && cmp -s "$patch_file" "$target_patch"; then
        return 0
    fi

    install -m 0644 "$patch_file" "$target_patch"
}

install_sfp_warm_reboot_patches() {
    local workspace_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local patch_root="$workspace_root/patches/filogic/sfp"
    local patch_name

    [ -d "$patch_root" ] || return 0

    for patch_name in \
        999-2753-net-phy-sfp-support-additional-RollBall-modules.patch \
        999-2754-net-phy-sfp-support-shared-mod-def0-gpio.patch \
        999-2764-net-phy-sfp-add-some-FS-copper-SFP-fixes.patch \
        999-2765-net-phy-sfp-add-some-checksum-fail-SFP-war.patch \
        999-2769-net-phy-aquantia-add-software-reset-to-aqr107_probe.patch
    do
        install_kernel_patch "$patch_root/$patch_name" "$patch_name"
    done
}

create_aqr10g_phy_fw_package() {
    local pkg_dir="package/kernel/aqr10g-phy-fw"

    mkdir -p "$pkg_dir"
    cat > "$pkg_dir/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=aqr10g-phy-fw
PKG_RELEASE:=1
PKG_LICENSE:=LicenseRef-Redistributable
PKG_MAINTAINER:=BananaPi-R4 community

include $(INCLUDE_DIR)/package.mk

define Package/aqr10g-phy-fw
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=Aquantia AQR113C/CUX3410 10G PHY firmware
endef

define Package/aqr10g-phy-fw/description
  Firmware blobs referenced by the MT7988 AQR113C and CUX3410 DTS
  overlays. They allow the Aquantia driver to reload firmware after a
  software reset, which is needed for reliable warm reboot recovery.
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	wget -qO $(PKG_BUILD_DIR)/Rhe-05.06-Candidate9-AQR_Mediatek_23B_P5_ID45824_LCLVER1.cld \
		https://raw.githubusercontent.com/shiyu1314/immortalwrt-mt798x-6.12/25.12-dev/package/kernel/aqr10g-phy-fw/files/Rhe-05.06-Candidate9-AQR_Mediatek_23B_P5_ID45824_LCLVER1.cld
	wget -qO $(PKG_BUILD_DIR)/AQR-G4_v5.7.0-AQR_EVB_Generic_X3410_StdCfg_MDISwap_USX_ID46316_VER2148.cld \
		https://raw.githubusercontent.com/shiyu1314/immortalwrt-mt798x-6.12/25.12-dev/package/kernel/aqr10g-phy-fw/files/AQR-G4_v5.7.0-AQR_EVB_Generic_X3410_StdCfg_MDISwap_USX_ID46316_VER2148.cld
	echo "19d73393d575fbe4018c1685fbdea2ae6fb59be3c995f608920a417c7e3f8d1c  $(PKG_BUILD_DIR)/Rhe-05.06-Candidate9-AQR_Mediatek_23B_P5_ID45824_LCLVER1.cld" | sha256sum -c
	echo "1c9a67faffe50da1a0efa374ec084a956b6ec64ca9d97d3ad6b1a8708d490a44  $(PKG_BUILD_DIR)/AQR-G4_v5.7.0-AQR_EVB_Generic_X3410_StdCfg_MDISwap_USX_ID46316_VER2148.cld" | sha256sum -c
endef

define Build/Compile
endef

define Package/aqr10g-phy-fw/install
	$(INSTALL_DIR) $(1)/lib/firmware
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/*.cld $(1)/lib/firmware/
endef

$(eval $(call BuildPackage,aqr10g-phy-fw))
EOF
}

rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-modemband
rm -rf package/mtk/applications/luci-app-turboacc-mtk
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}

# Clone community packages to package/community
mkdir -p package/community
pushd package/community
git clone --depth=1 -b dev https://github.com/fw876/helloworld
# rm -rf helloworld/{naiveproxy,shadowsocks-libev,shadowsocksr-libev,shadow-tls,simple-obfs,tcping,tuic-client,v2ray-plugin,xray-core,xray-plugin}
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
[ -f openwrt-passwall-packages/haproxy/Makefile ] && sed -i '/^[[:space:]]*ADDON+=USE_QUIC=1$/d' openwrt-passwall-packages/haproxy/Makefile
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
[ -f OpenWrt-nikki/nikki/Makefile ] && perl -0pi -e 's/define Build\/Compile\r?\n\r?\nendef/define Build\/Compile\n\nendef\n\ndefine Build\/InstallDev\n\nendef/' OpenWrt-nikki/nikki/Makefile
git clone --depth=1 https://github.com/1522042029/luci-app-socat
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-fan
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-modemband
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-sfp-status
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-turboacc-mtk
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/ddnsto
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/luci-app-ddnsto
popd

# add luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

create_aqr10g_phy_fw_package

# BPI-R4 SFP warm reboot recovery: allow shared MOD_DEF0 probing, extend
# copper-module quirks, and force Aquantia AQR/CUX PHY software reset on probe.
install_sfp_warm_reboot_patches

# add luci-app-OpenClash
mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1  https://github.com/vernesong/OpenClash
git config core.sparsecheckout true
popd

./scripts/feeds update -a

# Fix non-deterministic PKG_MIRROR_HASH in helloworld/shadowsocks-libev
patch_makefile_dep \
    package/community/helloworld/shadowsocks-libev/Makefile \
    'PKG_MIRROR_HASH:=b3898ad0a557bc8b0bbb2f3888101d461944239b0b7d4d4c6f164d73694a4595' \
    'PKG_MIRROR_HASH:=skip'

# shadowsocksr-libev: replace brittle LTO with no-lto
[ -f package/community/openwrt-passwall-packages/shadowsocksr-libev/Makefile ] && {
    sed -i '/^[[:space:]]*TARGET_CFLAGS += -flto$/c\PKG_BUILD_FLAGS+=no-lto' \
        package/community/openwrt-passwall-packages/shadowsocksr-libev/Makefile
    patch_makefile_dep \
        package/community/openwrt-passwall-packages/shadowsocksr-libev/Makefile \
        '146fa4511a52da2aaa1e11ea0294cfb450e62643156c5da3b10e037ef43961f6' \
        'skip'
}

# GCC 14 + musl fortify workaround for mbedtls
if ! grep -q '_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile; then
    if grep -q '\$(if \$(findstring cortex-a53,\$(CONFIG_CPU_TYPE)),-march=armv8-a)' package/libs/mbedtls/Makefile; then
        sed -i '/$(if $(findstring cortex-a53,$(CONFIG_CPU_TYPE)),-march=armv8-a)/a TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile
  else
    echo 'TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' >> package/libs/mbedtls/Makefile
  fi
fi

# Search multiple path variants: base package dir, feeds/base, and the feeds-installed symlink target.
_purge_libcrypt_compat() {
    local pattern='+USE_GLIBC:libcrypt-compat'
    local paths=(
        package/utils/busybox/Makefile
        package/network/services/dropbear/Makefile
        package/libs/libpcap/Makefile
        package/network/services/ppp/Makefile
        package/system/rpcd/Makefile
        package/network/services/uhttpd/Makefile
    )
    # Alternative locations after feeds update/install.
    # The base feed may preserve the full "package/" prefix or strip it.
    for basedir in feeds/base package/feeds/base; do
        for pfx in '' 'package/'; do
            paths+=(
                "${pfx}utils/busybox/Makefile"
                "${pfx}network/services/dropbear/Makefile"
                "${pfx}libs/libpcap/Makefile"
                "${pfx}network/services/ppp/Makefile"
                "${pfx}system/rpcd/Makefile"
                "${pfx}network/services/uhttpd/Makefile"
            )
        done
    done
    for f in "${paths[@]}"; do
        patch_makefile_dep "$f" "$pattern" ''
    done
}

_purge_libcrypt_compat

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

patch_makefile_dep \
    package/emortal/autocore/Makefile \
    '+(TARGET_mediatek||TARGET_mvebu):mhz' \
    '+(TARGET_mediatek||TARGET_mvebu):mhz \
    +TARGET_mediatek:wireless-tools'

[ -d target/linux/mediatek/files-6.6 ] && {
	# Enable LVTS thermal sensor
	sed -i '/lvts: lvts@1100a000 {/,/^[[:space:]]*};/ { /status = "disabled";/d; }' \
		target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7988a.dtsi

	# MDIO drive 8mA -> 10mA for AQR113C 10G PHY (MTK 1010)
	sed -i '/groups = "mdc_mdio0";/{N; s/drive-strength = <MTK_DRIVE_8mA>/drive-strength = <MTK_DRIVE_10mA>/}' \
		target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7988a.dtsi

	# Keep the BPI-R4 SFP I2C mux from leaving an SFP channel selected across
	# idle periods. This helps warm-reboot SFP reprobe reliability.
	for dts in \
		mt7988a-bananapi-bpi-r4.dtsi \
		mt7988a-bananapi-bpi-r4-pro.dts
	do
		dts_path="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/$dts"
		[ -f "$dts_path" ] && ! grep -q 'i2c-mux-idle-disconnect;' "$dts_path" && \
			sed -i '/compatible = "nxp,pca9545";/a\
		i2c-mux-idle-disconnect;' "$dts_path"
	done

	# Do not force mediatek,pnswap-rx on BPI-R4. The board DTS does not set it
	# upstream, and forcing PCS RX polarity can break RTL8672/RTL9601C copper
	# or GPON SFP modules during EEPROM/PHY probe.
	bpi_dtsi="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7988a-bananapi-bpi-r4.dtsi"
	if [ -f "$bpi_dtsi" ] && grep -q 'mediatek,pnswap-rx' "$bpi_dtsi"; then
		perl -0pi -e 's/\n&usxgmiisys0[ \t\r]*\{[ \t\r\n]*mediatek,pnswap-rx;[ \t\r\n]*\};[ \t\r]*\n[ \t\r]*\n?&usxgmiisys1[ \t\r]*\{[ \t\r\n]*mediatek,pnswap-rx;[ \t\r\n]*\};[ \t\r]*\n/\n/g' "$bpi_dtsi"
	fi
}

[ -f "$GITHUB_WORKSPACE/scripts/cpuinfo" ] && \
	install -m 0755 "$GITHUB_WORKSPACE/scripts/cpuinfo" package/emortal/autocore/files/generic/cpuinfo

[ -f "$GITHUB_WORKSPACE/scripts/tempinfo" ] && \
	install -m 0755 "$GITHUB_WORKSPACE/scripts/tempinfo" package/emortal/autocore/files/arm/tempinfo

./scripts/feeds install -a

# Re-patch libcrypt-compat after feeds install in case feed symlinks/copies brought it back
_purge_libcrypt_compat

# Downgrade the usign SHA-512 padding warning from ERROR_MESSAGE (red/scary) 
sed -i 's/ERROR_MESSAGE,WARNING: Applying padding in/MESSAGE,WARNING: Applying padding in/' package/Makefile

[ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/60_wifi.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1000-luci-status-overview-wifi7-mlo.patch"

[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1001-luci-network-wireless-station-hints.patch"

[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/999-luci-wireless-mtk-mode-matrix.patch"

[ -d package/system/rpcd ] && {
    mkdir -p package/system/rpcd/patches
    install -m 0644 \
        "$GITHUB_WORKSPACE/patches/filogic/997-rpcd-iwinfo-export-mhz-hi.patch" \
        package/system/rpcd/patches/997-iwinfo-export-eht-dcm.patch
}

[ -f package/network/utils/iwinfo/src/iwinfo_mtk.c ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/998-iwinfo-mtk-fix-6ghz-reporting.patch"

[ -f package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1005-luci-wireless-mtk-station-and-rate-fixes.patch"

[ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/60_wifi.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1002-luci-status-overview-rate-mhz-hi.patch"
