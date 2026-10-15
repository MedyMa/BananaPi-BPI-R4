#!/bin/bash
# diy-mtk.sh -- BPI-R4 BE14 vendor WiFi7 build for benboguan/openwrt-25.12.
# Configuration and firmware guards run through this existing DIY script.
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

check_wifi7_config() {
    local cfg="${1:-.config}"
    [ -r "$cfg" ] || { echo "Cannot read resolved config: $cfg" >&2; exit 1; }

    require_config() {
        grep -qxF "$1" "$cfg" || {
            echo "Required WiFi7 configuration missing: $1" >&2
            exit 1
        }
    }

    for package in kmod-mt_wifi7 kmod-mt_hwifi kmod-mtk_pci kmod-mtk_wed kmod-warp \
        kmod-mediatek_hnat kmod-mt_wifi_osal mtwifi-cfg wifi-dats luci-app-mtwifi-cfg \
        luci-app-fan luci-app-sfp-status luci-app-adguardhome luci-app-modemband \
        luci-app-turboacc-mtk luci-app-traffic luci-app-eqos-mtk \
        rpcd-mod-router-status wireless-tools wpad-openssl; do
        require_config "CONFIG_PACKAGE_${package}=y"
    done
    require_config 'CONFIG_TARGET_mediatek_filogic_DEVICE_bananapi_bpi-r4=y'
    require_config 'CONFIG_MTK_HWIFI_FW_BE14000_20260721=y'
    require_config 'CONFIG_MTK_HWIFI_FW_PATH_BE14000="BE14000-20260721"'
    require_config 'CONFIG_MTK_WIFI7_WLAN_HOOK=y'
    require_config 'CONFIG_MTK_WIFI7_FAST_NAT_SUPPORT=y'
    require_config 'CONFIG_MTK_WIFI7_WHNAT_SUPPORT=m'
    require_config 'CONFIG_MTK_WIFI7_OSAL_SUPPORT=y'
    require_config 'CONFIG_MTK_WIFI7_CFG80211_SUPPORT=y'
    require_config 'CONFIG_MTK_WIFI7_CFG80211_FULL_OPS_SUPPORT=y'
    require_config 'CONFIG_MTK_WIFI7_HOSTAPD_MBSS_SUPPORT=y'
    require_config 'CONFIG_MTK_WIFI_OSAL_CFG80211_SUPPORT=y'

    for package in kmod-mt76-core kmod-mt76-connac kmod-mt7996e kmod-mt7990-firmware \
        kmod-mt7996-firmware kmod-mt7996-233-firmware kmod-mt_wifi_cmn \
        wifi-profile wifi-script luci-app-mtk; do
        if grep -qE "^CONFIG_PACKAGE_${package}=[ym]$" "$cfg"; then
            echo "Conflicting mt76 wireless package selected: $package" >&2
            exit 1
        fi
    done
    if grep -qE '^CONFIG_(EN_HWIFI_NPU_SUPPORT|PACKAGE_kmod-en_npu|PACKAGE_kmod-npu(-[^=]+)?|PACKAGE_npu-[^=]+)=[ym]$' "$cfg"; then
        echo 'NPU offload must remain disabled for this BPI-R4 build' >&2
        exit 1
    fi
    echo 'BPI-R4 BE14 vendor WiFi7 configuration verified'
}

verify_wifi7_firmware() {
    local custom roots verified root blob
    custom=package/mtk/drivers/mt_hwifi/files/BE14000-20260721
    roots=$(find build_dir -type d -path '*/root-mediatek' -print)
    [ -n "$roots" ] || { echo 'Installed mediatek root filesystem missing' >&2; exit 1; }
    verified=0
    for root in $roots; do
        [ -d "$root/lib/firmware" ] || continue
        for blob in WIFI_MT7990_PATCH_MCU_1_1_hdr.bin \
            WIFI_MT7990_WACPU_RAM_CODE_1_1.bin WIFI_RAM_CODE_MT7990_1_1.bin \
            WIFI_RAM_CODE_MT7990_1_1_TESTMODE.bin; do
            cmp -s "$custom/$blob" "$root/lib/firmware/$blob" || {
                echo "BE14 firmware missing or overwritten: $root/lib/firmware/$blob" >&2
                exit 1
            }
        done
        verified=$((verified + 1))
    done
    [ "$verified" -gt 0 ] || { echo 'No installed BE14 firmware found' >&2; exit 1; }
    echo "Verified BE14000-20260721 in $verified installed root filesystem(s)"
}

