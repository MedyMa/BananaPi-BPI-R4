#!/bin/bash
set -e

configure_wifi7() {
    local cfg="${1:-.config}" package symbol
    [ -f package/mtk/drivers/mt_wifi7/Makefile ] || {
        echo 'Vendor WiFi7 source is required for this configuration' >&2
        exit 1
    }
    [ -f package/mtk/drivers/mt_wifi_osal/Makefile ] || {
        echo 'Vendor WiFi OSAL source is required for this configuration' >&2
        exit 1
    }
    [ -r "$cfg" ] || { echo "Cannot read config: $cfg" >&2; exit 1; }
    for package in kmod-mt76-core kmod-mt76-connac kmod-mt7996e \
        kmod-mt7990-firmware kmod-mt7996-firmware kmod-mt7996-233-firmware \
        kmod-mt7996-firmware-common wifi-profile wifi-script \
        kmod-en_npu kmod-mt_wifi_cmn kmod-crypto-hw-safexcel \
        mtk-hqos luci-app-mtk-hqos mtkhnat_util ethswbox flowtable \
        netsys_dbg_util tops-tool; do
        symbol="CONFIG_PACKAGE_${package}"
        sed -i "/^${symbol}=/d; /^# ${symbol} is not set$/d" "$cfg"
        printf '# %s is not set\n' "$symbol" >> "$cfg"
    done
    for symbol in CONFIG_MTK_WIFI7_OSAL_SUPPORT CONFIG_PACKAGE_kmod-mt_wifi_osal; do
        sed -i "/^${symbol}=/d; /^# ${symbol} is not set$/d" "$cfg"
        printf '%s=y\n' "$symbol" >> "$cfg"
    done
    if grep -qx 'CONFIG_PACKAGE_mtwifi-scripts=y' "$cfg"; then
        [ -f package/mtk/applications/mtwifi-scripts/Makefile ] || {
            echo 'The selected source does not provide mtwifi-scripts' >&2
            exit 1
        }
        for package in be14-ucg luci-app-unifi luci-i18n-unifi-zh-cn mtwifi-dot1x mtwifi-cfg wifi-scripts luci-app-mtwifi-cfg \
            luci-i18n-mtwifi-cfg-zh-cn; do
            symbol="CONFIG_PACKAGE_${package}"
            sed -i "/^${symbol}=/d; /^# ${symbol} is not set$/d" "$cfg"
            printf '# %s is not set\n' "$symbol" >> "$cfg"
        done
    fi
    sed -i '/^CONFIG_EN_HWIFI_NPU_SUPPORT=/d; /^# CONFIG_EN_HWIFI_NPU_SUPPORT is not set$/d' "$cfg"
    printf '# CONFIG_EN_HWIFI_NPU_SUPPORT is not set\n' >> "$cfg"
    sed -i '/^CONFIG_KERNEL_NET_MEDIATEK_HNAT=/d; /^CONFIG_KERNEL_MEDIATEK_NETSYS_/d; /^# CONFIG_KERNEL_MEDIATEK_NETSYS_.* is not set$/d' "$cfg"
}

verify_ucode_wifi7() {
    local cfg="${1:-.config}" symbol
    [ -r "$cfg" ] || { echo "Cannot read config: $cfg" >&2; return 1; }
    for symbol in CONFIG_PACKAGE_mtwifi-scripts CONFIG_WIFI_SCRIPTS_UCODE \
        CONFIG_PACKAGE_kmod-mt_wifi7 CONFIG_PACKAGE_kmod-mt_hwifi \
        CONFIG_PACKAGE_kmod-mt_wifi_osal CONFIG_PACKAGE_kmod-cfg80211 \
        CONFIG_MTK_WIFI7_OSAL_SUPPORT CONFIG_MTK_WIFI7_CFG80211_SUPPORT \
        CONFIG_MTK_WIFI7_IWCOMMAND_CFG80211_SUPPORT \
        CONFIG_MTK_WIFI7_CFG80211_FULL_OPS_SUPPORT \
        CONFIG_MTK_WIFI7_LED_CONTROL_SUPPORT \
        CONFIG_MTK_WIFI7_HOSTAPD_MBSS_SUPPORT CONFIG_MTK_WIFI7_APCLI_SUPPLICANT_SUPPORT \
        CONFIG_MTK_WIFI_OSAL_CFG80211_SUPPORT CONFIG_MTK_HWIFI_FW_BE14000_20260721 \
        CONFIG_PACKAGE_wifi-dats CONFIG_PACKAGE_mwctl CONFIG_PACKAGE_iw \
        CONFIG_PACKAGE_wpad-openssl CONFIG_PACKAGE_hostapd-utils CONFIG_PACKAGE_wpa-cli \
        CONFIG_PACKAGE_rpcd-mod-iwinfo CONFIG_PACKAGE_luci-mod-network; do
        grep -qx "${symbol}=y" "$cfg" || {
            echo "Resolved ucode firmware configuration is missing ${symbol}=y" >&2
            return 1
        }
    done
    for symbol in CONFIG_PACKAGE_be14-ucg CONFIG_PACKAGE_luci-app-unifi CONFIG_PACKAGE_luci-i18n-unifi-zh-cn \
        CONFIG_PACKAGE_mtwifi-dot1x CONFIG_PACKAGE_mtwifi-cfg CONFIG_PACKAGE_wifi-scripts \
        CONFIG_PACKAGE_luci-app-mtwifi-cfg CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn \
        CONFIG_PACKAGE_wifi-profile CONFIG_PACKAGE_wifi-script \
        CONFIG_PACKAGE_kmod-mt7996e CONFIG_PACKAGE_kmod-en_npu; do
        if grep -Eq "^${symbol}=[ym]$" "$cfg"; then
            echo "Conflicting wireless owner selected: ${symbol}" >&2
            return 1
        fi
    done
    echo '[DIY] verified: vendor OSAL/cfg80211, shared wpad and ucode management'
}

