#!/bin/bash

sed -i 's/192.168.6.1/192.168.2.1/g' package/base-files/files/bin/config_generate

if [ -f package/base-files/files/etc/shadow ]; then
  sed -i -E 's#^root:[^:]*:#root::#' package/base-files/files/etc/shadow
fi

if ! grep -q '_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile; then
  if grep -q 'TARGET_CFLAGS := \$(filter-out -O%' package/libs/mbedtls/Makefile; then
    sed -i '/TARGET_CFLAGS := \$(filter-out -O%/a TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile
  else
    echo 'TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' >> package/libs/mbedtls/Makefile
  fi
fi

# Check the resolved package selection for the private BE14 image.
make defconfig && bash "$(dirname -- "${BASH_SOURCE[0]}")/diy-mtk.sh" --verify-wext .config
