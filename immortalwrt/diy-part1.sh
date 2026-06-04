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

# Remove feeds packages that will be replaced by community clones below.
# This MUST run after the workflow's initial feeds update but BEFORE feeds install.
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
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-turboacc-mtk
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
# merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/relevance/ddnsto
# merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages-luci" nas-packages-luci/luci/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages" nas-packages/network/services/ddnsto
popd

# Replace immortalwrt mt76 with BPI-R4PRO custom mt76;
# also pull mtk_hnat driver + mtk_eth_dbg dependency + hnat kernel patches.
rm -rf package/kernel/mt76
git clone --depth=1 --filter=blob:none --sparse \
    https://github.com/BPI-SINOVOIP/BPI-R4PRO-8X-OPENWRT-V24.10.0-Master-Devel \
    bpi-r4pro-src
pushd bpi-r4pro-src
git sparse-checkout set \
    package/kernel/mt76 \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek \
    target/linux/mediatek/files-6.6/include \
    target/linux/mediatek/patches-6.6
popd

mv bpi-r4pro-src/package/kernel/mt76 package/kernel/mt76

# 39c960c3 already contains the rxfilter default change from BPI patch 0001.
# Keep it out of the patch stack to avoid a reversed-patch failure.
rm -f package/kernel/mt76/patches/0001-mtk-mt76-mt7996-config-rxfilter-to-drop-other-unicas.patch

# 2ab64980 already carries the 0004 behavior in refactored mt76 dma init code.
rm -f package/kernel/mt76/patches/0004-mtk-mt76-mt7996-Remove-wed-rro-ring-add-napi-at-init.patch

# Rebase 0003/0005/0008 onto 2ab64980 via workspace patch files instead of
# embedding patch bodies in this script.
cp "$GITHUB_WORKSPACE/patches/filogic/mt76/0003-mtk-mt76-mt7996-Fix-call-trace-happened-when-wed-att.patch" \
    package/kernel/mt76/patches/0003-mtk-mt76-mt7996-Fix-call-trace-happened-when-wed-att.patch
cp "$GITHUB_WORKSPACE/patches/filogic/mt76/0005-mtk-mt76-mt7996-Remove-wed_stop-during-L1-SER.patch" \
    package/kernel/mt76/patches/0005-mtk-mt76-mt7996-Remove-wed_stop-during-L1-SER.patch
cp "$GITHUB_WORKSPACE/patches/filogic/mt76/0008-mtk-mt76-mt7996-add-critical-update-support.patch" \
    package/kernel/mt76/patches/0008-mtk-mt76-mt7996-add-critical-update-support.patch
perl -0pi -e 's/\r\n/\n/g; s/\r/\n/g' \
    package/kernel/mt76/patches/0003-mtk-mt76-mt7996-Fix-call-trace-happened-when-wed-att.patch \
    package/kernel/mt76/patches/0005-mtk-mt76-mt7996-Remove-wed_stop-during-L1-SER.patch \
    package/kernel/mt76/patches/0008-mtk-mt76-mt7996-add-critical-update-support.patch

# Keep the mt76 package Makefile bump as a standalone patch, so the version
# update is tracked in the workspace and validated with patch(1).
(cd package/kernel/mt76 && patch -p1 < "$GITHUB_WORKSPACE/patches/filogic/mt76/1005-mt76-makefile-2ab64980.patch")

# Apply BPI-R4PRO mt76 compatibility after the vendor patch series.
# The compat patch in this workspace may contain mixed line endings.
# Normalize it to LF so it matches the post-patch mt76 sources in CI.
cp "$GITHUB_WORKSPACE/patches/filogic/1004-mt76-immortalwrt-24.10-compat.patch" \
    package/kernel/mt76/mt76-compat.patch
perl -0pi -e 's/\r\n/\n/g; s/\r/\n/g' package/kernel/mt76/mt76-compat.patch
cp "$GITHUB_WORKSPACE/patches/filogic/mt76/compat-fixup.sh" \
    package/kernel/mt76/compat-fixup.sh
