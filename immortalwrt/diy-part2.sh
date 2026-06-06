#!/bin/bash
#
# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Keep the mt76 package Makefile patch as a standalone patch so the local
# packaging changes stay tracked in the workspace and validated with patch(1).
perl -0pi -e 's/\r\n/\n/g; s/\r/\n/g' \
  "$GITHUB_WORKSPACE/patches/filogic/mt76/1005-mt76-makefile-2ab64980.patch"
(cd package/kernel/mt76 && patch -p1 < "$GITHUB_WORKSPACE/patches/filogic/mt76/1005-mt76-makefile-2ab64980.patch")
