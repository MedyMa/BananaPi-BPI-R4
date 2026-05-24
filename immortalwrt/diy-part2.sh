#!/bin/bash
#
# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Workaround: GCC 14 + musl fortify "always_inline memset: target specific option mismatch" in mbedtls
# Root cause: When building for aarch64_cortex-a53 with GCC 14, TARGET_CFLAGS includes
# target-specific CPU flags (e.g. -mcpu=cortex-a53+crypto) that conflict with the
# always_inline memset declared in musl's fortify/string.h. GCC 14 enforces strict
# target-option consistency for always_inline functions and raises an error.
# Fix: Disable _FORTIFY_SOURCE only for mbedtls so the fortify inline is not attempted,
# resolving the mismatch without affecting any other package's compilation.
if ! grep -q '_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile; then
  if grep -q 'TARGET_CFLAGS := \$(filter-out -O%' package/libs/mbedtls/Makefile; then
    sed -i '/TARGET_CFLAGS := \$(filter-out -O%/a TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile
  else
    echo 'TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' >> package/libs/mbedtls/Makefile
  fi
fi

# ── MTK WiFi7 driver (mtk-openwrt-feeds MP4.2, 2025-09-12) ──────────────────
# Replaces stock mt76 / mac80211 / wifi-scripts with MTK's WiFi7 release.
# Only these WiFi packages are touched; all other feeds/packages unchanged.
git clone --depth=1 \
    https://git01.mediatek.com/plugins/gitiles/openwrt/feeds/mtk-openwrt-feeds \
    /tmp/mtk-openwrt-feeds

MTK_BASE="/tmp/mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/24.10"

# Update mt76 / mac80211 / hostapd Makefile versions to MTK WiFi7 release
for p in \
    "$MTK_BASE/patches-base/0001-mt76-package-makefile.patch" \
    "$MTK_BASE/patches-base/0003-hostapd-package-makefile-ucode-files.patch" \
    "$MTK_BASE/patches-base/0004-mac80211-package-makefile.patch"; do
    [ -f "$p" ] || continue
    git apply --ignore-space-change --ignore-whitespace "$p" 2>/dev/null \
        || patch -p1 -F3 --no-backup-if-mismatch < "$p" \
        || echo "WARN: $(basename $p) could not apply, skipping"
done

# Merge WiFi driver files (mt76/mac80211 patches + MT7996 firmware, wifi-scripts)
# rsync --archive merges into existing directories without removing anything.
MTK_FILES="$MTK_BASE/files"
for pkg in \
    package/kernel/mt76 \
    package/kernel/mac80211 \
    package/network/config/wifi-scripts; do
    [ -d "$MTK_FILES/$pkg" ] && rsync -a "$MTK_FILES/$pkg/" "$pkg/"
done

rm -rf /tmp/mtk-openwrt-feeds
# ─────────────────────────────────────────────────────────────────────────────