perl -0pi -e 's/\r\n/\n/g; s/\r/\n/g' package/kernel/mt76/compat-fixup.sh
chmod 0755 package/kernel/mt76/compat-fixup.sh
{
    printf '\n'
    printf '%s\n' 'define Build/Prepare'
    printf '\t%s\n' '$(call Build/Prepare/Default)'
    printf '\t%s\n' '(cd $(PKG_BUILD_DIR) && patch -p1 < $(TOPDIR)/package/kernel/mt76/mt76-compat.patch)'
    printf '\t%s\n' '$(TOPDIR)/package/kernel/mt76/compat-fixup.sh $(PKG_BUILD_DIR)'
    printf '%s\n' 'endef'
} > package/kernel/mt76/compat-prepare.mk
awk 'FNR == NR { block = block $0 "\n"; next }
    /^\$\(eval \$\(call KernelPackage,/ && !done { print block; done = 1 }
         { print }' \
        package/kernel/mt76/compat-prepare.mk package/kernel/mt76/Makefile \
        > package/kernel/mt76/Makefile.tmp \
    && mv package/kernel/mt76/Makefile.tmp package/kernel/mt76/Makefile
rm -f package/kernel/mt76/compat-prepare.mk

mkdir -p target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek
cp -r bpi-r4pro-src/target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/
cp bpi-r4pro-src/target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_dbg.{c,h} \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/

# ra_nat.h and other kernel headers needed by hnat/skbuff patches
if [ -d bpi-r4pro-src/target/linux/mediatek/files-6.6/include ]; then
    cp -r bpi-r4pro-src/target/linux/mediatek/files-6.6/include/. \
        target/linux/mediatek/files-6.6/include/
fi

for patch in \
    999-2735-netfilter-nf_flow_table-support-hw-offload-through-v.patch \
    999-2736-net-8021q-support-hardware-flow-table-offload.patch \
    999-2737-net-bridge-support-hardware-flow-table-offload.patch \
    999-2738-net-pppoe-support-hardware-flow-table-offload.patch \
    999-2739-net-dsa-support-hardware-flow-table-offload.patch \
    999-2740-net-macvlan-support-hardware-flow-table-offload.patch \
    999-2741-mtkhnat-add-support-for-virtual-interface-a.patch \
    "999-2742-mtkhnat-tnl-interface-offload-check.patch.patch" \
    999-2743-mtkhnat-ipv6-fix-pskb-expand-head-limitatio.patch \
    999-2744-mtk-gso-skb-headroom-copy.patch \
    999-2745-mtkhnat-add-mtkhnat-driver-support.patch
do
    src="bpi-r4pro-src/target/linux/mediatek/patches-6.6/$patch"
    [ -f "$src" ] && cp "$src" target/linux/mediatek/patches-6.6/
done

# 999-2746 failed to apply (context mismatch); inject its defines directly into
# hnat.h so hnat.c compiles. MTK_FE_INT_STATUS2 is called MTK_INT_STATUS2 in
# ImmortalWrt — provide both names so the driver builds regardless of base.
# MTK_QTX_PER_PAGE: defined in BPI-R4PRO's mtk_eth_soc patches (not copied).
cat >> target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat/hnat.h << 'EOF'

/* PPE flow-check interrupt registers (injected; normally patched via 999-2746) */
#ifndef MTK_FE_INT_STATUS2
#define MTK_FE_INT_STATUS2		0x28
#endif
#ifndef MTK_FE_INT_ENABLE2
#define MTK_FE_INT_ENABLE2		0x2C
#endif
#ifndef MTK_FE_INT2_PPE0_FLOW_CHK
#define MTK_FE_INT2_PPE0_FLOW_CHK	BIT(28)
#endif
#ifndef MTK_FE_INT2_PPE1_FLOW_CHK
#define MTK_FE_INT2_PPE1_FLOW_CHK	BIT(29)
#endif

/* QDMA QTX per page (from BPI-R4PRO mtk_eth_soc patches; NETSYS V3 = 16) */
#ifndef MTK_QTX_PER_PAGE
#define MTK_QTX_PER_PAGE		16
#endif
EOF

# flow_offload_hw_path.tnl_type is added by BPI-R4PRO's 999-4100 TOPS patch
# which we do not carry. Keep the local inject patch in the workspace instead
# of embedding it here.
cp "$GITHUB_WORKSPACE/patches/filogic/mt76/999-2741b-flow-offload-add-tnl-type.patch" \
    target/linux/mediatek/patches-6.6/999-2741b-flow-offload-add-tnl-type.patch
perl -0pi -e 's/\r\n/\n/g; s/\r/\n/g' \
    target/linux/mediatek/patches-6.6/999-2741b-flow-offload-add-tnl-type.patch

rm -rf bpi-r4pro-src

# Kernel config symbols introduced by BPI-R4PRO hnat patches (999-2745).
# Without explicit values, syncconfig blocks in non-interactive CI.
# MT7988A is NETSYS V3; V3 selects V2 as base, so both are needed.
for kcfg in \
    CONFIG_MEDIATEK_NETSYS_V2=y \
    CONFIG_MEDIATEK_NETSYS_V3=y \
    CONFIG_MEDIATEK_NETSYS_RX_V2=y \
    CONFIG_NET_MEDIATEK_HNAT=m
do
    key="${kcfg%%=*}"
    grep -qF "$key" target/linux/mediatek/filogic/config-6.6 || \
        echo "$kcfg" >> target/linux/mediatek/filogic/config-6.6
done

# add luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# add luci-app-OpenClash
mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash
popd

# merge_package "-b openwrt-24.10-6.6 https://github.com/padavanonly/immortalwrt-mt798x-6.6" immortalwrt-mt798x-6.6/package/mtk/applications/mtkhqos_util

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
