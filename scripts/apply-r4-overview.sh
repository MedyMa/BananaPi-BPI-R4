#!/bin/bash
# Apply only the requested acceleration row. Undo the exact earlier CPU/temp
# patch when reusing a build workspace; refuse to overwrite any other edits.
set -euo pipefail
patch_file=${1:?overview patch path required}

if git apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    exit 0
fi

if ! git apply --check "$patch_file" >/dev/null 2>&1; then
    legacy=(
        'c81d2ebecccaafcf29d4fd421e43644e9129a9ba8f2b245fd40e517d5d0f63d2 8a7a87a777c7be145b3f5832c1e8b695887f63450fe7cf91719ff76f5eccf990 modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js'
        '4b02a92064a40852678d6e9e03b0267b19dc3dc5c4b060cf96e730a79f7f4253 2dd70d248edffd46b118b66355db4fac1c40331bce30200fed780df6694e0f67 modules/luci-mod-status/root/usr/share/rpcd/acl.d/luci-mod-status-index.json'
        'dd16922c22459a7dd3cc5ca8f40ccc45238eb75f4458a99972aec86a4030f73c 874c443816f819dca13c1503fb80b2ba9f48981f3f25584dcf037af3ce76320d modules/luci-base/po/zh_Hans/base.po'
    )
    staging=$(mktemp -d)
    trap 'rm -rf -- "$staging"' EXIT
    index=0
    for record in "${legacy[@]}"; do
        read -r old_hash base_hash relative <<< "$record"
        actual=$(sha256sum "feeds/luci/$relative" | awk '{print $1}')
        [ "$actual" = "$old_hash" ] || {
            echo "Unrecognized LuCI edits; refusing to overwrite feeds/luci/$relative" >&2
            exit 1
        }
        git -C feeds/luci show "HEAD:$relative" > "$staging/$index"
        [ "$(sha256sum "$staging/$index" | awk '{print $1}')" = "$base_hash" ] || {
            echo "LuCI base changed; refusing an automatic overview migration" >&2
            exit 1
        }
        index=$((index + 1))
    done
    index=0
    for record in "${legacy[@]}"; do
        read -r old_hash base_hash relative <<< "$record"
        cat "$staging/$index" > "feeds/luci/$relative"
        index=$((index + 1))
    done
fi

git apply --check "$patch_file"
git apply "$patch_file"
