#!/bin/bash
# diy-mtk.sh — Post-autobuild fixups for BPI-R4 vendor WiFi + HNAT + NPU
# Run AFTER: autobuild.sh prepare
# Run BEFORE: autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic build
set -euo pipefail

log()  { echo "[MTK-FIX] $*"; }
warn() { echo "[MTK-FIX WARN] $*"; }
die()  { echo "[MTK-FIX ERROR] $*"; exit 1; }

# ─── Bootstrap ───
OPENWRT_ROOT="${OPENWRT_ROOT:-$(pwd)}"
MTK_SDK_DIR="${MTK_SDK_DIR:-${OPENWRT_ROOT}/../mtk-openwrt-feeds}"
CHASEY_REPO="https://github.com/chasey-dev/immortalwrt-mt798x-rebase.git"
CHASEY_BRANCH="25.12"

log "OPENWRT_ROOT=${OPENWRT_ROOT}"
log "MTK_SDK_DIR=${MTK_SDK_DIR}"

# ═══════════════════════════════════════════
# Step 1: Pin kernel Kconfig symbols
# ═══════════════════════════════════════════
log "=== Step 1: Kconfig ==="
CFG="${OPENWRT_ROOT}/target/linux/mediatek/filogic/config-6.12"
[ -f "$CFG" ] || die "config-6.12 not found: ${CFG}"

declare -A PINS=(
    [MEDIATEK_2P5GE_PHY]="# CONFIG_MEDIATEK_2P5GE_PHY is not set"
    [NET_MEDIATEK_HNAT]="CONFIG_NET_MEDIATEK_HNAT=m"
    [MEDIATEK_NETSYS_V3]="CONFIG_MEDIATEK_NETSYS_V3=y"
    [NETFILTER]="CONFIG_NETFILTER=y"
)
for sym in "${!PINS[@]}"; do
    sed -i "/^CONFIG_${sym}=/d; /^# CONFIG_${sym} is not set\$/d" "$CFG"
    echo "${PINS[$sym]}" >> "$CFG"
    log "  ${sym}: pinned"
done

# ═══════════════════════════════════════════
# Step 2: CMake policy
# ═══════════════════════════════════════════
log "=== Step 2: CMake ==="
export CMAKE_POLICY_VERSION_MINIMUM=3.5
echo "CMAKE_POLICY_VERSION_MINIMUM=3.5" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
log "  OK"

# ═══════════════════════════════════════════
# Step 3: HNAT files + patches + header
# ═══════════════════════════════════════════
log "=== Step 3: HNAT integration ==="

SDK_FILES="${MTK_SDK_DIR}/autobuild/unified/global/logan_common/25.12/files/target/linux/mediatek/files-6.12"
DST_FILES="${OPENWRT_ROOT}/target/linux/mediatek/files-6.12"
PATCH_DIR="${OPENWRT_ROOT}/target/linux/mediatek/patches-6.12"

[ -d "$SDK_FILES" ] || die "SDK files-6.12 missing: ${SDK_FILES}"
mkdir -p "$DST_FILES" "$PATCH_DIR"

# -- 3a: Overlay HNAT source from SDK --
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT
cp -af "$SDK_FILES"/. "$TMP/" || die "copy SDK files failed"
BEFORE=$(find "$TMP" -type f | wc -l)

# Keep HNAT Makefile, drop all other Makefile/Kbuild/Kconfig
find "$TMP" -type f \( -name Makefile -o -name Kbuild -o -name Kconfig \) -print0 | \
while IFS= read -r -d '' f; do
    case "$f" in */drivers/net/ethernet/mediatek/mtk_hnat/Makefile) ;; *) rm -f "$f" ;; esac
