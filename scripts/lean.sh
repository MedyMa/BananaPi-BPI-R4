#!/bin/bash
#=================================================
# Description: DIY script
# Lisence: MIT
# Author: P3TERX
# Blog: https://p3terx.com
#=================================================

# Clone community packages to package/community
mkdir package/community
pushd package/community

# Merge_package
function merge_package(){
    repo=`echo $1 | rev | cut -d'/' -f 1 | rev`
    pkg=`echo $2 | rev | cut -d'/' -f 1 | rev`
    # find package/ -follow -name $pkg -not -path "package/openwrt-packages/*" | xargs -rt rm -rf
    git clone --depth=1 --single-branch $1
    [ -d package/openwrt-packages ] || mkdir -p package/openwrt-packages
    mv $2 package/openwrt-packages/
    rm -rf $repo
}

# # rm -rf ../../customfeeds/packages/utils/apk
# # # Add apk (Apk Packages Manager)
# # merge_package https://github.com/openwrt/packages packages/utils/apk

# # Add OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash

# Add luci-theme-argon
git clone --depth=1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
rm -rf ../../customfeeds/luci/themes/luci-theme-argon

# Add subconverter
# git clone --depth=1 https://github.com/tindy2013/openwrt-subconverter

# Add OpenAppFilter
# git clone --depth=1 https://github.com/destan19/OpenAppFilter
popd

# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Test kernel 5.10
sed -i 's/6.1/6.6/g' target/linux/rockchip/Makefile

rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 22.x feeds/packages/lang/golang

# Custom configs
echo -e "OpenWrt built on "$(date +%Y.%m.%d)"\n -----------------------------------------------------" >> package/base-files/files/etc/banner
# echo 'net.bridge.bridge-nf-call-iptables=0' >> package/base-files/files/etc/sysctl.conf
# echo 'net.bridge.bridge-nf-call-ip6tables=0' >> package/base-files/files/etc/sysctl.conf
# echo 'net.bridge.bridge-nf-call-arptables=0' >> package/base-files/files/etc/sysctl.conf
# echo 'net.bridge.bridge-nf-filter-vlan-tagged=0' >> package/base-files/files/etc/sysctl.conf

# Add CUPInfo
#pushd package/lean/autocore/files/arm/sbin
#cp -f $GITHUB_WORKSPACE/scripts/cpuinfo cpuinfo
#popd