fix_be14_firmware_install() {
    # Keep generic PHY firmware, then install the selected BE14 blobs last.
    python3 - <<'PY'
from pathlib import Path
recipe = Path('package/mtk/drivers/mt_hwifi/Makefile')
text = recipe.read_text(encoding="utf-8")
install = text.index('define KernelPackage/mt_hwifi/install')
start = text.index('ifneq ($(CONFIG_MTK_HWIFI_FW_PATH_BE19000),)', install)
end = text.index('ifeq ($(CONFIG_MTK_HWIFI_MT7992),y)', start)
base = text.rfind('$(PKG_BUILD_DIR)/bin/mt7990/', install, end)
if base < 0:
    raise SystemExit('MT7990 base firmware install layout missing')
if start > base:
    print('BE14 custom firmware already installed last')
else:
    block_end = text.index('ifeq ($(CONFIG_MTK_WIFI7_CCN34_SPLIT_MAC_SUPPORT),y)', start)
    block = text[start:block_end]
    if block.count('$(INSTALL_BIN)') != 2:
        raise SystemExit('Unexpected MT7990 custom firmware install layout')
    text = text[:start] + text[block_end:]
    end = text.index('ifeq ($(CONFIG_MTK_HWIFI_MT7992),y)', start)
    close = text.rfind('endif', start, end)
    if close < start:
        raise SystemExit('MT7990 install guard missing')
    recipe.write_text(text[:close] + block + text[close:], encoding="utf-8")
    print('BE14 custom firmware installation order corrected')
PY
}

case "${1:-}" in
    --configure) configure_wifi7 "${2:-.config}"; exit ;;
    --check-config) check_wifi7_config "${2:-.config}"; exit ;;
    --verify-firmware) verify_wifi7_firmware; exit ;;
    "") ;;
    *) echo "Unknown DIY mode: $1" >&2; exit 2 ;;
esac

# MAPCfg and MAP_ROLE_* are absent when MAP support is disabled. Keep this
# MAP-only ACL restriction behind the same feature guard as those declarations.
_mt_wifi7_patch_dir="package/mtk/drivers/mt_wifi7/patches"
_mt_wifi7_acl_patch="$GITHUB_WORKSPACE/patches/filogic/25.12/1018-mt-wifi7-guard-map-acl.patch"
_mt_wifi7_acl_target="$_mt_wifi7_patch_dir/0044-mt_wifi7-guard-map-acl-when-disabled.patch"
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

merge_package(){
    repo=`echo $1 | rev | cut -d'/' -f 1 | rev`
    pkg=`echo $2 | rev | cut -d'/' -f 1 | rev`
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
rm -rf package/mtk/applications/luci-app-turboacc-mtk
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}

# Clone community packages
mkdir -p package/community
pushd package/community
git clone --depth=1 -b dev https://github.com/fw876/helloworld
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
[ -f openwrt-passwall-packages/haproxy/Makefile ] && sed -i '/^[[:space:]]*ADDON+=USE_QUIC=1$/d' openwrt-passwall-packages/haproxy/Makefile
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
# The selected helloworld/mihomo core satisfies Nikki's +mihomo dependency.
# Drop unused alternative providers whose mutual CONFLICTS cause a Kconfig cycle.
[ -f helloworld/mihomo/Makefile ] || exit 1
rm -rf OpenWrt-nikki/mihomo-alpha OpenWrt-nikki/mihomo-meta
git clone --depth=1 https://github.com/1522042029/luci-app-socat
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
merge_package https://github.com/kenzok8/jell jell/adguardhome
# default_username.patch: upstream zh-cn.json moved/indent changed; rewrite the
# hunk so the AdGuardHome prepare stage does not fail
_adguardhome_patch="package/openwrt-packages/adguardhome/patches/default_username.patch"
if [ -f "$_adguardhome_patch" ]; then
	cat > "$_adguardhome_patch" << 'AGPATCH'
--- a/client/src/__locales/zh-cn.json
+++ b/client/src/__locales/zh-cn.json
@@ -752,7 +752,7 @@
   "use_private_ptr_resolvers_title": "使用私人反向 DNS 解析器",
   "use_saved_key": "使用之前保存的密钥",
   "username_label": "用户名",
-  "username_placeholder": "输入用户名",
+  "username_placeholder": "默认用户名密码都是root",
   "validated_with_dnssec": "通过 DNSSEC 验证",
   "version": "版本",
   "version_request_error": "检查更新失败。请检查互联网连接。",
AGPATCH
	echo "[DIY] adguardhome default_username.patch regenerated for v0.107.78"
fi
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-fan
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-sfp-status
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-modemband
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-turboacc-mtk
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-traffic
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/rpcd-mod-router-status
if [ ! -f package/openwrt-packages/rpcd-mod-router-status/Makefile ] || \
   [ ! -f package/openwrt-packages/rpcd-mod-router-status/root/etc/init.d/router-status ]; then
    echo "Independent router status package was not fetched" >&2
    exit 1
fi
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/ddnsto
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/luci-app-ddnsto
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
    package/community/package/openwrt-packages/adguardhome/Makefile \
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
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

fix_be14_firmware_install
