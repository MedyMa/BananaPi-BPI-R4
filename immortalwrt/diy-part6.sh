#!/bin/bash
#
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

# Select the correct mt76 Makefile patch based on the branch.
# master branch upstream already includes mt7990-firmware, so only
# the MODPARAMS addition is needed there.  openwrt-24.10 needs the
# full patch that also adds mt7990-firmware support.
if [ "$REPO_BRANCH" = "master" ]; then
    MT76_PATCH="1005-mt76-makefile-2ab64980-master.patch"
else
    MT76_PATCH="1005-mt76-makefile-2ab64980.patch"
fi

validate_and_apply_mt76_patch \
  "$GITHUB_WORKSPACE/patches/filogic/mt76/$MT76_PATCH"
