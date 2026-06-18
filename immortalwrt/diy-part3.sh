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

    if git apply --ignore-space-change --ignore-whitespace --reverse --check "$patch_file" >/dev/null 2>&1; then
        return 0
    fi

    git apply --ignore-space-change --ignore-whitespace "$patch_file"
}

install_kernel_patch() {
    local patch_file="$1"
    local patch_name="$2"
    local patch_dir="target/linux/mediatek/patches-6.6"

    [ -f "$patch_file" ] || return 0
    [ -d "$patch_dir" ] || return 0

    install -m 0644 "$patch_file" "$patch_dir/$patch_name"
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
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/ddnsto
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/luci-app-ddnsto
popd

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

[ -f target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7988a.dtsi ] && {
	# Enable LVTS thermal sensor
	sed -i '/lvts: lvts@1100a000 {/,/^[[:space:]]*};/ { /status = "disabled";/d; }' \
		target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7988a.dtsi
	# Increase MDIO drive strength from 8mA to 10mA for GMAC1 and GMAC2 AQR113C 10G PHY
	# (MTK upstream patch 1010; required for reliable 10G link at high frequencies)
	sed -i '/groups = "mdc_mdio0";/{N; s/drive-strength = <MTK_DRIVE_8mA>/drive-strength = <MTK_DRIVE_10mA>/}' \
		target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7988a.dtsi
}

[ -f "$GITHUB_WORKSPACE/scripts/cpuinfo" ] && \
	install -m 0755 "$GITHUB_WORKSPACE/scripts/cpuinfo" package/emortal/autocore/files/generic/cpuinfo

[ -f "$GITHUB_WORKSPACE/scripts/tempinfo" ] && \
	install -m 0755 "$GITHUB_WORKSPACE/scripts/tempinfo" package/emortal/autocore/files/arm/tempinfo

./scripts/feeds install -a

[ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/60_wifi.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1000-luci-status-overview-wifi7-mlo.patch"

[ -f package/system/rpcd/patches/0002-iwinfo-Improve-EHT-DCM-support.patch ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/997-rpcd-iwinfo-export-mhz-hi.patch"

[ -f package/network/utils/iwinfo/src/iwinfo_mtk.c ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/998-iwinfo-mtk-fix-6ghz-reporting.patch"

[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1001-luci-network-wireless-station-hints.patch"

[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/999-luci-wireless-mtk-mode-matrix.patch"

[ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/60_wifi.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1002-luci-status-overview-rate-mhz-hi.patch"

# Allow RTL8672/RTL9601C locked GPON ONT sticks that return all-zero EEPROM
# and reduce false-positive RTL8672 warnings on MT7988 SFP I2C.
install_kernel_patch \
    "$GITHUB_WORKSPACE/patches/filogic/997-sfp-rtl8672-accept-zero-phys-id-24.10.patch" \
    "999-2767-01-net-phy-sfp-rtl8672-accept-zero-phys-id.patch"

install_kernel_patch \
    "$GITHUB_WORKSPACE/patches/filogic/998-sfp-rtl8672-reduce-false-positive-warning.patch" \
    "999-2767-02-net-phy-sfp-reduce-rtl8672-warning-false-positive.patch"

patch_makefile_dep \
    feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js \
    "\t\t\t\thint = name || ipv4 || ipv6 || '?';" \
    "\t\t\t\thint = (name == '?' ? null : name) || ipv4 || ipv6 || bss.mac;"