verify_wext_wifi7() {
    local cfg="$1" symbol
    [ -r "$cfg" ] || { echo "Cannot read config: $cfg" >&2; return 1; }
    for symbol in CONFIG_PACKAGE_be14-ucg CONFIG_PACKAGE_luci-app-unifi CONFIG_PACKAGE_luci-i18n-unifi-zh-cn \
        CONFIG_PACKAGE_mtwifi-dot1x CONFIG_PACKAGE_mtwifi-cfg CONFIG_PACKAGE_wifi-scripts \
        CONFIG_PACKAGE_wireless-tools CONFIG_PACKAGE_luci-app-mtwifi-cfg \
        CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn CONFIG_PACKAGE_luci-lib-uqr \
        CONFIG_PACKAGE_luci-mod-network CONFIG_PACKAGE_rpcd-mod-iwinfo \
        CONFIG_PACKAGE_wifi-dats CONFIG_PACKAGE_kmod-mt_wifi7 \
        CONFIG_PACKAGE_kmod-mt_hwifi CONFIG_PACKAGE_kmod-mt_wifi_osal \
        CONFIG_MTK_WIFI7_OSAL_SUPPORT CONFIG_MTK_WIFI7_LED_CONTROL_SUPPORT \
        CONFIG_MTK_HWIFI_FW_BE14000_20260721; do
        grep -qx "${symbol}=y" "$cfg" || {
            echo "Resolved WEXT firmware configuration is missing ${symbol}=y" >&2
            return 1
        }
    done
    for symbol in CONFIG_PACKAGE_mtwifi-scripts CONFIG_WIFI_SCRIPTS_UCODE \
        CONFIG_MTK_WIFI7_CFG80211_SUPPORT CONFIG_MTK_WIFI_OSAL_CFG80211_SUPPORT \
        CONFIG_MTK_WIFI7_IWCOMMAND_CFG80211_SUPPORT CONFIG_MTK_WIFI7_CFG80211_FULL_OPS_SUPPORT \
        CONFIG_MTK_WIFI7_HOSTAPD_MBSS_SUPPORT CONFIG_MTK_WIFI7_APCLI_SUPPLICANT_SUPPORT \
        CONFIG_MTK_WIFI7_MAP_HOSTAPD_SUPPORT CONFIG_PACKAGE_wifi-profile CONFIG_PACKAGE_wifi-script \
        CONFIG_PACKAGE_kmod-mt_wifi_cmn CONFIG_PACKAGE_kmod-mt7996e CONFIG_PACKAGE_kmod-en_npu; do
        if grep -Eq "^${symbol}=[ym]$" "$cfg"; then
            echo "Conflicting WEXT firmware option: ${symbol}" >&2
            return 1
        fi
    done
    echo '[DIY] verified: vendor OSAL/WEXT, mtwifi-cfg and dedicated LuCI'
}

