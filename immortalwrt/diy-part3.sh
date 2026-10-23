#!/bin/bash

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

patch_bpi_r4_sysupgrade_itb_check() {
    local platform_sh="target/linux/mediatek/filogic_a73/base-files/lib/upgrade/platform.sh"

    [ -f "$platform_sh" ] || return 0
    grep -q 'bananapi,bpi-r4' "$platform_sh" || return 0
    grep -q 'dd if="$1" bs=1 skip=257 count=5' "$platform_sh" || return 0

    perl -0pi -e '
        $count = s/\n\tmediatek,mt7988a-rfb\|\\\n\tbananapi,bpi-r4\|\\\n\tbananapi,bpi-r4-poe\|\\\n\tbananapi,bpi-r4-pro\|\\\n\ttplink,tl-7dr7230-rev1\.0-sp2\|\\\n\ttplink,tl-7dr7299-v1\)\n\t\tmagic="\$\(dd if="\$1" bs=1 skip=257 count=5 2>\/dev\/null\)"\n\n\t\t\[ "\$magic" != "ustar" \] && \{\n\t\t\techo "Invalid image type\."\n\t\t\treturn 1\n\t\t\}\n\n\t\treturn 0\n\t\t;;/\n\tmediatek,mt7988a-rfb|\\\n\tbananapi,bpi-r4|\\\n\tbananapi,bpi-r4-poe|\\\n\tbananapi,bpi-r4-pro|\\\n\ttplink,tl-7dr7230-rev1.0-sp2|\\\n\ttplink,tl-7dr7299-v1)\n\t\t[ "\$(identify_magic_long "\$magic")" != "fit" ] && {\n\t\t\techo "Invalid image type."\n\t\t\treturn 1\n\t\t}\n\n\t\treturn 0\n\t\t;;/s;
        END { exit($count ? 0 : 2); }
    ' "$platform_sh"
}


rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-modemband
rm -rf package/mtk/applications/luci-app-turboacc-mtk
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}

# Clone community packages
mkdir -p package/community
pushd package/community
git clone --depth=1 -b dev https://github.com/fw876/helloworld
# rm -rf helloworld/{naiveproxy,shadowsocks-libev,shadowsocksr-libev,shadow-tls,simple-obfs,tcping,tuic-client,v2ray-plugin,xray-core,xray-plugin}
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
[ -f openwrt-passwall-packages/haproxy/Makefile ] && sed -i '/^[[:space:]]*ADDON+=USE_QUIC=1$/d' openwrt-passwall-packages/haproxy/Makefile
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
# The selected helloworld/mihomo core satisfies Nikki's +mihomo dependency.
# Drop unused alternative providers whose mutual CONFLICTS cause a Kconfig cycle.
[ -f helloworld/mihomo/Makefile ] || exit 1
rm -rf OpenWrt-nikki/mihomo-alpha OpenWrt-nikki/mihomo-meta
[ -f OpenWrt-nikki/nikki/Makefile ] && perl -0pi -e 's/define Build\/Compile\r?\n\r?\nendef/define Build\/Compile\n\nendef\n\ndefine Build\/InstallDev\n\nendef/' OpenWrt-nikki/nikki/Makefile
git clone --depth=1 https://github.com/1522042029/luci-app-socat
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
merge_package https://github.com/kenzok8/jell jell/adguardhome
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/ddnsto
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/luci-app-ddnsto
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-fan
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-modemband
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-sfp-status
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-turboacc-mtk
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-traffic
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/rpcd-mod-router-status
if [ ! -f package/openwrt-packages/rpcd-mod-router-status/Makefile ] || \
   [ ! -f package/openwrt-packages/rpcd-mod-router-status/root/etc/init.d/router-status ]; then
    echo "Independent router status package was not fetched" >&2
    exit 1
fi
popd

rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 27.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# The AQR firmware recipe is owned by the source tree, not generated by DIY.
[ -f package/kernel/aqr10g-phy-fw/Makefile ] || {
    echo 'MT7988 source AQR firmware recipe is missing' >&2
    exit 1
}

# Kernel and vendor WiFi fixes are versioned in the selected source tree.
# Do not copy a second patch queue from this build repository.

mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1  https://github.com/vernesong/OpenClash
git config core.sparsecheckout true
popd

# Fix opkg feed URLs: 24.10-SNAPSHOT feeds are gone, use latest stable 24.10.6
sed -i 's|24.10-SNAPSHOT|24.10.6|g' include/version.mk
sed -i 's|24.10-SNAPSHOT|24.10.6|g' package/base-files/image-config.in

# padavanonly filogic_a73 upgrades via fit_do_upgrade; fix platform_check_image
patch_bpi_r4_sysupgrade_itb_check

