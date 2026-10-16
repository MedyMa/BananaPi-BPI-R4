#!/bin/bash
set -euo pipefail

# Run inside the cloned OpenWrt tree, before applying workspace customizations.
workspace="${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must identify the build repository}"
source_ref="$(tr -d '\r\n' < "$workspace/immortalwrt/MT7988/source.commit")"
[[ "$source_ref" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Invalid MT7988 source commit" >&2
    exit 1
}
[ -f include/toplevel.mk ] && [ -f scripts/feeds ] || {
    echo "MT7988 source preparation must run at the OpenWrt root" >&2
    exit 1
}

if ! git cat-file -e "$source_ref^{commit}" 2>/dev/null; then
    git fetch --depth=1 origin "$source_ref"
fi
git -c advice.detachedHead=false checkout --detach "$source_ref"
[ "$(git rev-parse HEAD)" = "$source_ref" ]
echo "MT7988 source locked to $source_ref"

# The workflow cache key predates the driver rollback. Retain host/tools and
# toolchain caches, but rebuild every target package and the kernel together.
for cache_path in build_dir/target-* staging_dir/target-*; do
    [ ! -e "$cache_path" ] || rm -rf -- "$cache_path"
done
rm -rf -- tmp bin
