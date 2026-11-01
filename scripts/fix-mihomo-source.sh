#!/bin/sh
set -eu

recipe=package/community/helloworld/mihomo/Makefile
[ -f "$recipe" ] || {
    echo "Missing Mihomo source recipe: $recipe" >&2
    exit 1
}

# Scope this correction to the broken 1.19.33 recipe. Both GitHub archive
# and Git fallback downloads in the firmware CI produced the same hash.
# The commit is the upstream v1.19.33 tag observed in that CI checkout.
grep -qxF 'PKG_VERSION:=1.19.33' "$recipe" || exit 0
grep -qxF 'PKG_MIRROR_HASH:=2e37b49d2c9c25baa850e08f008cfdb133a16df7f6b0b078178086a10e3233a7' "$recipe" || exit 0

if ! grep -qxF 'PKG_SOURCE_PROTO:=git' "$recipe" ||
   ! grep -qxF 'PKG_SOURCE_URL:=https://github.com/MetaCubeX/mihomo.git' "$recipe" ||
   ! grep -qxF 'PKG_SOURCE_VERSION:=v$(PKG_VERSION)' "$recipe"; then
    echo 'Unexpected Mihomo source layout; review before updating its hash' >&2
    exit 1
fi

sed -i \
    -e 's/^PKG_SOURCE_VERSION:=v\$(PKG_VERSION)$/PKG_SOURCE_VERSION:=3f27ef39f8c96bbfbc8b0b9bb10f5c9ef60149d8/' \
    -e 's/^PKG_MIRROR_HASH:=2e37b49d2c9c25baa850e08f008cfdb133a16df7f6b0b078178086a10e3233a7$/PKG_MIRROR_HASH:=f29117485648124b819d5f790a27fceef3f8e2a9aceec6b12584bd99c8ab3fdf/' \
    "$recipe"

grep -qxF 'PKG_SOURCE_VERSION:=3f27ef39f8c96bbfbc8b0b9bb10f5c9ef60149d8' "$recipe"
grep -qxF 'PKG_MIRROR_HASH:=f29117485648124b819d5f790a27fceef3f8e2a9aceec6b12584bd99c8ab3fdf' "$recipe"