# uci-defaults fallback that rewrites distfeeds.conf on first boot
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-fix-distfeeds <<'UCIEOF'
#!/bin/sh
FEEDCONF="/etc/opkg/distfeeds.conf"
BASE="https://downloads.immortalwrt.org/releases/24.10.6"
cat > "$FEEDCONF" <<EOF
src/gz immortalwrt_core ${BASE}/targets/mediatek/filogic/packages
src/gz immortalwrt_base ${BASE}/packages/aarch64_cortex-a53/base
src/gz immortalwrt_luci ${BASE}/packages/aarch64_cortex-a53/luci
src/gz immortalwrt_packages ${BASE}/packages/aarch64_cortex-a53/packages
src/gz immortalwrt_routing ${BASE}/packages/aarch64_cortex-a53/routing
src/gz immortalwrt_telephony ${BASE}/packages/aarch64_cortex-a53/telephony
EOF
UCIEOF
chmod +x files/etc/uci-defaults/99-fix-distfeeds

rm -rf feeds/luci
./scripts/feeds update -a

# helloworld shadowsocks-libev: skip the non-deterministic PKG_MIRROR_HASH
for f in \
    package/community/helloworld/shadowsocks-libev/Makefile; do
    [ -f "$f" ] && sed -i '/^PKG_MIRROR_HASH:=/s/:=.*/:=skip/' "$f"
done

# This upstream patch lacks its final LF, which needs fuzz 1 to apply.
# Restore the line ending so the source tree can keep PATCHFUZZ=0.
obfs_patch=package/community/helloworld/simple-obfs/patches/001-convert-arguments-of-isdigit-to-int.patch
if [ -s "$obfs_patch" ] && [ "$(tail -c 1 "$obfs_patch" | wc -l)" -eq 0 ]; then
    printf '\n' >> "$obfs_patch"
fi

# containerd's vendored cpuid v2.0.4 hits Go's >= 1.23 linkname check. MAKE_FLAGS is
# frozen by the BuildPackage eval, so the line must be injected before it.
f=feeds/packages/utils/containerd/Makefile
if [ ! -f "$f" ]; then
    echo "[DIY] containerd Makefile missing: $f" >&2
elif ! grep -q 'checklinkname=0' "$f"; then
    awk -v ins="MAKE_FLAGS += EXTRA_LDFLAGS='-s -w -checklinkname=0'" '{print} /^Build\/Compile=/ {print ins}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "[DIY] containerd: -checklinkname=0 injected=$(grep -c 'checklinkname=0' "$f")"
fi

# GCC 14 + musl fortify workaround for mbedtls
if ! grep -q '_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile; then
    if grep -q '\$(if \$(findstring cortex-a53,\$(CONFIG_CPU_TYPE)),-march=armv8-a)' package/libs/mbedtls/Makefile; then
        sed -i '/$(if $(findstring cortex-a53,$(CONFIG_CPU_TYPE)),-march=armv8-a)/a TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile
  else
    echo 'TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' >> package/libs/mbedtls/Makefile
  fi
fi

# locate libcrypt-compat references across all feed path variants
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
    # feed copies may keep or strip the "package/" prefix
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
    
patch_makefile_dep \
    package/emortal/autocore/Makefile \
    '+(TARGET_mediatek||TARGET_mvebu):mhz' \
    '+(TARGET_mediatek||TARGET_mvebu):mhz \
    +TARGET_mediatek:wireless-tools'

# MT7988 DTS, SFP recovery and pstore integration are owned by the source tree.
# Do not mutate kernel inputs or copy SFP scripts from this build repository.

[ -f "$GITHUB_WORKSPACE/scripts/cpuinfo" ] && \
	install -m 0755 "$GITHUB_WORKSPACE/scripts/cpuinfo" package/emortal/autocore/files/generic/cpuinfo

[ -f "$GITHUB_WORKSPACE/scripts/tempinfo" ] && \
	install -m 0755 "$GITHUB_WORKSPACE/scripts/tempinfo" package/emortal/autocore/files/arm/tempinfo

./scripts/feeds install -a

# Re-patch libcrypt-compat after feeds install in case feed symlinks/copies brought it back
_purge_libcrypt_compat

# Downgrade the usign SHA-512 padding warning from ERROR_MESSAGE
sed -i 's/ERROR_MESSAGE,WARNING: Applying padding in/MESSAGE,WARNING: Applying padding in/' package/Makefile

# Apply source-owned LuCI feed integration only after feeds are installed.
# The source entrypoint checks its inputs and accepts an already-applied state.
[ -f scripts/mt7988-apply-feed-patches.sh ] || {
    echo 'MT7988 source feed-patch entrypoint is missing' >&2
    exit 1
}
bash scripts/mt7988-apply-feed-patches.sh || exit $?