done
# Keep only drivers/ include/ arch/
for d in "$TMP"/*/; do
    [ -d "$d" ] || continue
    case "$(basename "${d%/}")" in drivers|include|arch) ;; *) rm -rf "$d" ;; esac
done
AFTER=$(find "$TMP" -type f | wc -l)
cp -af "$TMP"/. "$DST_FILES/"
rm -rf "$TMP"
trap - EXIT
log "  files: ${BEFORE} -> ${AFTER} overlaid"

# -- 3b: Fetch chasey-dev rebased patches --
# Shallow-clone chasey-dev, copy HNAT patches, discard clone
CHASEY_TMP=$(mktemp -d)
trap "rm -rf '$CHASEY_TMP'" EXIT
git clone --depth 1 --branch "$CHASEY_BRANCH" "$CHASEY_REPO" "$CHASEY_TMP" 2>&1 | tail -1
CHASEY_PATCHES="${CHASEY_TMP}/target/linux/mediatek/patches-6.12"
if [ -d "$CHASEY_PATCHES" ]; then
    # Purge SDK patches that conflict with chasey-dev rebased versions
    for prefix in 999-eth-91 999-hnat- 999-net-03 999-net-04 999-tnl- 999-zzz-51 999-zzz-53; do
        find "$PATCH_DIR" -maxdepth 1 -name "${prefix}*" -delete 2>/dev/null || true
    done
    # Strip diff --git from remaining non-HNAT SDK patches
    find "$PATCH_DIR" -maxdepth 1 -name '*.patch' -exec sed -i '/^diff --git /d' {} + 2>/dev/null || true
    log "  old SDK patches cleaned"

    # Copy chasey-dev patches (git format-patch, keep diff --git intact)
    COUNT=0
    for prefix in 999-eth-91 999-eth-93 999-hnat- 999-net-03 999-net-04 999-tnl- 999-zzz-51 999-zzz-53; do
        for p in "$CHASEY_PATCHES"/${prefix}*.patch; do
            [ -f "$p" ] || continue
            cp -f "$p" "$PATCH_DIR/"
            COUNT=$((COUNT + 1))
        done
    done
    log "  staged ${COUNT} chasey-dev patches (from ${CHASEY_BRANCH})"
else
    die "chasey-dev patches not found after clone"
fi
rm -rf "$CHASEY_TMP"
trap - EXIT

# -- 3c: mtk_eth_reset.h (NPU needs it, not in files-6.12) --
HDR="${DST_FILES}/drivers/net/ethernet/mediatek/mtk_eth_reset.h"
SDK_P93="${MTK_SDK_DIR}/autobuild/unified/global/logan_common/25.12/files/target/linux/mediatek/patches-6.12/999-eth-93-mtk_eth_soc-add-internal-SER-notify-event.patch"
CD_P93=$(find "$PATCH_DIR" -maxdepth 1 -name '999-eth-93*' -print -quit 2>/dev/null || true)

extract_hdr() {
    awk '/^diff.*mtk_eth_reset\.h$/{s=1;next} /^diff --git /{s=0} s&&/^@@/{h=1;next} s&&h&&/^\+/{print substr($0,2)}' "$1" > "$2"
    [ -s "$2" ] && grep -q 'MTK_FE_START_RESET' "$2"
}

mkdir -p "$(dirname "$HDR")"
if [ -f "$SDK_P93" ] && extract_hdr "$SDK_P93" "$HDR"; then
    log "  mtk_eth_reset.h: SDK ($(wc -l < "$HDR") lines)"
elif [ -n "$CD_P93" ] && [ -f "$CD_P93" ] && extract_hdr "$CD_P93" "$HDR"; then
    log "  mtk_eth_reset.h: chasey-dev ($(wc -l < "$HDR") lines)"
else
    warn "mtk_eth_reset.h extraction failed"
fi

# ═══════════════════════════════════════════
# Step 4: KERNEL_EXTRA_SYMBOLS for HNAT→NPU
# ═══════════════════════════════════════════
log "=== Step 4: KERNEL_EXTRA_SYMBOLS ==="
NETDEV="${OPENWRT_ROOT}/package/kernel/linux/modules/netdevices.mk"

if [ -f "$NETDEV" ] && grep -q 'KernelPackage/mediatek_hnat' "$NETDEV"; then
    if ! grep -q 'KERNEL_EXTRA_SYMBOLS.*:=.*1' "$NETDEV"; then
        sed -i '/^define KernelPackage\/mediatek_hnat$/,/^endef$/{/DEPENDS:=/a\  KERNEL_EXTRA_SYMBOLS:=1
}' "$NETDEV"
        log "  KERNEL_EXTRA_SYMBOLS injected"
    else
        log "  already present"
    fi
    if ! grep -q 'CONFIG_NETFILTER=y' "$NETDEV"; then
        sed -i '/^define KernelPackage\/mediatek_hnat$/,/^endef$/{/KCONFIG:=/a\	CONFIG_NETFILTER=y
}' "$NETDEV"
        sed -i '/^define KernelPackage\/mediatek_hnat$/,/^endef$/{/KCONFIG:=/a\	CONFIG_NF_CONNTRACK=m
}' "$NETDEV"
        sed -i '/^define KernelPackage\/mediatek_hnat$/,/^endef$/{/KCONFIG:=/a\	CONFIG_IP_NF_NAT=m
}' "$NETDEV"
        log "  NETFILTER deps injected"
    fi
else
    warn "netdevices.mk: no mediatek_hnat"
fi

# ═══════════════════════════════════════════
# Step 5: NPU compile flags + include path
# ═══════════════════════════════════════════
log "=== Step 5: NPU patches ==="

# 5a: NETSYS_V3 into EXTRA_CFLAGS
NPU_MK="${MTK_SDK_DIR}/feed/kernel/mtk_npu/Makefile"
if [ -f "$NPU_MK" ]; then
    if grep -q 'CONFIG_MEDIATEK_NETSYS_V3' "$NPU_MK"; then
        log "  NETSYS_V3: already patched"
    else
        sed -i '/EXTRA_KCONFIG))))$/a\EXTRA_CFLAGS+= -DCONFIG_MEDIATEK_NETSYS_V3' "$NPU_MK"
        log "  NETSYS_V3: added"
    fi
else
    warn "NPU Makefile missing: ${NPU_MK}"
fi

# 5b: HNAT include path for NPU Kbuild
NPU_KB="${MTK_SDK_DIR}/feed/kernel/mtk_npu/src/Makefile"
if [ -f "$NPU_KB" ]; then
    if grep -q 'srctree.*mediatek' "$NPU_KB"; then
        log "  include: already patched"
    else
        sed -i '/^ccflags-y += -I\$(src)\/protocol\/inc$/a\ccflags-y += -I$(srctree)/drivers/net/ethernet/mediatek' "$NPU_KB"
        log "  include: added"
    fi
else
    warn "NPU Kbuild missing: ${NPU_KB}"
fi

# ═══════════════════════════════════════════
log "=== All fixups complete ==="
