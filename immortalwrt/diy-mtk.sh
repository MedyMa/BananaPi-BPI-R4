#!/bin/bash
set -euo pipefail

log()  { echo "[MTK-FIX] $*"; }
warn() { echo "[MTK-FIX WARN] $*"; }

OPENWRT_ROOT="${OPENWRT_ROOT:-$(pwd)}"
MTK_SDK_DIR="${MTK_SDK_DIR:-${OPENWRT_ROOT}/../mtk-openwrt-feeds}"

log "OPENWRT_ROOT=${OPENWRT_ROOT}"
log "MTK_SDK_DIR=${MTK_SDK_DIR}"

log "Pinning kernel Kconfig symbols..."
cfg="${OPENWRT_ROOT}/target/linux/mediatek/filogic/config-6.12"
if [ -f "$cfg" ]; then
    for symbol in MEDIATEK_2P5GE_PHY NET_MEDIATEK_HNAT MEDIATEK_NETSYS_V3 NETFILTER; do
        case "$symbol" in
            MEDIATEK_2P5GE_PHY) val="# CONFIG_${symbol} is not set" ;;
            NET_MEDIATEK_HNAT) val="CONFIG_${symbol}=m" ;;
            *) val="CONFIG_${symbol}=y" ;;
        esac
        sed -i "/^CONFIG_${symbol}=/d; /^# CONFIG_${symbol} is not set$/d" "$cfg"
        echo "$val" >> "$cfg"
        log "  ${symbol}: pinned"
    done
else
    warn "config-6.12 not found: ${cfg}"
fi

log "Enabling CMake policy compatibility..."
export CMAKE_POLICY_VERSION_MINIMUM=3.5
echo "CMAKE_POLICY_VERSION_MINIMUM=3.5" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
log "  CMAKE_POLICY_VERSION_MINIMUM=3.5"

