#!/bin/bash
# diy-mtk.sh -- Community packages & config for chasey-dev build

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

# containerd vendors cpuid v2.0.4, which trips the Go >= 1.23 linkname check
f=feeds/packages/utils/containerd/Makefile
if [ -f "$f" ] && ! grep -q 'checklinkname=0' "$f"; then
    printf '\nMAKE_FLAGS += EXTRA_LDFLAGS=-checklinkname=0\n' >> "$f"
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

# hostapd 975 (MTK MLO PMKSA): sta->mld_* only exist under CONFIG_IEEE80211BE and
# this tree builds wpad without 11BE, so the MLO block must be compiled out.
# Regex guards survive upstream churn; bump the hunk line count by +3.
_mt975="package/network/services/hostapd/patches/975-mtk-mlo-pass-pmksa-link-address.patch"
if [ -f "$_mt975" ]; then
    if perl -0777 -e '
        local $/;
        my $txt = <STDIN>;
        my $n = 0;
        $n++ if $txt =~ s/^(\+\t)bool is_ml = ap_sta_has_ml_rsn\(hapd, sta\);\n/${1}bool is_ml = false;\n+#ifdef CONFIG_IEEE80211BE\n${1}is_ml = ap_sta_has_ml_rsn(hapd, sta);\n/m;
        $n++ if $txt =~ s/^(\+\tif \(is_ml\) \{.*?^(\+\t)\}\n)/$1+#endif \/* CONFIG_IEEE80211BE *\/\n/ms;
        if ($n == 2) {
            $txt =~ s/^(\@\@ [^\n]*\+[0-9]+,)(\d+)( \@\@(?=[^\n]*\n \n void sae_accept_sta))/sprintf("%s%d%s", $1, $2 + 3, $3)/me;
            print $txt;
            exit 0;
        }
        exit 2;
    ' < "$_mt975" > "$_mt975.new"; then
        mv "$_mt975.new" "$_mt975"
        echo "[DIY] hostapd 975 guard: #ifdef CONFIG_IEEE80211BE injected (regex, hunk count +3)"
    else
        rm -f "$_mt975.new"
        echo "[DIY] hostapd 975 guard: SKIP - 975 patch format changed, MLO block left unguarded" >&2
    fi
fi

# wifi-profile: use padavanonly's mt7990-only build (chasey-dev's references
# nonexistent files and breaks on shell command-substitution)
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

# MTK mt_wifi7: map OpenWrt Kconfig names to vendor Kbuild names
_mt_wifi7_makefile="package/mtk/drivers/mt_wifi7/Makefile"
_mt_wifi7_kconfig_anchor='$(foreach c, $(PKG_KCONFIG),$(if $(CONFIG_MTK_WIFI7_$c),CONFIG_$(c)=$(CONFIG_MTK_WIFI7_$(c)))) \'
_mt_wifi7_kconfig_replacement='$(foreach c, $(PKG_KCONFIG),$(if $(CONFIG_MTK_WIFI7_$c),CONFIG_$(c)=$(CONFIG_MTK_WIFI7_$(c)))) \
		CONFIG_WIFI_DRIVER=$(CONFIG_MTK_WIFI7_DRIVER) \
		CONFIG_DOT11_HE_AX=$(CONFIG_MTK_WIFI7_DOT11_AX_SUPPORT) \
		CONFIG_DOT11_EHT_BE=$(CONFIG_MTK_WIFI7_DOT11_BE_SUPPORT) \'

if [ ! -f "$_mt_wifi7_makefile" ]; then
    echo "Required mt_wifi7 Makefile not found: $_mt_wifi7_makefile" >&2
    exit 1
elif grep -qE '^[[:space:]]*CONFIG_WIFI_DRIVER=\$\(CONFIG_MTK_WIFI7_DRIVER\)[[:space:]]*\\$' "$_mt_wifi7_makefile" && \
     grep -qE '^[[:space:]]*CONFIG_DOT11_HE_AX=\$\(CONFIG_MTK_WIFI7_DOT11_AX_SUPPORT\)[[:space:]]*\\$' "$_mt_wifi7_makefile" && \
     grep -qE '^[[:space:]]*CONFIG_DOT11_EHT_BE=\$\(CONFIG_MTK_WIFI7_DOT11_BE_SUPPORT\)[[:space:]]*\\$' "$_mt_wifi7_makefile"; then
    echo "[DIY] mt_wifi7/Makefile: vendor Kbuild mappings already present"
elif grep -qF "$_mt_wifi7_kconfig_anchor" "$_mt_wifi7_makefile"; then
    patch_makefile_dep \
        "$_mt_wifi7_makefile" \
        "$_mt_wifi7_kconfig_anchor" \
        "$_mt_wifi7_kconfig_replacement" || exit 1
    echo "[DIY] mt_wifi7/Makefile: vendor Kbuild mappings injected"