configure_luci() {
    local LC_ALL=C
    local build_root="${GITHUB_WORKSPACE:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
    local patch_dir="$build_root/patches/feeds/luci"
    local overview="$patch_dir/1019-luci-system-acceleration-row.patch"
    local index
    local -a wireless=("$patch_dir"/102[0-9]-luci-mtwifi-*.patch)

    if ! git apply --reverse --check "$overview" >/dev/null 2>&1; then
        git apply "$overview"
    fi
    grep -qx 'CONFIG_PACKAGE_mtwifi-scripts=y' .config || return 0
    [ "${#wireless[@]}" -eq 10 ] || {
        echo 'Incomplete MTK wireless LuCI patch series' >&2
        return 1
    }

    # Reverse-check the complete prefix because the individual patches overlap.
    for ((index=${#wireless[@]}; index>0; index--)); do
        if git apply --reverse --check - < <(cat "${wireless[@]:0:index}") 2>/dev/null; then
            break
        fi
    done
    for ((; index<${#wireless[@]}; index++)); do
        if ! git apply --reverse --check "${wireless[index]}" >/dev/null 2>&1; then
            git apply "${wireless[index]}" || return 1
        fi
    done
    git apply --reverse --check - < <(cat "${wireless[@]}")
}

case "${1:-}" in
    --configure)
        configure_wifi7 "${2:-.config}"
        if [ "${2:-.config}" = '.config' ]; then
            verifier=verify_wext_wifi7
            if grep -qx 'CONFIG_PACKAGE_mtwifi-scripts=y' .config; then
                verifier=verify_ucode_wifi7
            fi
            make defconfig
            "$verifier" .config
            configure_luci
        fi
        exit ;;
    --verify-ucode) verify_ucode_wifi7 "${2:-.config}"; exit ;;
    --verify-wext) verify_wext_wifi7 "${2:-.config}"; exit ;;
    "") ;;
    *) echo "Unknown DIY mode: $1" >&2; exit 2 ;;
esac

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

mkdir -p package/community
pushd package/community
git clone --depth=1 -b dev https://github.com/fw876/helloworld
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
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
mtk_luci_packages=(
    luci-app-fan luci-app-sfp-status luci-app-adguardhome luci-app-unifi
    luci-app-modemband luci-app-turboacc-mtk luci-app-traffic luci-app-hqos-mtk rpcd-mod-router-status
)
for package in "${mtk_luci_packages[@]}"; do
    [ -f "luci-app/Luci-app/$package/Makefile" ] || {
        echo "MedyMa package missing: $package" >&2
        exit 1
    }
    rm -rf -- "$_mtk_source_root/package/mtk/applications/$package"
    rm -rf -- "$_mtk_source_root/feeds/luci/applications/$package" \
        "$_mtk_source_root/package/feeds/luci/$package"
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

sh "$GITHUB_WORKSPACE/scripts/fix-mihomo-source.sh" || exit 1

_go_values="feeds/packages/lang/golang/golang-values.mk"
_go_feed_default="$(sed -n 's/^GO_DEFAULT_VERSION:=[[:space:]]*//p' "$_go_values" 2>/dev/null)"
_go_default="$_go_feed_default"
case "$_go_default" in
    1.[0-9]|1.1[0-9]|1.2[0-6]) _go_default=1.27 ;;
esac
case "$_go_default" in
    ''|*[!0-9.]*)
        echo 'The 25.12 packages feed must provide its native versioned Go helpers' >&2
        exit 1
        ;;
esac
_go_recipe="feeds/packages/lang/golang/golang$_go_default/Makefile"
if ! grep -qxF "PKG_NAME:=golang$_go_default" "$_go_recipe"; then
    echo "Missing native Go $_go_default toolchain in the packages feed" >&2
    exit 1
fi
if [ "$_go_default" != "$_go_feed_default" ]; then
    sed -i "s/^GO_DEFAULT_VERSION:=.*/GO_DEFAULT_VERSION:=$_go_default/" "$_go_values" || exit 1
fi
# AdGuardHome 1.0 requires Go 1.27.4. Backport openwrt/packages db68036b
# while the ImmortalWrt feed still ships an earlier 1.27 patch release.
if [ "$_go_default" = 1.27 ] && grep -Eq '^GO_VERSION_PATCH:=[0-3]?$' "$_go_recipe"; then
    sed -i -e 's/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=4/' \
        -e 's/^GO_VERSION_RC:=.*/GO_VERSION_RC:=/' \
        -e 's/^PKG_HASH:=.*/PKG_HASH:=73cfb8571aec0c01177687db87163d46aa20e9779672772891aa17654d9a6099/' \
        "$_go_recipe" || exit 1
fi
rm -rf feeds/packages/net/mosdns
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash
popd

for f in \
    package/community/helloworld/simple-obfs/Makefile \
    package/community/helloworld/shadowsocks-libev/Makefile; do
    [ -f "$f" ] && sed -i '/^PKG_MIRROR_HASH:=/s/:=.*/:=skip/' "$f"
done

