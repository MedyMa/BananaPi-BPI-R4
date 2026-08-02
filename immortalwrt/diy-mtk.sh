#!/bin/bash
#
# diy-mtk.sh -- Community packages & config for chasey-dev build
#

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

# Remove upstream feeds replaced by community clones below
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
git clone --depth=1 https://github.com/1522042029/luci-app-socat
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
merge_package https://github.com/kenzok8/jell jell/adguardhome
# Fix broken default_username.patch: upstream zh-cn.json was reorganized since
# the patch was created (hunk context moved from ~L571 to ~L755, indentation
# changed from 4-space to 2-space). Replace with corrected hunk so the build
# does not fail at AdGuardHome prepare stage.
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
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/ddnsto
merge_package "-b main https://github.com/linkease/ddnsto-openwrt-package" ddnsto-openwrt-package/luci-app-ddnsto
merge_package "-b main https://github.com/linkease/nas-packages-luci" nas-packages-luci/luci/luci-app-baidudrive
merge_package "-b master https://github.com/linkease/nas-packages" nas-packages/network/services/baidudrive
popd

# luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# luci-app-OpenClash
mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash
popd

# Fix non-deterministic PKG_MIRROR_HASH in helloworld/shadowsocks-libev
patch_makefile_dep \
    package/community/helloworld/shadowsocks-libev/Makefile \
    'PKG_MIRROR_HASH:=b3898ad0a557bc8b0bbb2f3888101d461944239b0b7d4d4c6f164d73694a4595' \
    'PKG_MIRROR_HASH:=skip'

# simple-obfs: skip tarball hash (git archive + submodule produces non-deterministic hash)
patch_makefile_dep \
    package/community/helloworld/simple-obfs/Makefile \
    'PKG_MIRROR_HASH:=7a0154d2de18373e52783d1b64cf5204471049c2d2c64f0b3323d7f430aa4275' \
    'PKG_MIRROR_HASH:=skip'

# adguardhome: skip frontend hash (GitHub release asset hash is volatile)
patch_makefile_dep \
    package/community/package/openwrt-packages/adguardhome/Makefile \
    'FRONTEND_HASH:=084bf3e00ca3e49487fc5a87270b4e1eb26617710ca6116b9e42ce90cb1ad358' \
    'FRONTEND_HASH:=skip'

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

# Drop onionshare-cli (unresolved metadata, not in our config)
rm -rf feeds/packages/net/onionshare-cli

