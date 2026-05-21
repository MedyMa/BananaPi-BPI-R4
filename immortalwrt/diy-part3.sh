#!/bin/bash

# Merge_package
function merge_package(){
    repo="${1##*/}"
    pkg="${2##*/}"
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

patch_literal_block() {
    local file_path="$1"
    local old_text="$2"
    local new_text="$3"
    local perl_status

    [ -f "$file_path" ] || return 0

    PATCH_NEW_TEXT="$new_text" \
        perl -0ne 'BEGIN { $new = $ENV{"PATCH_NEW_TEXT"}; }
            exit(index($_, $new) >= 0 ? 0 : 1);' "$file_path"
    if [ "$?" -eq 0 ]; then
        return 0
    fi

    PATCH_OLD_TEXT="$old_text" PATCH_NEW_TEXT="$new_text" \
        perl -0pi -e 'BEGIN { $old = $ENV{"PATCH_OLD_TEXT"}; $new = $ENV{"PATCH_NEW_TEXT"}; }
            $count = s/\Q$old\E/$new/g;
            END { exit($count > 0 ? 0 : 2); }' "$file_path"
    perl_status=$?

    [ "$perl_status" -eq 0 ] || {
        echo "Failed to apply literal block patch to $file_path" >&2
        return "$perl_status"
    }
}

sparse_checkout_copy() {
    local repo_url="$1"
    local repo_branch="$2"
    local source_path="$3"
    local dest_path="$4"
    local checkout_prefix="$5"
    local clone_mode="${6:-partial}"
    local checkout_dir

    checkout_dir="$(sparse_checkout_init "$repo_url" "$repo_branch" "$checkout_prefix" "$clone_mode")"
    git -C "$checkout_dir" sparse-checkout set --skip-checks "$source_path"

    sparse_checkout_copy_from_dir "$checkout_dir" "$source_path" "$dest_path"
    rm -rf "$checkout_dir"
}

sparse_checkout_init() {
    local repo_url="$1"
    local repo_branch="$2"
    local checkout_prefix="$3"
    local clone_mode="${4:-partial}"
    local temp_root="${TMPDIR:-/tmp}"
    local checkout_dir

    if [ -n "$checkout_prefix" ]; then
        checkout_dir="$(mktemp -d "$temp_root/${checkout_prefix}.XXXXXX")"
    else
        checkout_dir="$(mktemp -d "$temp_root/sparse-checkout.XXXXXX")"
    fi

    if [ "$clone_mode" = "full" ]; then
        git clone --depth=1 --sparse -b "$repo_branch" "$repo_url" "$checkout_dir"
    else
        git clone --depth=1 --filter=blob:none --sparse -b "$repo_branch" "$repo_url" "$checkout_dir"
    fi

    printf '%s\n' "$checkout_dir"
}

sparse_checkout_copy_from_dir() {
    local checkout_dir="$1"
    local source_path="$2"
    local dest_path="$3"

    rm -rf "$dest_path"
    mkdir -p "$(dirname "$dest_path")"
    cp -a "$checkout_dir/$source_path" "$dest_path"
}

sparse_checkout_copy_many() {
    local repo_url="$1"
    local repo_branch="$2"
    local checkout_prefix="$3"
    local clone_mode="${4:-partial}"
    local checkout_dir
    local source_paths=()
    local dest_paths=()
    local index

    shift 4
    while [ "$#" -gt 0 ]; do
        source_paths+=("$1")
        dest_paths+=("$2")
        shift 2
    done

    checkout_dir="$(sparse_checkout_init "$repo_url" "$repo_branch" "$checkout_prefix" "$clone_mode")"
    git -C "$checkout_dir" sparse-checkout set --skip-checks "${source_paths[@]}"

    for index in "${!source_paths[@]}"; do
        sparse_checkout_copy_from_dir "$checkout_dir" "${source_paths[$index]}" "${dest_paths[$index]}"
    done

    rm -rf "$checkout_dir"
}

apply_workspace_patch() {
    local patch_file="$1"

    [ -f "$patch_file" ] || return 0

    if git apply --ignore-space-change --ignore-whitespace --reverse --check "$patch_file" >/dev/null 2>&1; then
        return 0
    fi

    git apply --ignore-space-change --ignore-whitespace "$patch_file"
}

apply_wireless_regdb_overlay() {
    local regdb_dir="package/firmware/wireless-regdb"

    [ -d "$regdb_dir" ] || return 0

    rm -f "$regdb_dir"/patches/*.patch
    mkdir -p "$regdb_dir/patches"
    cp -f "$GITHUB_WORKSPACE/patches/filogic/500-world-regd-5GHz.patch" \
        "$regdb_dir/patches/500-world-regd-5GHz.patch"
    cp -f "$GITHUB_WORKSPACE/patches/filogic/600-custom-change-txpower-and-dfs.patch" \
        "$regdb_dir/patches/600-custom-change-txpower-and-dfs.patch"
    cp -f "$GITHUB_WORKSPACE/patches/filogic/regdb.Makefile" \
        "$regdb_dir/Makefile"
}

apply_wifi_mlo_uci_backport() {
    local anchor="package/network/config/wifi-scripts/files-ucode/usr/share/ucode/wifi/supplicant.uc"

    [ -f "$anchor" ] || return 0
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/996-wifi-scripts-add-mlo-uci-passthrough.patch"
}


rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-modemband
rm -rf feeds/luci/applications/luci-app-adguardhome
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
# Clone community packages to package/community
mkdir -p package/community
pushd package/community
git clone --depth=1 https://github.com/fw876/helloworld
# rm -rf helloworld/{naiveproxy,shadowsocks-libev,shadowsocksr-libev,shadow-tls,simple-obfs,tcping,tuic-client,v2ray-plugin,xray-core,xray-plugin}
rm -rf helloworld/{naiveproxy}
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
git clone --depth=1 https://github.com/1522042029/luci-app-socat
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-fan
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-sfp-status
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-modemband
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages-luci" nas-packages-luci/luci/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages" nas-packages/network/services/ddnsto
popd

# Import the MTK vendor 6.6 package tree that is not shipped in ImmortalWrt openwrt-24.10.
sparse_checkout_copy \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    package/mtk \
    package/mtk \
    vendor-mtk

# datconf is selected by the MT7988 defconfig and expects its vendor tarball to
# already exist under dl/ because the package Makefile has no source URL.
# MTK HNAT is not present in the upstream 24.10 mediatek target, but the
# imported MTK WiFi/WARP stack selects and depends on it.
# The vendor HNAT patches sit on top of a contiguous mtk_eth_soc patch train
# plus companion debug/reset sources. Cherry-picking later patches without that
# base breaks 24.10 kernel patch application. Keep the main asset import on the
# mtwifi branch for WARP/HNAT support, but source the 3000-series PPE QoS and
# roaming patches from the 24.10-rebased branch below; the mtwifi variant of
# 999-3007 expects extra ftnetlink changes and no longer applies cleanly.
sparse_checkout_copy_many \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    vendor-mtk-assets \
    partial \
    dl/datconf-757f9679.tar.bz2 \
    dl/datconf-757f9679.tar.bz2 \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_dbg.c \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_dbg.c \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_dbg.h \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_dbg.h \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_reset.c \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_reset.c \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_reset.h \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_reset.h \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat \
    target/linux/mediatek/files-6.6/include/net/ra_nat.h \
    target/linux/mediatek/files-6.6/include/net/ra_nat.h \
    target/linux/mediatek/patches-6.6/999-2700-net-ethernet-mtk_eth_soc-add-mdio-reset-delay.patch \
    target/linux/mediatek/patches-6.6/999-2700-net-ethernet-mtk_eth_soc-add-mdio-reset-delay.patch \
    target/linux/mediatek/patches-6.6/999-2701-net-ethernet-mtk_eth_soc-remove-pextp-reset.patch \
    target/linux/mediatek/patches-6.6/999-2701-net-ethernet-mtk_eth_soc-remove-pextp-reset.patch \
    target/linux/mediatek/patches-6.6/999-2702-net-ethernet-mtk_eth_soc-revise-xgmac-force-mode.patch \
    target/linux/mediatek/patches-6.6/999-2702-net-ethernet-mtk_eth_soc-revise-xgmac-force-mode.patch \
    target/linux/mediatek/patches-6.6/999-2704-net-ethernet-mtk_eth_soc-revise-mdc-divider-configur.patch \
    target/linux/mediatek/patches-6.6/999-2704-net-ethernet-mtk_eth_soc-revise-mdc-divider-configur.patch \
    target/linux/mediatek/patches-6.6/999-2705-net-ethernet-mtk_eth_soc-support-proprietary-debugfs.patch \
    target/linux/mediatek/patches-6.6/999-2705-net-ethernet-mtk_eth_soc-support-proprietary-debugfs.patch \
    target/linux/mediatek/patches-6.6/999-2706-net-ethernet-mtk_eth_soc-support-forced-reset-contro.patch \
    target/linux/mediatek/patches-6.6/999-2706-net-ethernet-mtk_eth_soc-support-forced-reset-contro.patch \
    target/linux/mediatek/patches-6.6/999-2707-net-ethernet-mtk_eth_soc-add-hw-dump-for-forced-rese.patch \
    target/linux/mediatek/patches-6.6/999-2707-net-ethernet-mtk_eth_soc-add-hw-dump-for-forced-rese.patch \
    target/linux/mediatek/patches-6.6/999-2708-net-ethernet-mtk_eth_soc-support-ethernet-passive-mu.patch \
    target/linux/mediatek/patches-6.6/999-2708-net-ethernet-mtk_eth_soc-support-ethernet-passive-mu.patch \
    target/linux/mediatek/patches-6.6/999-2709-net-ethernet-mtk_eth_soc-fix-panic-issue-with-napi_enable.patch \
    target/linux/mediatek/patches-6.6/999-2709-net-ethernet-mtk_eth_soc-fix-panic-issue-with-napi_enable.patch \
    target/linux/mediatek/patches-6.6/999-2710-net-ethernet-mtk_eth_soc-add-rss-lro-reg.patch \
    target/linux/mediatek/patches-6.6/999-2710-net-ethernet-mtk_eth_soc-add-rss-lro-reg.patch \
    target/linux/mediatek/patches-6.6/999-2711-net-ethernet-mtk_eth_soc-add-rss-support.patch \
    target/linux/mediatek/patches-6.6/999-2711-net-ethernet-mtk_eth_soc-add-rss-support.patch \
    target/linux/mediatek/patches-6.6/999-2712-net-ethernet-mtk_eth_soc-add-lro-support.patch \
    target/linux/mediatek/patches-6.6/999-2712-net-ethernet-mtk_eth_soc-add-lro-support.patch \
    target/linux/mediatek/patches-6.6/999-2713-net-ethernet-mtk_eth_soc-refactor-SER-monitor.patch \
    target/linux/mediatek/patches-6.6/999-2713-net-ethernet-mtk_eth_soc-refactor-SER-monitor.patch \
    target/linux/mediatek/patches-6.6/999-2735-netfilter-nf_flow_table-support-hw-offload-through-v.patch \
    target/linux/mediatek/patches-6.6/999-2735-netfilter-nf_flow_table-support-hw-offload-through-v.patch \
    target/linux/mediatek/patches-6.6/999-2736-net-8021q-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2736-net-8021q-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2737-net-bridge-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2737-net-bridge-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2738-net-pppoe-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2738-net-pppoe-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2739-net-dsa-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2739-net-dsa-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2740-net-macvlan-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2740-net-macvlan-support-hardware-flow-table-offload.patch \
    target/linux/mediatek/patches-6.6/999-2741-mtkhnat-add-support-for-virtual-interface-a.patch \
    target/linux/mediatek/patches-6.6/999-2741-mtkhnat-add-support-for-virtual-interface-a.patch \
    target/linux/mediatek/patches-6.6/999-2742-mtkhnat-tnl-interface-offload-check.patch.patch \
    target/linux/mediatek/patches-6.6/999-2742-mtkhnat-tnl-interface-offload-check.patch.patch \
    target/linux/mediatek/patches-6.6/999-2743-mtkhnat-ipv6-fix-pskb-expand-head-limitatio.patch \
    target/linux/mediatek/patches-6.6/999-2743-mtkhnat-ipv6-fix-pskb-expand-head-limitatio.patch \
    target/linux/mediatek/patches-6.6/999-2745-mtkhnat-add-mtkhnat-driver-support.patch \
    target/linux/mediatek/patches-6.6/999-2745-mtkhnat-add-mtkhnat-driver-support.patch \
    target/linux/mediatek/patches-6.6/999-2746-mtkhnat-add-support-ppe-flow-check-interrupt.patch \
    target/linux/mediatek/patches-6.6/999-2746-mtkhnat-add-support-ppe-flow-check-interrupt.patch \
    target/linux/mediatek/patches-6.6/999-2747-crypto-eth-inline.patch \
    target/linux/mediatek/patches-6.6/999-2747-crypto-eth-inline.patch \
    target/linux/mediatek/patches-6.6/999-2747-net-ethernet-mtk_eth_soc-add-proprietary-SER-flow.patch \
    target/linux/mediatek/patches-6.6/999-2747-net-ethernet-mtk_eth_soc-add-proprietary-SER-flow.patch \
    target/linux/mediatek/patches-6.6/999-3020-flow-offload-add-mtkhnat-macvlan-support.patch \
    target/linux/mediatek/patches-6.6/999-3020-flow-offload-add-mtkhnat-macvlan-support.patch \
    target/linux/mediatek/patches-6.6/9991-dsa-hnat.patch \
    target/linux/mediatek/patches-6.6/9991-dsa-hnat.patch \
    target/linux/mediatek/patches-6.6/9992-dsa-exthnat-fix.patch \
    target/linux/mediatek/patches-6.6/9992-dsa-exthnat-fix.patch \
    target/linux/mediatek/patches-6.6/9996-ext-hnat.patch \
    target/linux/mediatek/patches-6.6/9996-ext-hnat.patch \
    target/linux/mediatek/patches-6.6/9999-reset.patch \
    target/linux/mediatek/patches-6.6/9999-reset.patch

# The openwrt-24.10-6.6 branch carries the 3000-series PPE patches rebased onto
# the upstream 24.10 kernel layout, plus the rebased HNAT/ext-hnat fixes for
# linux-6.6.139 without the extra mtwifi-only ftnetlink patch train.
sparse_checkout_copy_many \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    openwrt-24.10-6.6 \
    vendor-mtk-2410-ppe \
    partial \
    target/linux/mediatek/patches-6.6/999-3000-netfilter-add-bridging-support-to-xt_FLOWOFFLOAD.patch \
    target/linux/mediatek/patches-6.6/999-3000-netfilter-add-bridging-support-to-xt_FLOWOFFLOAD.patch \
    target/linux/mediatek/patches-6.6/999-3001-net-ethernet-mtk_ppe-change-to-internal-ppe-debugfs.patch \
    target/linux/mediatek/patches-6.6/999-3001-net-ethernet-mtk_ppe-change-to-internal-ppe-debugfs.patch \
    target/linux/mediatek/patches-6.6/999-3002-net-ethernet-mtk_ppe-keep-sp-in-the-info1.patch \
    target/linux/mediatek/patches-6.6/999-3002-net-ethernet-mtk_ppe-keep-sp-in-the-info1.patch \
    target/linux/mediatek/patches-6.6/999-3003-net-ethernet-mtk_ppe-change-to-internal-QoS-mode.patch \
    target/linux/mediatek/patches-6.6/999-3003-net-ethernet-mtk_ppe-change-to-internal-QoS-mode.patch \
    target/linux/mediatek/patches-6.6/999-3004-netfilter-add-DSCP-learning-flow-to-xt_FLOWOFFLOAD.patch \
    target/linux/mediatek/patches-6.6/999-3004-netfilter-add-DSCP-learning-flow-to-xt_FLOWOFFLOAD.patch \
    target/linux/mediatek/patches-6.6/999-3005-netfilter-add-DEV_PATH_MTK_WDMA-path-to-xt_FLOWOFFLO.patch \
    target/linux/mediatek/patches-6.6/999-3005-netfilter-add-DEV_PATH_MTK_WDMA-path-to-xt_FLOWOFFLO.patch \
    target/linux/mediatek/patches-6.6/999-3007-net-ethernet-mtk_ppe-add-roaming-handler.patch \
    target/linux/mediatek/patches-6.6/999-3007-net-ethernet-mtk_ppe-add-roaming-handler.patch \
    target/linux/mediatek/patches-6.6/999-3008-net-ethernet-mtk_ppe-enable-CS0_PIPE-and-SRH_CACHE_F.patch \
    target/linux/mediatek/patches-6.6/999-3008-net-ethernet-mtk_ppe-enable-CS0_PIPE-and-SRH_CACHE_F.patch \
    target/linux/mediatek/patches-6.6/999-3009-net-ethernet-mtk_ppe-fix-typo-for-enabling-MIB-cache.patch \
    target/linux/mediatek/patches-6.6/999-3009-net-ethernet-mtk_ppe-fix-typo-for-enabling-MIB-cache.patch \
    target/linux/mediatek/patches-6.6/9997-hnat.patch \
    target/linux/mediatek/patches-6.6/9997-hnat.patch \
    target/linux/mediatek/patches-6.6/9999-fix-ext-hnat-with-fdb-error.patch \
    target/linux/mediatek/patches-6.6/99999-hnat-extdevice-fix-fdberr.patch

# linux-6.6.139 still keeps mtk_ppe_update_mtu() between deinit and start, so
# rebase the imported roaming patch hunk to the current header layout.
patch_literal_block \
    target/linux/mediatek/patches-6.6/999-3007-net-ethernet-mtk_ppe-add-roaming-handler.patch \
    $'@@ -350,6 +350,8 @@ struct mtk_ppe {\n struct mtk_ppe *mtk_ppe_init(struct mtk_eth *eth, void __iomem *base, int index);\n \n void mtk_ppe_deinit(struct mtk_eth *eth);\n+int mtk_ppe_roaming_start(struct mtk_eth *eth);\n+int mtk_ppe_roaming_stop(struct mtk_eth *eth);\n void mtk_ppe_start(struct mtk_ppe *ppe);\n int mtk_ppe_stop(struct mtk_ppe *ppe);\n int mtk_ppe_prepare_reset(struct mtk_ppe *ppe);' \
    $'@@ -350,7 +350,9 @@ struct mtk_ppe {\n struct mtk_ppe *mtk_ppe_init(struct mtk_eth *eth, void __iomem *base, int index);\n \n void mtk_ppe_deinit(struct mtk_eth *eth);\n+int mtk_ppe_roaming_start(struct mtk_eth *eth);\n+int mtk_ppe_roaming_stop(struct mtk_eth *eth);\n void mtk_ppe_update_mtu(struct mtk_ppe *ppe, int mtu);\n void mtk_ppe_start(struct mtk_ppe *ppe);\n int mtk_ppe_stop(struct mtk_ppe *ppe);\n int mtk_ppe_prepare_reset(struct mtk_ppe *ppe);'

if ! grep -q 'KernelPackage/mediatek_hnat' target/linux/mediatek/modules.mk; then
cat >> target/linux/mediatek/modules.mk <<'EOF'

define KernelPackage/mediatek_hnat
    SUBMENU:=Network Devices
    TITLE:=MediaTek hardware NAT support
    DEPENDS:=@TARGET_mediatek +kmod-nf-conntrack +kmod-ipt-nat
    KCONFIG:=CONFIG_NET_MEDIATEK_HNAT
    FILES:=$(LINUX_DIR)/drivers/net/ethernet/mediatek/mtk_hnat/mtkhnat.ko
    AUTOLOAD:=$(call AutoProbe,mtkhnat)
endef

define KernelPackage/mediatek_hnat/description
    MediaTek hardware NAT support for the NETSYS/PPE offload path.
endef

$(eval $(call KernelPackage,mediatek_hnat))
EOF
fi

# The current 24.10-based tree lacks the xcrypt package block that defines libcrypt-compat.
sparse_checkout_copy \
    https://github.com/immortalwrt/immortalwrt \
    openwrt-25.12 \
    package/libs/xcrypt \
    package/libs/xcrypt \
    immortalwrt-core \
    full

# Restore ImmortalWrt's status overview helpers and override tempinfo for mt_wifi7.
sparse_checkout_copy \
    https://github.com/immortalwrt/immortalwrt \
    openwrt-24.10 \
    package/emortal/autocore \
    package/emortal/autocore \
    immortalwrt-autocore \
    full

cp -f "$GITHUB_WORKSPACE/scripts/tempinfo" package/emortal/autocore/files/tempinfo
chmod 0755 package/emortal/autocore/files/tempinfo

# add luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# add luci-app-OpenClash
mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash
git config core.sparsecheckout true
popd

# wireless-regdb / wifi-scripts MLO compatibility overrides
apply_wireless_regdb_overlay
apply_wifi_mlo_uci_backport

# BPi-R4 SFP can fall back to a broken link on both 24.10 and 25.12
# when the USXGMII PCS polarity is left at the default board-agnostic setting.
if [ -d target/linux/mediatek/patches-6.12 ]; then
    cp -f $GITHUB_WORKSPACE/patches/filogic/995-bpi-r4-sfp-usxgmii-polarity.patch \
        target/linux/mediatek/patches-6.12/995-arm64-dts-mediatek-mt7988a-bpi-r4-fix-usxgmii-polarity.patch
elif [ -d target/linux/mediatek/patches-6.6 ]; then
    cp -f $GITHUB_WORKSPACE/patches/filogic/995-bpi-r4-sfp-usxgmii-polarity-24.10.patch \
        target/linux/mediatek/patches-6.6/995-arm64-dts-mediatek-mt7988a-bpi-r4-fix-usxgmii-polarity.patch
fi

# Some BPi-R4 SFP links come up without carrier until they are retrained once.
mkdir -p target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface
cp -f $GITHUB_WORKSPACE/patches/filogic/99-bpi-r4-sfp-retrain \
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/99-bpi-r4-sfp-retrain
chmod 0755 target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/99-bpi-r4-sfp-retrain

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
