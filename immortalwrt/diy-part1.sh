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

apply_workspace_patch() {
    local patch_file="$1"

    [ -f "$patch_file" ] || return 0

    if git apply --ignore-space-change --ignore-whitespace --reverse --check "$patch_file" >/dev/null 2>&1; then
        return 0
    fi

    git apply --ignore-space-change --ignore-whitespace "$patch_file"
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

# merge_package "-b openwrt-24.10-6.6 https://github.com/padavanonly/immortalwrt-mt798x-6.6" immortalwrt-mt798x-6.6/package/mtk/applications/mtkhqos_util

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

[ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/60_wifi.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1000-luci-status-overview-wifi7-mlo.patch"
    
[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1001-luci-network-wireless-station-hints.patch"

[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/999-luci-wireless-mtk-mode-matrix.patch"

[ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/60_wifi.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1002-luci-status-overview-rate-mhz-hi.patch"    

[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1003-luci-wireless-mtk-mlo-ofdma-controls.patch"

# ── BPI-R4 LED + BE14000 WiFi fixes ─────────────────────────────────────────
# The upstream immortalwrt openwrt-24.10 DTS defines the B LED (GPIO 63) with
# LED_FUNCTION_WPS, which only activates during WPS setup – invisible after
# normal boot.  The G LED (GPIO 79) uses 'default-state = "on"' which can be
# lost when the mtwifi vendor driver re-initialises GPIO ordering.
#
# Preferred path: apply the workspace patch which rewrites the LED section to:
#   G (GPIO 79) -> default-on (system status, always lit)
#   B (GPIO 63) -> heartbeat  (system-alive blink; mtwifi takes over for WiFi)
#   SSD (GPIO 10) -> disk-activity (NVMe/eMMC I/O blink – verify GPIO 10 for
#                    your board revision against BPI-R4-Main schematic H2)
#
# Fallback path (sed): in case the DTS content drifts between immortalwrt
# commits, a targeted sed run makes the same changes without needing exact
# context lines.

BPI_R4_DTSI="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7988a-bananapi-bpi-r4.dtsi"

if [ -f "$BPI_R4_DTSI" ]; then
    if apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/998-bpi-r4-be14000-leds-fix.patch" 2>/dev/null; then
        echo "INFO: BPI-R4 LED DTS patch applied successfully."
    else
        echo "WARN: DTS patch did not apply cleanly; falling back to sed fixups."
        # G LED: swap default-state for explicit default-on trigger
        sed -i \
            's/^\(\s*\)default-state = "on";/\1linux,default-trigger = "default-on";/' \
            "$BPI_R4_DTSI"
        # B LED: change WPS function and add heartbeat trigger
        sed -i \
            's/LED_FUNCTION_WPS/LED_FUNCTION_INDICATOR/' \
            "$BPI_R4_DTSI"
        sed -i \
            's/^\(\s*\)default-state = "off";/\1linux,default-trigger = "heartbeat";/' \
            "$BPI_R4_DTSI"
        # Add SSD LED node after the closing brace of led-blue if not present
        if ! grep -q 'led-ssd' "$BPI_R4_DTSI"; then
            sed -i '/gpios = <&pio 63 GPIO_ACTIVE_HIGH>;/{n; s/.*/\t\t};\n\n\t\tled-ssd {\n\t\t\tlabel = "green:ssd";\n\t\t\tfunction = LED_FUNCTION_DISK;\n\t\t\tcolor = <LED_COLOR_ID_GREEN>;\n\t\t\tgpios = <\&pio 10 GPIO_ACTIVE_HIGH>;\n\t\t\tlinux,default-trigger = "disk-activity";\n\t\t};/}' \
                "$BPI_R4_DTSI" 2>/dev/null || true
        fi
    fi
fi

# Deploy a uci-defaults script so LED sysfs names are wired to the correct
# OpenWrt system LED config entries on first boot.  This is a belt-and-
# suspenders measure: even if the DTS labels drift, the LEDs are reachable
# by their known sysfs names once the gpio-leds driver binds.
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/91_bpi-r4-leds << 'EOF'
#!/bin/sh
# BPI-R4 H2 connector LED defaults – applied once on first boot.

# G (green, GPIO 79) – always-on status LED
uci -q delete system.led_status 2>/dev/null
uci set system.led_status=led
uci set system.led_status.name='Status'
uci set system.led_status.sysfs='green:status'
uci set system.led_status.trigger='default-on'

# B (blue, GPIO 63) – heartbeat until mtwifi takes over for WiFi activity
uci -q delete system.led_wifi 2>/dev/null
uci set system.led_wifi=led
uci set system.led_wifi.name='WiFi'
uci set system.led_wifi.sysfs='blue:indicator'
uci set system.led_wifi.trigger='heartbeat'

# SSD (GPIO 10) – disk activity, blinks on NVMe / eMMC I/O
uci -q delete system.led_ssd 2>/dev/null
uci set system.led_ssd=led
uci set system.led_ssd.name='SSD'
uci set system.led_ssd.sysfs='green:ssd'
uci set system.led_ssd.trigger='disk-activity'

uci commit system
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/91_bpi-r4-leds
# ─────────────────────────────────────────────────────────────────────────────
