#!/bin/bash

function merge_package(){
    repo="${1##*/}"
    pkg="${2##*/}"
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

apply_patch_series() {
    local patch_root="$1"
    shift

    while [ "$#" -gt 0 ]; do
        apply_workspace_patch "$patch_root/$1"
        shift
    done
}

sync_tree() {
    local source_dir="$1"
    local dest_dir="$2"

    [ -d "$source_dir" ] || return 0
    mkdir -p "$dest_dir"
    cp -a "$source_dir"/. "$dest_dir"/
}

inject_mediatek_hnat_package() {
    local target_file="package/kernel/linux/modules/netdevices.mk"

    [ -f "$target_file" ] || return 0
    grep -q 'KernelPackage/mediatek_hnat' "$target_file" && return 0

    cat >> "$target_file" <<'EOF'

define KernelPackage/mediatek_hnat
  SUBMENU:=$(NETWORK_DEVICES_MENU)
  TITLE:=Mediatek HNAT module
  DEPENDS:=@TARGET_mediatek +kmod-nf-conntrack
  KCONFIG:= \
	CONFIG_BRIDGE_NETFILTER=y \
	CONFIG_NETFILTER_FAMILY_BRIDGE=y \
	CONFIG_NET_MEDIATEK_HNAT
  FILES:= \
	$(LINUX_DIR)/drivers/net/ethernet/mediatek/mtk_hnat/mtkhnat.ko
endef

define KernelPackage/mediatek_hnat/description
  Kernel modules for MediaTek HW NAT offloading
endef

$(eval $(call KernelPackage,mediatek_hnat))
EOF
}

apply_wifi_mlo_uci_backport() {
    local legacy_anchor="package/network/config/wifi-scripts/files-ucode/usr/share/ucode/wifi/supplicant.uc"
    local shell_anchor="package/network/config/wifi-scripts/files/lib/netifd/hostapd.sh"

    if [ -f "$legacy_anchor" ]; then
        apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/996-wifi-scripts-add-mlo-uci-passthrough.patch"
        return 0
    fi

    if [ -f "$shell_anchor" ]; then
        apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/996-wifi-scripts-add-mlo-uci-passthrough-24.10.patch"
        return 0
    fi

    echo "Missing wifi-scripts anchor after feeds install: $legacy_anchor or $shell_anchor" >&2
    return 1
}

ensure_shared_mod_def0_patch() {
    local patch_dir="$1"
    local workspace_patch="$GITHUB_WORKSPACE/patches/filogic/997-bpi-r4-sfp-shared-mod-def0-24.10.patch"

    [ -d "$patch_dir" ] || return 0
    [ -f "$workspace_patch" ] || return 0

    if grep -RqsE 'GPIOD_FLAGS_BIT_NONEXCLUSIVE|shared mod-def0 gpio' "$patch_dir"; then
        return 0
    fi

    cp -f "$workspace_patch" \
        "$patch_dir/996-net-phy-sfp-support-shared-mod-def0-gpio.patch"
}

refresh_public_hnat_patches() {
    local patch_dir="$1"
    local checkout_dir
    local ext_fix_src="target/linux/mediatek/patches-6.6/9999-fix-ext-hnat-with-fdb-error.patch"

    [ -d "$patch_dir" ] || return 0
    [ -f "$patch_dir/9997-hnat.patch" ] || return 0

    checkout_dir="$(sparse_checkout_init \
        https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
        openwrt-24.10-6.6 \
        vendor-mtk-2410-public-hnat \
        partial)"
    git -C "$checkout_dir" sparse-checkout set --skip-checks \
        target/linux/mediatek/patches-6.6/9997-hnat.patch \
        "$ext_fix_src"

    sparse_checkout_copy_from_dir \
        "$checkout_dir" \
        target/linux/mediatek/patches-6.6/9997-hnat.patch \
        "$patch_dir/9997-hnat.patch"

    if [ -f "$patch_dir/9999-fix-ext-hnat-with-fdb-error.patch" ]; then
        sparse_checkout_copy_from_dir \
            "$checkout_dir" \
            "$ext_fix_src" \
            "$patch_dir/9999-fix-ext-hnat-with-fdb-error.patch"
    elif [ -f "$patch_dir/99999-hnat-extdevice-fix-fdberr.patch" ]; then
        sparse_checkout_copy_from_dir \
            "$checkout_dir" \
            "$ext_fix_src" \
            "$patch_dir/99999-hnat-extdevice-fix-fdberr.patch"
    fi

    rm -rf "$checkout_dir"
}

