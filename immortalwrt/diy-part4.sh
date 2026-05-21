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