else
    echo "Failed to locate mt_wifi7 Kconfig compile anchor in $_mt_wifi7_makefile" >&2
    exit 1
fi

# MTK mt_wifi7: Linux 6.12 moved the generic unaligned helpers out of asm/.
_mt_wifi7_unaligned_patch_src="$GITHUB_WORKSPACE/patches/filogic/25.12/1006-mt_wifi7-linux-6.12-unaligned-header.patch"
_mt_wifi7_unaligned_patch_dst="package/mtk/drivers/mt_wifi7/patches/900-linux-6.12-unaligned-header.patch"

if [ ! -f "$_mt_wifi7_unaligned_patch_src" ]; then
    echo "Required mt_wifi7 compatibility patch not found: $_mt_wifi7_unaligned_patch_src" >&2
    exit 1
fi

install -Dm0644 "$_mt_wifi7_unaligned_patch_src" "$_mt_wifi7_unaligned_patch_dst"
echo "[DIY] mt_wifi7: Linux 6.12 unaligned header compatibility patch installed"

# mt_wifi7: GCC 14 -Werror rejects missing AC_NUM/PMKSA declarations (kept
# separate from the unaligned fix so either patch can be dropped)
_mt_wifi7_declarations_patch_src="$GITHUB_WORKSPACE/patches/filogic/25.12/1007-mt_wifi7-fix-missing-declarations.patch"
_mt_wifi7_declarations_patch_dst="package/mtk/drivers/mt_wifi7/patches/901-fix-missing-declarations.patch"

if [ ! -f "$_mt_wifi7_declarations_patch_src" ]; then
    echo "Required mt_wifi7 compatibility patch not found: $_mt_wifi7_declarations_patch_src" >&2
    exit 1
fi

install -Dm0644 "$_mt_wifi7_declarations_patch_src" "$_mt_wifi7_declarations_patch_dst"
echo "[DIY] mt_wifi7: GCC 14 missing declarations compatibility patch installed"

# mt_wifi7: GCC 14 -Werror rejects MAX_TRANSMIT_POWER in rt_channel.c (vendor
# only defines it locally in bcn.c)
_mt_wifi7_max_tx_power_patch_src="$GITHUB_WORKSPACE/patches/filogic/25.12/1008-mt_wifi7-fix-max-transmit-power.patch"
_mt_wifi7_max_tx_power_patch_dst="package/mtk/drivers/mt_wifi7/patches/902-fix-max-transmit-power.patch"

if [ ! -f "$_mt_wifi7_max_tx_power_patch_src" ]; then
    echo "Required mt_wifi7 compatibility patch not found: $_mt_wifi7_max_tx_power_patch_src" >&2
    exit 1
fi

install -Dm0644 "$_mt_wifi7_max_tx_power_patch_src" "$_mt_wifi7_max_tx_power_patch_dst"
echo "[DIY] mt_wifi7: MAX_TRANSMIT_POWER declaration compatibility patch installed"

# mt_wifi7: RT_CFG80211_SUPPORT makes owe_cmm.h skip sae_cmm.h while sec_cmm.h
# still compiles the SAE structs -> "field has incomplete type". Align the
# include guard with the field guard.
_mt_wifi7_sae_patch_src="$GITHUB_WORKSPACE/patches/filogic/25.12/1009-mt_wifi7-fix-incomplete-sae-structs.patch"
_mt_wifi7_sae_patch_dst="package/mtk/drivers/mt_wifi7/patches/903-fix-incomplete-sae-structs.patch"

if [ ! -f "$_mt_wifi7_sae_patch_src" ]; then
    echo "Required mt_wifi7 compatibility patch not found: $_mt_wifi7_sae_patch_src" >&2
    exit 1
fi

install -Dm0644 "$_mt_wifi7_sae_patch_src" "$_mt_wifi7_sae_patch_dst"
echo "[DIY] mt_wifi7: incomplete SAE struct compatibility patch installed"

# mt_wifi7: cac_required is MAP-guarded but used unconditionally by rt_channel.c
# and cmm_rdm_mt.c -> move the field out of the MAP guard
_mt_wifi7_cac_patch_src="$GITHUB_WORKSPACE/patches/filogic/25.12/1010-mt_wifi7-fix-cac-required-field.patch"
_mt_wifi7_cac_patch_dst="package/mtk/drivers/mt_wifi7/patches/904-fix-cac-required-field.patch"

if [ ! -f "$_mt_wifi7_cac_patch_src" ]; then
    echo "Required mt_wifi7 compatibility patch not found: $_mt_wifi7_cac_patch_src" >&2
    exit 1
fi

install -Dm0644 "$_mt_wifi7_cac_patch_src" "$_mt_wifi7_cac_patch_dst"
echo "[DIY] mt_wifi7: cac_required field compatibility patch installed"

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
