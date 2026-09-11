#!/bin/bash

# Modify default IP
sed -i 's/192.168.6.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Keep root password empty (user must set it after first login)
if [ -f package/base-files/files/etc/shadow ]; then
  sed -i -E 's#^root:[^:]*:#root::#' package/base-files/files/etc/shadow
fi

# GCC 14 + musl fortify: mbedtls fails with "always_inline memset: target specific
# option mismatch"; disable _FORTIFY_SOURCE for mbedtls only.
if ! grep -q '_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile; then
  if grep -q 'TARGET_CFLAGS := \$(filter-out -O%' package/libs/mbedtls/Makefile; then
    sed -i '/TARGET_CFLAGS := \$(filter-out -O%/a TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile
  else
    echo 'TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' >> package/libs/mbedtls/Makefile
  fi
fi
