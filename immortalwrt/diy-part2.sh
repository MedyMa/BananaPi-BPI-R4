#!/bin/bash
#
# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Keep the upstream package tree intact; only reuse BPI hnat assets
# and the mt76 version bump patch from the workspace.
git clone --depth=1 --filter=blob:none --sparse \
  https://github.com/BPI-SINOVOIP/BPI-R4PRO-8X-OPENWRT-V24.10.0-Master-Devel \
  bpi-r4pro-src
pushd bpi-r4pro-src
git sparse-checkout set --no-cone \
  /target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek \
  /target/linux/mediatek/files-6.6/include \
  /target/linux/mediatek/patches-6.6
popd

for required_path in \
  bpi-r4pro-src/target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat \
  bpi-r4pro-src/target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_dbg.c \
  bpi-r4pro-src/target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_dbg.h \
  bpi-r4pro-src/target/linux/mediatek/patches-6.6
do
  [ -e "$required_path" ] || {
    echo "Missing required BPI path after sparse checkout: $required_path" >&2
    exit 1
  }
done

# Keep the mt76 package Makefile bump as a standalone patch, so the version
# update is tracked in the workspace and validated with patch(1).
perl -0pi -e 's/\r\n/\n/g; s/\r/\n/g' \
  "$GITHUB_WORKSPACE/patches/filogic/mt76/1005-mt76-makefile-2ab64980.patch"
(cd package/kernel/mt76 && patch -p1 < "$GITHUB_WORKSPACE/patches/filogic/mt76/1005-mt76-makefile-2ab64980.patch")

# The copied HNAT driver sources only add kernel code; OpenWrt still needs a
# KernelPackage definition so kmod-mediatek_hnat exists for defconfig and LuCI.
if ! grep -qF 'define KernelPackage/mediatek_hnat' target/linux/mediatek/modules.mk; then
cat >> target/linux/mediatek/modules.mk << 'EOF'

define KernelPackage/mediatek_hnat
  SUBMENU:=Network Devices
  TITLE:=MediaTek HNAT support
  DEPENDS:=@TARGET_mediatek_filogic +kmod-nf-flow
  KCONFIG:=CONFIG_NET_MEDIATEK_HNAT
  FILES:=$(LINUX_DIR)/drivers/net/ethernet/mediatek/mtk_hnat/mtkhnat.ko
  AUTOLOAD:=$(call AutoProbe,mtkhnat)
endef

define KernelPackage/mediatek_hnat/description
  MediaTek hardware NAT offload module for Filogic targets.
endef

$(eval $(call KernelPackage,mediatek_hnat))
EOF
fi

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

# Extend the copied BPI 999-2741 patch so nf_flow_table.h is touched once.
# A separate follow-up patch is brittle here because cached kernel trees or
# nearby upstream context drift can make the second hunk fail before compile.
if [ -f target/linux/mediatek/patches-6.6/999-2741-mtkhnat-add-support-for-virtual-interface-a.patch ]; then
  patch_file=target/linux/mediatek/patches-6.6/999-2741-mtkhnat-add-support-for-virtual-interface-a.patch
  PATCH_FILE="$patch_file" perl -0pi -e 'BEGIN { $file = $ENV{"PATCH_FILE"}; }
      $count_header = s/@@ -182,6 \+182,7 @@ struct flow_offload \{/@@ -182,6 +182,8 @@ struct flow_offload {/g;
      $count = s/\+\s+struct net_device \*virt_dev;\n(\s+u32 flags;)/+\tstruct net_device *virt_dev;\n+\tu32 tnl_type;\n$1/g;
      END {
        if ($count_header == 1 && $count == 1) {
          exit 0;
        }
        print STDERR "Failed to inject tnl_type into $file\n";
        exit 2;
      }' "$patch_file"
fi

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

rm -rf bpi-r4pro-src

# Patch stack changes can survive through restored kernel build dirs and cause
# stale plaintext-patch failures. Force target/linux to repatch from scratch.
find build_dir -type d \( -name 'linux-*' -o -name 'linux-mediatek_filogic' \) -prune -exec rm -rf {} + 2>/dev/null || true
find staging_dir -path '*/stamp/.target_compile*' -type f -delete 2>/dev/null || true

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
