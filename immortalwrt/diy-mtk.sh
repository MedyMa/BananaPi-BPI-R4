#!/bin/bash
# diy-mtk.sh -- BPI-R4 BE14 WiFi7 build for MedyMa/immortalwrt-mt798x-25.12.
# Configure the vendor WiFi7 stack and prepare build sources.
set -e

configure_wifi7() {
    local cfg="${1:-.config}" package symbol
    [ -f package/mtk/drivers/mt_wifi7/Makefile ] || {
        echo 'Vendor WiFi7 source is required for this configuration' >&2
        exit 1
    }
    [ -r "$cfg" ] || { echo "Cannot read config: $cfg" >&2; exit 1; }
    # Disable target defaults that conflict with the vendor radio stack.
    for package in kmod-mt76-core kmod-mt76-connac kmod-mt7996e \
        kmod-mt7990-firmware kmod-mt7996-firmware kmod-mt7996-233-firmware \
        kmod-mt7996-firmware-common kmod-mt_wifi_cmn wifi-profile wifi-script luci-app-mtk \
        kmod-npu kmod-npu-flow kmod-npu-flow-autoload kmod-npu-nf_hnat \
        kmod-npu-nf_hnat-autoload kmod-npu-mcast kmod-npu-mcast-autoload npu-rebb-fw kmod-npu-dpdk kmod-npu-dpdk-autoload kmod-en_npu \
        mtk-hqos luci-app-mtk-hqos kmod-pce mtkhnat_util ethswbox flowtable \
        netsys_dbg_util tops-tool; do
        symbol="CONFIG_PACKAGE_${package}"
        sed -i "/^${symbol}=/d; /^# ${symbol} is not set$/d" "$cfg"
        printf '# %s is not set\n' "$symbol" >> "$cfg"
    done
    sed -i '/^CONFIG_EN_HWIFI_NPU_SUPPORT=/d; /^# CONFIG_EN_HWIFI_NPU_SUPPORT is not set$/d' "$cfg"
    printf '# CONFIG_EN_HWIFI_NPU_SUPPORT is not set\n' >> "$cfg"
    # Let this source's kernel configuration and package dependencies select HNAT.
    sed -i '/^CONFIG_KERNEL_NET_MEDIATEK_HNAT=/d; /^CONFIG_KERNEL_MEDIATEK_NETSYS_/d; /^# CONFIG_KERNEL_MEDIATEK_NETSYS_.* is not set$/d' "$cfg"
}


case "${1:-}" in
    --configure) configure_wifi7 "${2:-.config}"; exit ;;
    "") ;;
    *) echo "Unknown DIY mode: $1" >&2; exit 2 ;;
esac

# MAPCfg and MAP_ROLE_* are absent when MAP support is disabled. Keep this
# MAP-only ACL restriction behind the same feature guard as those declarations.
_mt_wifi7_patch_dir="package/mtk/drivers/mt_wifi7/patches"
_mt_wifi7_acl_patch="$GITHUB_WORKSPACE/patches/filogic/25.12/1018-mt-wifi7-guard-map-acl.patch"
_mt_wifi7_acl_target="$_mt_wifi7_patch_dir/0049-mt_wifi7-guard-map-acl-when-disabled.patch"
[ -d "$_mt_wifi7_patch_dir" ] || {
    echo "Vendor WiFi7 patch directory missing: $_mt_wifi7_patch_dir" >&2
    exit 1
}
[ -f "$_mt_wifi7_acl_patch" ] || {
    echo "MAP ACL compatibility patch missing: $_mt_wifi7_acl_patch" >&2
    exit 1
}
if [ -e "$_mt_wifi7_acl_target" ] && ! cmp -s "$_mt_wifi7_acl_patch" "$_mt_wifi7_acl_target"; then
    echo "Vendor WiFi7 patch slot already occupied: $_mt_wifi7_acl_target" >&2
    exit 1
fi
install -m 0644 "$_mt_wifi7_acl_patch" "$_mt_wifi7_acl_target"
echo "Installed MAP-disabled ACL build fix: $_mt_wifi7_acl_target"

_mtk_source_root="$PWD"

merge_package(){
    local repo_url="$1" package_path="$2" branch="${3:-}" repo
    repo="${repo_url##*/}"
    repo="${repo%.git}"
    if [ -n "$branch" ]; then
        git clone --depth=1 --single-branch --branch "$branch" -- "$repo_url" "$repo"
    else
        git clone --depth=1 --single-branch -- "$repo_url" "$repo"
    fi
    mkdir -p "$_mtk_source_root/package/openwrt-packages"
    mv "$package_path" "$_mtk_source_root/package/openwrt-packages/"
    rm -rf -- "$repo"
}

