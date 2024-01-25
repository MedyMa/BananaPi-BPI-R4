#!/bin/bash
#=================================================
# File name: hook-feeds.sh
# Author: SuLingGG
# Blog: https://mlapp.cn
#=================================================

# Svn checkout packages from immortalwrt's repository
pushd customfeeds

# Add luci-app-eqos
git clone --depth=1 -b master https://github.com/immortalwrt/luci/applications/luci-app-eqos luci/applications/luci-app-eqos

# Add luci-proto-modemmanager
git clone --depth=1 -b master https://github.com/immortalwrt/luci/protocols/luci-proto-modemmanager luci/protocols/luci-proto-modemmanager

# Add tmate
git clone --depth=1 https://github.com/immortalwrt/openwrt-tmate

# Add gotop
git clone --depth=1 -b openwrt-18.06 https://github.com/immortalwrt/packages/admin/gotop packages/admin/gotop

# Add minieap
git clone --depth=1 -b master https://github.com/immortalwrt/packages/net/minieap packages/net/minieap
popd

# Set to local feeds
pushd customfeeds/packages
export packages_feed="$(pwd)"
popd
pushd customfeeds/luci
export luci_feed="$(pwd)"
popd
sed -i '/src-git packages/d' feeds.conf.default
echo "src-link packages $packages_feed" >> feeds.conf.default
sed -i '/src-git luci/d' feeds.conf.default
echo "src-link luci $luci_feed" >> feeds.conf.default

# Update feeds
./scripts/feeds update -a