patch_makefile_dep \
    package/openwrt-packages/adguardhome/Makefile \
    'FRONTEND_HASH:=084bf3e00ca3e49487fc5a87270b4e1eb26617710ca6116b9e42ce90cb1ad358' \
    'FRONTEND_HASH:=skip'

f=feeds/packages/utils/containerd/Makefile
if [ ! -f "$f" ]; then
    echo "[DIY] containerd Makefile missing: $f" >&2
elif ! grep -q 'checklinkname=0' "$f"; then
    awk -v ins="MAKE_FLAGS += EXTRA_LDFLAGS='-s -w -checklinkname=0'" '{print} /^Build\/Compile=/ {print ins}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "[DIY] containerd: -checklinkname=0 injected=$(grep -c 'checklinkname=0' "$f")"
fi

if ! grep -q '_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile; then
    if grep -q '\$(if \$(findstring cortex-a53,\$(CONFIG_CPU_TYPE)),-march=armv8-a)' package/libs/mbedtls/Makefile; then
        sed -i '/$(if $(findstring cortex-a53,$(CONFIG_CPU_TYPE)),-march=armv8-a)/a TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile
  else
    echo 'TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' >> package/libs/mbedtls/Makefile
  fi
fi

rm -rf feeds/packages/net/onionshare-cli

if grep -q 'mkdir $(PKG_BUILD_DIR)/bin' feeds/packages/net/vpnc/Makefile 2>/dev/null; then
    sed -i '/mkdir $(PKG_BUILD_DIR)\/bin/s/mkdir /mkdir -p /' feeds/packages/net/vpnc/Makefile
fi

for recipe in package/mtk/drivers/mt_wifi7/Makefile package/mtk/drivers/mt_hwifi/Makefile; do
    [ -f "$recipe" ] || { echo "Required source recipe missing: $recipe" >&2; exit 1; }
done
./scripts/feeds update -a
for _luci_feed_patch in \
    "$GITHUB_WORKSPACE/patches/filogic/25.12/1004-luci-package-manager-apk-upload-untrusted-master.patch" \
    "$GITHUB_WORKSPACE/patches/filogic/25.12/1005-luci-dockerman-docker-menu.patch" \
    "$GITHUB_WORKSPACE/patches/filogic/25.12/1006-luci-argon-docker-menu-layout.patch" \
    "$GITHUB_WORKSPACE/patches/filogic/25.12/1007-luci-dhcpv4-hide-empty-identifiers.patch"; do
    if ! git apply --reverse --check "$_luci_feed_patch" >/dev/null 2>&1; then
        git apply --check "$_luci_feed_patch"
        git apply "$_luci_feed_patch"
    fi
done
sh "$GITHUB_WORKSPACE/scripts/build-argon-styles.sh" package/community/luci-theme-argon
if grep -q '^define Package/weechat-minimal$' feeds/packages/net/weechat/Makefile 2>/dev/null && \
    grep -qF ' +weechat ' feeds/luci/applications/luci-app-weechat/Makefile 2>/dev/null; then
    patch_makefile_dep feeds/luci/applications/luci-app-weechat/Makefile \
        ' +weechat ' ' +weechat-minimal '
    ./scripts/feeds update -i luci
fi
./scripts/feeds install -a
./scripts/feeds install c-ares udns
for package in "${mtk_luci_packages[@]}"; do
    rm -rf -- "feeds/luci/applications/$package" "package/feeds/luci/$package"
done
rm -rf feeds/packages/net/adguardhome package/feeds/packages/adguardhome
rm -rf feeds/packages/net/prosody feeds/packages/utils/telegraf
rm -rf package/feeds/packages/prosody package/feeds/packages/telegraf

for f in \
    package/base-files/files/etc/apk/repositories \
    package/base-files/files/etc/apk/repositories.d/* \
    package/utils/alpine-repositories/files/repositories; do
    [ -f "$f" ] && grep -q 'kiddin9' "$f" 2>/dev/null && sed -i '/kiddin9/d' "$f" 2>/dev/null || true
done

if [ ! -f package/libs/mbedtls/Makefile ]; then
  echo "WARNING: package/libs/mbedtls/Makefile not found" >&2
elif ! grep -q 'define Package/libmbedtls' package/libs/mbedtls/Makefile; then
  echo "WARNING: package/libs/mbedtls/Makefile does not define libmbedtls" >&2
fi

export GOEXPERIMENT=
export GOPROXY=https://proxy.golang.org,direct

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

patch_makefile_dep \
    package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch \
    'CONFIG_BOOTDELAY=30' \
    'CONFIG_BOOTDELAY=10'

sed -i 's/192.168.6.1/192.168.2.1/g' package/base-files/files/bin/config_generate