patch_makefile_dep() {
    local file_path="$1"
    local old_text="$2"
    local new_text="$3"
    local perl_status

    [ -f "$file_path" ] || return 0
    grep -qzF "$old_text" "$file_path" || return 0

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

# Remove feed packages replaced by community clones
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-modemband
rm -rf feeds/luci/applications/luci-app-adguardhome
rm -rf package/feeds/luci/luci-app-adguardhome
rm -rf package/mtk/applications/luci-app-adguardhome
rm -rf package/mtk/applications/luci-app-turboacc-mtk
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}

# Clone community packages
mkdir -p package/community
pushd package/community
git clone --depth=1 -b dev https://github.com/fw876/helloworld
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
[ -f openwrt-passwall-packages/haproxy/Makefile ] && sed -i '/^[[:space:]]*ADDON+=USE_QUIC=1$/d' openwrt-passwall-packages/haproxy/Makefile
[ -f openwrt-passwall-packages/naiveproxy/Makefile ] && {
  sed -i 's/^PKG_RELEASE:=.*$/PKG_RELEASE:=5/' openwrt-passwall-packages/naiveproxy/Makefile
  sed -i '/aarch64_cortex-a53)$/{n;s/^[[:space:]]*PKG_HASH:=.*/  PKG_HASH:=8a60b3a5f46e005ebce4785c367a35b4938d127e001f6f365aa7f099fb4a9a64/;}' openwrt-passwall-packages/naiveproxy/Makefile
}
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
# The selected helloworld/mihomo core satisfies Nikki's +mihomo dependency.
# Drop unused alternative providers whose mutual CONFLICTS cause a Kconfig cycle.
[ -f helloworld/mihomo/Makefile ] || exit 1
rm -rf OpenWrt-nikki/mihomo-alpha OpenWrt-nikki/mihomo-meta
git clone --depth=1 https://github.com/1522042029/luci-app-socat
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
rm -rf -- "$_mtk_source_root/package/community/package/openwrt-packages/adguardhome"
rm -rf -- "$_mtk_source_root/package/openwrt-packages/adguardhome"
merge_package https://github.com/kenzok8/jell jell/adguardhome
git clone --depth=1 --single-branch --branch main https://github.com/MedyMa/luci-app.git luci-app
echo "MedyMa LuCI source: $(git -C luci-app rev-parse HEAD)"
mkdir -p "$_mtk_source_root/package/openwrt-packages"
for package in luci-app-fan luci-app-sfp-status luci-app-adguardhome \
    luci-app-modemband luci-app-turboacc-mtk luci-app-traffic rpcd-mod-router-status; do
    [ -f "luci-app/Luci-app/$package/Makefile" ] || {
        echo "MedyMa package missing: $package" >&2
        exit 1
    }
    rm -rf -- "$_mtk_source_root/package/community/package/openwrt-packages/$package"
    rm -rf -- "$_mtk_source_root/package/openwrt-packages/$package"
    mv "luci-app/Luci-app/$package" "$_mtk_source_root/package/openwrt-packages/"
done
rm -rf luci-app
if [ ! -f "$_mtk_source_root/package/openwrt-packages/rpcd-mod-router-status/Makefile" ] || \
   [ ! -f "$_mtk_source_root/package/openwrt-packages/rpcd-mod-router-status/root/etc/init.d/router-status" ]; then
    echo "Independent router status package was not fetched" >&2
    exit 1
fi
merge_package https://github.com/linkease/ddnsto-openwrt-package ddnsto-openwrt-package/ddnsto main
merge_package https://github.com/linkease/ddnsto-openwrt-package ddnsto-openwrt-package/luci-app-ddnsto main
popd

rm -rf feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 27.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash
popd

# helloworld simple-obfs/shadowsocks-libev: skip the non-deterministic PKG_MIRROR_HASH
for f in \
    package/community/helloworld/simple-obfs/Makefile \
    package/community/helloworld/shadowsocks-libev/Makefile; do
    [ -f "$f" ] && sed -i '/^PKG_MIRROR_HASH:=/s/:=.*/:=skip/' "$f"
done

# adguardhome: skip frontend hash (GitHub release asset hash is volatile)
patch_makefile_dep \
    package/openwrt-packages/adguardhome/Makefile \
    'FRONTEND_HASH:=084bf3e00ca3e49487fc5a87270b4e1eb26617710ca6116b9e42ce90cb1ad358' \
    'FRONTEND_HASH:=skip'

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

# Drop onionshare-cli (unresolved metadata, not in our config)
rm -rf feeds/packages/net/onionshare-cli

