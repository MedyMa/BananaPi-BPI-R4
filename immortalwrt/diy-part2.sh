#!/bin/bash

sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

perl -0pi -e 's/\r\n/\n/g; s/\r/\n/g' \
  "$GITHUB_WORKSPACE/patches/filogic/mt76/1005-mt76-makefile-wed-enable-mt7990-firmware.patch"
(cd package/kernel/mt76 && patch -p1 < "$GITHUB_WORKSPACE/patches/filogic/mt76/1005-mt76-makefile-wed-enable-mt7990-firmware.patch")