log "Overlaying HNAT kernel files..."
files_src="${MTK_SDK_DIR}/autobuild/unified/global/logan_common/25.12/files/target/linux/mediatek/files-6.12"
files_dst="${OPENWRT_ROOT}/target/linux/mediatek/files-6.12"
log "  source: ${files_src}"
if [ -d "$files_src" ]; then
    mkdir -p "$files_dst"
    tmp_dst=$(mktemp -d)
    log "  staging: ${tmp_dst}"
    trap "rm -rf '$tmp_dst'" EXIT
    if cp -af "$files_src"/. "$tmp_dst/" 2>/dev/null; then
        before=$(find "$tmp_dst" -type f 2>/dev/null | wc -l)
        log "  copied ${before} files to staging"
        find "$tmp_dst" -type f \( -name 'Makefile' -o -name 'Kbuild' -o -name 'Kconfig' \) -print0 2>/dev/null | \
            while IFS= read -r -d '' mf; do
                case "$mf" in
                    */drivers/net/ethernet/mediatek/mtk_hnat/Makefile)
                        log "    keep: $(echo "$mf" | sed "s|${tmp_dst}/||")"
                        ;;
                    *)
                        log "    drop: $(echo "$mf" | sed "s|${tmp_dst}/||")"
                        rm -f "$mf"
                        ;;
                esac
            done
        for dir in "$tmp_dst"/*/; do
            [ -d "$dir" ] || continue
            case "$(basename "${dir%/}")" in
                drivers|include|arch) ;;
                *) rm -rf "$dir" ;;
            esac
        done
        after=$(find "$tmp_dst" -type f 2>/dev/null | wc -l)
        log "  after cleanup: ${after} files"
        cp -af "$tmp_dst"/. "$files_dst/"
        log "  overlaid to: ${files_dst}"

        # 999-eth-91-a/b replace the original (PPE-failing) 999-eth-91:
        #   a) Kconfig: complete file overlay into files-6.12 (no patch — avoids
        #      plaintext patch parser issues with tab-indented context lines)
        #   b) Makefile: single-file quilt patch (works in plaintext mode)
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        mtk="${script_dir}/../patches/filogic/mtk"
        owrt="${OPENWRT_ROOT}/target/linux/mediatek/patches-6.12"

        # Kconfig: copy complete modified file into files-6.12 overlay
        kconfig_src="${mtk}/Kconfig"
        kconfig_dst="${files_dst}/drivers/net/ethernet/mediatek/Kconfig"
        if [ -f "$kconfig_src" ]; then
            mkdir -p "$(dirname "$kconfig_dst")"
            cp -f "$kconfig_src" "$kconfig_dst"
            log "  Kconfig: complete file overlaid"
        else
            warn "Kconfig source not found: ${kconfig_src}"
        fi

        # Makefile: staged as quilt patch
        if [ -d "$owrt" ]; then
            find "$owrt" -name '999-eth-91*driver-support*' -delete 2>/dev/null || true
            find "$owrt" -name '999-eth-91*mtkhnat*' -delete 2>/dev/null || true
        fi
        mkdir -p "$owrt"
        mf_patch="${mtk}/999-eth-91-b-hnat-makefile.patch"
        if [ -f "$mf_patch" ]; then
            cp -f "$mf_patch" "$owrt/"
            log "  Makefile: staged quilt patch"
        else
            warn "Makefile patch not found: ${mf_patch}"
        fi

    else
        warn "Copy from logan_common failed"
        rm -rf "$tmp_dst"
        trap - EXIT
        exit 1
    fi
    rm -rf "$tmp_dst"
    trap - EXIT
else
    warn "logan_common files-6.12 not found: ${files_src}"
    exit 1
fi

log "Injecting KERNEL_EXTRA_SYMBOLS for HNAT→NPU symvers..."
# 0014 patch defines KernelPackage/mediatek_hnat but without symvers export.
# NPU modules depend on HNAT symbols; without KERNEL_EXTRA_SYMBOLS:=1,
# Module.symvers is not propagated → modpost undefined symbols.
netdev_mk="${OPENWRT_ROOT}/package/kernel/linux/modules/netdevices.mk"
if [ -f "$netdev_mk" ] && grep -q 'KernelPackage/mediatek_hnat' "$netdev_mk"; then
    if ! grep -q 'KERNEL_EXTRA_SYMBOLS.*:=.*1' "$netdev_mk"; then
        sed -i '/^define KernelPackage\/mediatek_hnat$/,/^endef$/{/DEPENDS:=/a\  KERNEL_EXTRA_SYMBOLS:=1
}' "$netdev_mk"
        log "  injected KERNEL_EXTRA_SYMBOLS:=1"
    else
        log "  already present"
    fi
else
    warn "netdevices.mk not found or mediatek_hnat not defined"
fi

log "Patching NPU Makefile for CONFIG_MEDIATEK_NETSYS_V3..."
# NPU package Makefile passes EXTRA_CFLAGS on cmdline → overrides Kbuild ccflags-y.
# Must inject -DCONFIG_MEDIATEK_NETSYS_V3 into EXTRA_CFLAGS here, not in Kbuild.
npu_makefile="${MTK_SDK_DIR}/feed/kernel/mtk_npu/Makefile"
if [ -f "$npu_makefile" ]; then
    if grep -q 'CONFIG_MEDIATEK_NETSYS_V3' "$npu_makefile"; then
        log "  already patched"
    else
        sed -i '/EXTRA_KCONFIG))))$/a\EXTRA_CFLAGS+= -DCONFIG_MEDIATEK_NETSYS_V3' "$npu_makefile"
        log "  added NETSYS_V3 to EXTRA_CFLAGS"
    fi
else
    warn "NPU Makefile not found: ${npu_makefile}"
fi

log "Patching NPU Kbuild for include path..."
npu_kbuild="${MTK_SDK_DIR}/feed/kernel/mtk_npu/src/Makefile"
if [ -f "$npu_kbuild" ]; then
    if grep -q 'srctree.*mediatek' "$npu_kbuild"; then
        log "  already patched"
    else
        sed -i '/^ccflags-y += -I\$(src)\/protocol\/inc$/a\ccflags-y += -I$(srctree)/drivers/net/ethernet/mediatek' "$npu_kbuild"
        log "  added include path"
    fi
else
    warn "NPU Kbuild not found: ${npu_kbuild}"
fi

log "Extracting mtk_eth_reset.h..."
hdr="${files_dst}/drivers/net/ethernet/mediatek/mtk_eth_reset.h"
log "  target: ${hdr}"

patch_sdk="${MTK_SDK_DIR}/autobuild/unified/global/logan_common/25.12/files/target/linux/mediatek/patches-6.12"
patch="${patch_sdk}/999-eth-93-mtk_eth_soc-add-internal-SER-notify-event.patch"
shopt -s nullglob
patch_owrt_candidates=("${OPENWRT_ROOT}"/target/linux/mediatek/patches-6.12/999-eth-93*)
shopt -u nullglob

found=""
if [ -f "$patch" ]; then
    found="$patch"
    log "  strategy1: found in SDK (${patch})"
elif [ "${#patch_owrt_candidates[@]}" -gt 0 ]; then
    found="${patch_owrt_candidates[0]}"
    log "  strategy2: found in OpenWrt tree (${found})"
else
    log "  strategy1: not found (${patch})"
    log "  strategy2: no candidates in OpenWrt tree"
fi

if [ -n "$found" ]; then
    mkdir -p "$(dirname "$hdr")"
    sed -n '/^diff.*mtk_eth_reset\.h$/{n; :a; /^diff --git /b; /^+++/!s/^+//; p; n; ba}' "$found" | \
        sed '1,/^@@/d' > "$hdr"
    if [ -s "$hdr" ] && grep -q 'MTK_FE_START_RESET' "$hdr"; then
        log "  Extracted ($(wc -l < "$hdr") lines)"
    else
        warn "Extraction produced empty or invalid file, header may be missing"
    fi
else
    warn "999-eth-93 patch not found in SDK or OpenWrt tree - NPU build may fail"
fi

log "All fixups complete."
