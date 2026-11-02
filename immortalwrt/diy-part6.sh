#!/bin/bash

set -e

configure_official_25_12() {
    local selected_device required
    [ -r .config ] || { echo 'Missing ordinary 25.12 .config' >&2; return 1; }
    make defconfig

    selected_device="$(sed -n '/^CONFIG_TARGET_.*_DEVICE_.*=y$/p' .config)"
    if [ "$selected_device" != 'CONFIG_TARGET_mediatek_filogic_DEVICE_bananapi_bpi-r4=y' ]; then
        echo "Ordinary 25.12 must select only BPI-R4; resolved devices: $selected_device" >&2
        return 1
    fi
    for required in \
        'CONFIG_TARGET_mediatek_filogic=y' \
        'CONFIG_TARGET_PROFILE="DEVICE_bananapi_bpi-r4"' \
        'CONFIG_PACKAGE_kmod-mt7996e=y' \
        'CONFIG_PACKAGE_kmod-mt7990-firmware=y'; do
        grep -qxF "$required" .config || {
            echo "Ordinary 25.12 profile lost a required setting: $required" >&2
            return 1
        }
    done
}

case "${1:-}" in
    --configure) configure_official_25_12; exit ;;
    "") configure_official_25_12 ;;
    *) echo "Unknown DIY mode: $1" >&2; exit 2 ;;
esac

# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

validate_and_apply_mt76_patch() {
    local patch_file="$1"

    [ -f "$patch_file" ] || {
        echo "Missing patch file: $patch_file" >&2
        return 2
    }

    perl -0pi -e 's/\r\n/\n/g; s/\r/\n/g' "$patch_file"

    if (cd package/kernel/mt76 && patch -p1 -R --dry-run < "$patch_file" >/dev/null 2>&1); then
        echo "Patch already applied: $patch_file"
        return 0
    fi

    if ! (cd package/kernel/mt76 && patch -p1 --dry-run < "$patch_file" >/dev/null); then
        echo "Patch does not apply cleanly to the current mt76 Makefile: $patch_file" >&2
        return 1
    fi

    (cd package/kernel/mt76 && patch -p1 < "$patch_file")
}

# 25.12 上游自带 mt7990-firmware，只需追加 wed_enable=1 的 patch
MT76_PATCH="1007-mt76-makefile-wed-enable.patch"

validate_and_apply_mt76_patch \
  "$GITHUB_WORKSPACE/patches/filogic/mt76/$MT76_PATCH"