mtk_public_root="${MTK_PUBLIC_FEEDS_PATH:-$GITHUB_WORKSPACE/mtk-openwrt-feeds-public}"

[ -d "$mtk_public_root/autobuild/unified/filogic/24.10" ] || {
    echo "Missing MediaTek public feeds checkout at $mtk_public_root" >&2
    exit 1
}

rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-modemband
rm -rf feeds/luci/applications/luci-app-adguardhome
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}

mkdir -p package/community
pushd package/community
git clone --depth=1 https://github.com/fw876/helloworld
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

# Import the MTK-specific LuCI QoS / HNAT apps from the vendor package tree.
sparse_checkout_copy_many \
    https://github.com/padavanonly/immortalwrt-mt798x-6.6 \
    mt798x-mt799x-6.6-mtwifi \
    vendor-mtk-luci-public \
    partial \
    package/mtk/applications/luci-app-eqos-mtk \
    package/openwrt-packages/luci-app-eqos-mtk \
    package/mtk/applications/luci-app-turboacc-mtk \
    package/openwrt-packages/luci-app-turboacc-mtk

# ImmortalWrt 24.10 ships tc as tc-tiny/tc-full rather than a plain tc package.
patch_makefile_dep \
    package/openwrt-packages/luci-app-eqos-mtk/Makefile \
    '+wget-ssl +tc +kmod-sched-core +kmod-ifb +ebtables-legacy-utils +ebtables-legacy  @!PACKAGE_luci-app-eqos' \
    '+wget-ssl +tc-full +kmod-sched-core +kmod-ifb +ebtables-legacy-utils +ebtables-legacy  @!PACKAGE_luci-app-eqos'

# The MTK public route is applied after feeds install so that wifi-scripts,
# hostapd and mt76 already exist in the tree and can be patched in place.
apply_patch_series \
    "$mtk_public_root/autobuild/unified/filogic/24.10/patches-base" \
    0010-remove-mtk-2p5ge-driver-from-built-in-list.patch \
    0013-disable-packet-steering-reload-service.patch
sync_tree \
    "$mtk_public_root/autobuild/unified/filogic/24.10/files/target/linux/mediatek" \
    target/linux/mediatek
# linux-6.6.139 already carries the PMA-based 2.5G/5G + EEE phylib support,
# so the older MTK public backport now rejects and must be dropped.
rm -f target/linux/mediatek/patches-6.6/999-1700-v6.8-net-phy-2p5g-eee-backport-read-support-link-mode-from-PMA.patch
# The MTK public 24.10 tree can still carry an older 9997 HNAT patch that no
# longer applies cleanly to linux-6.6.139. Refresh it from the rebased
# openwrt-24.10-6.6 branch before the kernel patch phase.
refresh_public_hnat_patches target/linux/mediatek/patches-6.6
inject_mediatek_hnat_package

apply_patch_series \
    "$mtk_public_root/autobuild/unified/filogic/mac80211/24.10/patches-base" \
    0001-mt76-package-makefile.patch \
    0002-iw-package-makefile.patch \
    0003-hostapd-package-makefile-ucode-files.patch \
    0004-mac80211-package-makefile.patch
sync_tree \
    "$mtk_public_root/autobuild/unified/filogic/mac80211/24.10/files/package" \
    package

# The current 24.10-based tree lacks the xcrypt package block that defines libcrypt-compat.
sparse_checkout_copy \
    https://github.com/immortalwrt/immortalwrt \
    openwrt-25.12 \
    package/libs/xcrypt \
    package/libs/xcrypt \
    immortalwrt-core \
    full

# Keep ImmortalWrt's autocore package available for the status view.
sparse_checkout_copy \
    https://github.com/immortalwrt/immortalwrt \
    openwrt-24.10 \
    package/emortal/autocore \
    package/emortal/autocore \
    immortalwrt-autocore \
    full

rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash
git config core.sparsecheckout true
popd

apply_wifi_mlo_uci_backport || exit 1

# USXGMII PCS polarity is left at the default board-agnostic setting.
cp -f "$GITHUB_WORKSPACE/patches/filogic/995-bpi-r4-sfp-usxgmii-polarity-24.10.patch" \
    target/linux/mediatek/patches-6.6/995-arm64-dts-mediatek-mt7988a-bpi-r4-fix-usxgmii-polarity.patch

mkdir -p target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface
cp -f "$GITHUB_WORKSPACE/patches/filogic/99-bpi-r4-sfp-retrain" \
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/99-bpi-r4-sfp-retrain
chmod 0755 target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/99-bpi-r4-sfp-retrain

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
