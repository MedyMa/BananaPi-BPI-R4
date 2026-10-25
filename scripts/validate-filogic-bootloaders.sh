#!/usr/bin/env bash
set -euo pipefail

# Run from the configured OpenWrt source tree on a Linux Actions runner.
out="${1:?validation output directory required}"
mkdir -p "$out"
git rev-parse HEAD > "$out/source-sha.txt"
cp .config "$out/resolved.config"
sha256sum .config > "$out/config.sha256"

variants=(mt7988_bananapi_bpi-r4-emmc mt7988_bananapi_bpi-r4-snand mt7988_bananapi_bpi-r4-sdmmc)
atf=(mt7988-emmc-comb mt7988-spim-nand-ubi-comb mt7988-sdmmc-comb)
for variant in "${variants[@]}"; do
    grep -qx "CONFIG_PACKAGE_u-boot-${variant}=y" .config
done
for variant in "${atf[@]}"; do
    grep -qx "CONFIG_PACKAGE_trusted-firmware-a-${variant}=y" .config
done

run_make() {
    local label="$1"
    shift
    printf '%q ' make -j2 "$@" V=s > "$out/${label}.command"
    printf '\n' >> "$out/${label}.command"
    set +e
    make -j2 "$@" V=s 2>&1 | tee "$out/${label}.log"
    local result="${PIPESTATUS[0]}"
    set -e
    printf '%s\n' "$result" > "$out/${label}.exit"
    return "$result"
}

run_make tools tools/install
run_make toolchain toolchain/install
run_make atf package/boot/arm-trusted-firmware-mediatek/compile
run_make uboot package/boot/uboot-mediatek/compile

mkdir -p "$out/images"
for variant in "${atf[@]}"; do
    mapfile -t images < <(find staging_dir/target-*/image -maxdepth 1 -type f -name "${variant}-bl2.img")
    [ "${#images[@]}" -eq 1 ] && [ -s "${images[0]}" ]
    cp "${images[0]}" "$out/images/"
done
for medium in emmc snand sdmmc; do
    mapfile -t images < <(find staging_dir/target-*/image -maxdepth 1 -type f -name "mt7988_bananapi_bpi-r4-${medium}-u-boot.fip")
    [ "${#images[@]}" -eq 1 ] && [ -s "${images[0]}" ]
    cp "${images[0]}" "$out/images/"
done
(cd "$out" && sha256sum images/* > images.sha256)