[ -f feeds/luci/applications/luci-app-package-manager/root/usr/libexec/package-manager-call ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/25.12/1004-luci-package-manager-apk-upload-untrusted-master.patch"

# vpnc: add -p to mkdir for idempotency
if grep -q 'mkdir $(PKG_BUILD_DIR)/bin' feeds/packages/net/vpnc/Makefile 2>/dev/null; then
    sed -i '/mkdir $(PKG_BUILD_DIR)\/bin/s/mkdir /mkdir -p /' feeds/packages/net/vpnc/Makefile
fi

# hostapd: keep MTK private MLO PMKSA patch out of non-BE builds
patch_makefile_dep \
    package/network/services/hostapd/patches/975-mtk-mlo-pass-pmksa-link-address.patch \
    '@@ -1158,6 +1158,18 @@ static int sae_assign_vlan(struct hostap' \
    '@@ -1158,6 +1158,21 @@ static int sae_assign_vlan(struct hostap' \
    && echo "[DIY] hostapd 975 hunk header: 18 -> 21" \
    || echo "[DIY] hostapd 975 hunk header: SKIP (already patched or not found)"
patch_makefile_dep \
    package/network/services/hostapd/patches/975-mtk-mlo-pass-pmksa-link-address.patch \
    '+	bool is_ml = ap_sta_has_ml_rsn(hapd, sta);
+
+	if (is_ml) {
+		u8 link_id = sta->mld_assoc_link_id;
+
+		/* PMKSA is keyed by MLD address; driver sync also needs link addr. */
+		pmksa_addr = sta->mld_info.common_info.mld_addr;
+		pmksa_link_addr = sta->mld_info.links[link_id].peer_addr;
+	}' \
    '+	bool is_ml = false;
+
+#ifdef CONFIG_IEEE80211BE
+	is_ml = ap_sta_has_ml_rsn(hapd, sta);
+	if (is_ml) {
+		u8 link_id = sta->mld_assoc_link_id;
+
+		/* PMKSA is keyed by MLD address; driver sync also needs link addr. */
+		pmksa_addr = sta->mld_info.common_info.mld_addr;
+		pmksa_link_addr = sta->mld_info.links[link_id].peer_addr;
+	}
+#endif /* CONFIG_IEEE80211BE */' \
    && echo "[DIY] hostapd 975 guard: #ifdef CONFIG_IEEE80211BE injected" \
    || echo "[DIY] hostapd 975 guard: SKIP (already patched or not found)"

# MTK Wi-Fi profiles: replace chasey-dev version with padavanonly's mt7990-only build
# (chasey-dev version references nonexistent mt7622/mt7615 files and uses broken
#  shell command-substitution for Kconfig values)
rm -rf package/mtk/drivers/wifi-profile
git clone --depth=1 -b mt798x-mt799x-6.6-mtwifi \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6.git \
    /tmp/padavanonly-wifi-profile >/dev/null 2>&1
mv /tmp/padavanonly-wifi-profile/package/mtk/drivers/wifi-profile \
    package/mtk/drivers/wifi-profile
rm -rf /tmp/padavanonly-wifi-profile
# Remove legacy wifi_jedi → /sbin/wifi install (conflicts with ImmortalWrt 25.12 wifi-scripts)
sed -i 's|$(INSTALL_BIN) ./files/common/wifi_jedi $(1)/sbin/wifi|# DIY: removed – conflicts with wifi-scripts|' \
    package/mtk/drivers/wifi-profile/Makefile
echo "[DIY] wifi-profile replaced with padavanonly mt7990-only version"

# MTK mt_wifi7: expand Kconfig card names in make, not in the shell
if [ -f "package/mtk/drivers/mt_wifi7/Makefile" ] && \
   grep -q 'CONFIG_first_card_name' "package/mtk/drivers/mt_wifi7/Makefile"; then
    sed -i 's/$$(CONFIG_first_card_name)/$(CONFIG_first_card_name)/g; s/$$(CONFIG_second_card_name)/$(CONFIG_second_card_name)/g; s/$$(CONFIG_third_card_name)/$(CONFIG_third_card_name)/g' \
        "package/mtk/drivers/mt_wifi7/Makefile"
    echo "[DIY] mt_wifi7/Makefile: CONFIG_*_card_name fixed for make expansion"
fi

# datconf: disable parallel build (5 sub-packages share one CMake tree, race with -j>1)
if [ -f "package/mtk/applications/datconf/Makefile" ] && \
   ! grep -q 'PKG_BUILD_PARALLEL' "package/mtk/applications/datconf/Makefile"; then
    sed -i '/^PKG_RELEASE:=/a PKG_BUILD_PARALLEL:=0' "package/mtk/applications/datconf/Makefile"
    echo "[DIY] datconf parallel build disabled"
fi

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

# Pin kernel Kconfig symbols to avoid interactive prompts (NEW symbols)
CFG="target/linux/mediatek/filogic/config-6.12"
if [ -f "$CFG" ]; then
    for sym in MEDIATEK_2P5GE_PHY NET_MEDIATEK_HNAT MEDIATEK_NETSYS_V3 NETFILTER; do
        case "$sym" in
            MEDIATEK_2P5GE_PHY) val="# CONFIG_${sym} is not set" ;;
            NET_MEDIATEK_HNAT)   val="CONFIG_${sym}=m" ;;
            *)                   val="CONFIG_${sym}=y" ;;
        esac
        sed -i "/^CONFIG_${sym}=/d; /^# CONFIG_${sym} is not set$/d" "$CFG"
        echo "$val" >> "$CFG"
    done
    echo "[DIY] Kernel Kconfig symbols pinned"
fi
