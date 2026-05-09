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

set -eu

PATCH_REL='luci-app-fan/kernel-snippets/patches/0001-arm64-dts-mt7988a-bpi-r4-enable-fan-tach-gpio21.patch'

if [ -n "${GITHUB_WORKSPACE:-}" ]; then
	PATCH_PATH="$GITHUB_WORKSPACE/$PATCH_REL"
else
	SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
	PATCH_PATH=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)/$PATCH_REL
fi

if [ ! -f "$PATCH_PATH" ]; then
	echo "BPI-R4 fan tach patch not found: $PATCH_PATH" >&2
	exit 1
fi

if git apply --reverse --check "$PATCH_PATH" >/dev/null 2>&1; then
	echo "BPI-R4 fan tach patch already applied"
	exit 0
fi

git apply --check "$PATCH_PATH"
git apply "$PATCH_PATH"

echo "Applied BPI-R4 fan tach patch: $PATCH_PATH"