[ -f feeds/luci/applications/luci-app-package-manager/root/usr/libexec/package-manager-call ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/25.12/1004-luci-package-manager-apk-upload-untrusted-master.patch"

# vpnc: add -p to mkdir for idempotency
if grep -q 'mkdir $(PKG_BUILD_DIR)/bin' feeds/packages/net/vpnc/Makefile 2>/dev/null; then
    sed -i '/mkdir $(PKG_BUILD_DIR)\/bin/s/mkdir /mkdir -p /' feeds/packages/net/vpnc/Makefile
fi

# The selected source already includes vendor driver compatibility patches.
# Keep its wifi-profile and mtwifi-cfg together; do not replace them from 6.6.
for recipe in package/mtk/drivers/mt_wifi7/Makefile package/mtk/drivers/mt_hwifi/Makefile; do
    [ -f "$recipe" ] || { echo "Required vendor driver recipe missing: $recipe" >&2; exit 1; }
done
# Feed deps needed by community clones (pcre2 is in main tree since 25.12)
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/feeds install c-ares udns
# Feed installation may restore providers replaced by the community packages.
rm -rf feeds/luci/applications/luci-app-adguardhome package/feeds/luci/luci-app-adguardhome
rm -rf feeds/packages/net/adguardhome package/feeds/packages/adguardhome
rm -rf feeds/packages/net/prosody feeds/packages/utils/telegraf
rm -rf package/feeds/packages/prosody package/feeds/packages/telegraf

# Remove kiddin9 APK repo (triggers broken video/ sub-repo)
for f in \
    package/base-files/files/etc/apk/repositories \
    package/base-files/files/etc/apk/repositories.d/* \
    package/utils/alpine-repositories/files/repositories; do
    [ -f "$f" ] && grep -q 'kiddin9' "$f" 2>/dev/null && sed -i '/kiddin9/d' "$f" 2>/dev/null || true
done

# APK runtime fixes: allow local unsigned APK uploads and disable broken feed entries
rm -f package/base-files/files/etc/uci-defaults/99-apk-untrusted
[ -d package/base-files/files/etc/uci-defaults ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/25.12/1005-base-files-apk-manager-fixes-master.patch"

# fibocom-dial: GCC 14 promotes implicit-function-declaration and return-mismatch to errors
[ -f package/mtk/applications/5g-modem/fibocom-dial/src/main.c ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/25.12/1015-fibocom-dial-gcc14-fixes.patch"

[ -f package/mtk/applications/5g-modem/quectel_cm_5G/src/device.c ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/25.12/1016-quectel-cm-5g-dname-buffer.patch"

[ -f package/mtk/applications/5g-modem/quectel_MHI/src/core/mhi_init.c ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/25.12/1017-quectel-mhi-kernel-api-compat.patch"

# Verify libmbedtls presence (required by shadowsocks-libev)
if [ ! -f package/libs/mbedtls/Makefile ]; then
  echo "WARNING: package/libs/mbedtls/Makefile not found" >&2
elif ! grep -q 'define Package/libmbedtls' package/libs/mbedtls/Makefile; then
  echo "WARNING: package/libs/mbedtls/Makefile does not define libmbedtls" >&2
fi

# GO proxy for sing-box
export GOEXPERIMENT=
export GOPROXY=https://proxy.golang.org,direct

# Compatibility fixes for floating feeds metadata
# rust: rust-lang pruned the 1.94.0 CI LLVM artifacts, so download-ci-llvm=true
# 404s; build LLVM from source instead (configure.py: last --set wins).
_rust_makefile="feeds/packages/lang/rust/Makefile"
if [ -f "$_rust_makefile" ]; then
    if grep -qF -- '--set=llvm.download-ci-llvm=false' "$_rust_makefile"; then
        echo "[DIY] rust: llvm.download-ci-llvm already false"
    elif grep -qF -- '--set=llvm.download-ci-llvm=true' "$_rust_makefile"; then
        sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' "$_rust_makefile"
        grep -qF -- '--set=llvm.download-ci-llvm=false' "$_rust_makefile" || {
            echo 'Failed to disable Rust CI LLVM download' >&2
            exit 1
        }
        echo "[DIY] rust: llvm.download-ci-llvm=false (build LLVM from source)"
    else
        echo 'WARNING: rust Makefile has no llvm.download-ci-llvm flag' >&2
    fi
fi

# luci-ssl-openssl: fall back to px5g-standalone (same /usr/sbin/px5g)
_ssl_makefile="feeds/luci/collections/luci-ssl-openssl/Makefile"
if [ -f "$_ssl_makefile" ] && \
    grep -qF -- '+px5g-openssl' "$_ssl_makefile" && \
    [ ! -d package/utils/px5g-openssl ]; then
    sed -i 's/+px5g-openssl/+px5g-standalone/' "$_ssl_makefile"
    grep -qF -- '+px5g-standalone' "$_ssl_makefile" || {
        echo 'Failed to switch luci-ssl-openssl to px5g-standalone' >&2
        exit 1
    }
    echo "[DIY] luci-ssl-openssl: dep px5g-openssl -> px5g-standalone"
fi

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

# Reduce BPI-R4 U-Boot bootdelay
patch_makefile_dep \
    package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch \
    'CONFIG_BOOTDELAY=30' \
    'CONFIG_BOOTDELAY=10'

# Modify default IP
sed -i 's/192.168.6.1/192.168.2.1/g' package/base-files/files/bin/config_generate
