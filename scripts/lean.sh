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

rm -rf ../../customfeeds/packages/utils/apk
# Add apk (Apk Packages Manager)
merge_package https://github.com/openwrt/packages packages/utils/apk

# Add Lienol's Packages
git clone --depth=1 https://github.com/Lienol/openwrt-package
rm -rf ../../customfeeds/luci/applications/luci-app-kodexplorer
rm -rf openwrt-package/verysync
rm -rf openwrt-package/luci-app-verysync

# Add luci-app-ssr-plus
# mkdir helloworld
# pushd helloworld
# git clone --depth=1 https://github.com/fw876/helloworld
# popd

# Add luci-app-passwall
# git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall
# git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages

# Add luci-proto-minieap
git clone --depth=1 https://github.com/ysc3839/luci-proto-minieap

# Add OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash

# Add luci-app-adguardhome
git clone --depth=1 https://github.com/MedyMa/luci-app-adguardhome

# Add luci-app-dockerman
rm -rf ../../customfeeds/luci/applications/luci-app-docker
git clone --depth=1 https://github.com/lisaac/luci-app-dockerman
git clone --depth=1 https://github.com/lisaac/luci-lib-docker

# Add luci-theme-argon
git clone --depth=1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
rm -rf ../../customfeeds/luci/themes/luci-theme-argon

# Add subconverter
git clone --depth=1 https://github.com/tindy2013/openwrt-subconverter

# Add OpenAppFilter
git clone --depth=1 https://github.com/destan19/OpenAppFilter
popd

# Add CPUInfo
#pushd feeds/luci/modules/luci-mod-admin-full/luasrc/view/admin_status
#sed -i '/Load Average/i\\t\t<tr><td width="33%"><%:CPU Temperature%></td><td><%=luci.sys.exec("cut -c1-2 /sys/class/thermal/thermal_zone0/temp")%><span>&#8451;</span></td></tr>' index.htm
#sed -i '/Load Average/i\\t\t<tr><td width="33%"><%:欢迎订阅 Youbube 频道%></td><td><a href="https://www.youtube.com"><%:YOURENAME%></a></td></tr>' index.htm
#sed -i 's/pcdata(boardinfo.system or "?")/"ARMv8"/' index.htm
#sed -i 's/<%=luci.sys.exec("cat \/etc\/bench.log") or " "%>//' index.htm
#sed -i 's|pcdata(boardinfo.system or "?")|luci.sys.exec("uname -m") or "?"|g' index.htm
#sed -i 's/or "1"%>/or "1"%> ( <%=luci.sys.exec("expr `cat \/sys\/class\/thermal\/thermal_zone0\/temp` \/ 1000") or "?"%> \&#8451; ) /g' index.htm
#popd

# Add luci-app-ddnsto
pushd package/network/services
git clone --depth=1 https://github.com/linkease/nas-packages-luci
rm -rf luci/luci-app-istorex luci-app-linkease luci-app-quickstart luci-app-unishare luci-lib-iform
git clone --depth=1 https://github.com/linkease/nas-packages
rm -rf multimedia
rm -rf network/services/linkease quickstart unishare webdav2
popd

# Mod zzz-default-settings
pushd package/lean/default-settings/files
sed -i '/http/d' zzz-default-settings
sed -i '/18.06/d' zzz-default-settings
export orig_version=$(cat "zzz-default-settings" | grep DISTRIB_REVISION= | awk -F "'" '{print $2}')
export date_version=$(date -d "$(rdate -n -4 -p pool.ntp.org)" +'%Y-%m-%d')
sed -i "s/${orig_version}/${orig_version} ${date_version}/g" zzz-default-settings
popd


# Fix mt76 wireless driver
pushd package/kernel/mt76
sed -i '/mt7662u_rom_patch.bin/a\\techo mt76-usb disable_usb_sg=1 > $\(1\)\/etc\/modules.d\/mt76-usb' Makefile
popd

# Change default shell to zsh
sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Test kernel 5.10
#sed -i 's/5.15/5.4/g' target/linux/rockchip/Makefile

# Custom configs
echo -e " Lean's OpenWrt built on "$(date +%Y.%m.%d)"\n -----------------------------------------------------" >> package/base-files/files/etc/banner
echo 'net.bridge.bridge-nf-call-iptables=0' >> package/base-files/files/etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-ip6tables=0' >> package/base-files/files/etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-arptables=0' >> package/base-files/files/etc/sysctl.conf
echo 'net.bridge.bridge-nf-filter-vlan-tagged=0' >> package/base-files/files/etc/sysctl.conf

# Add CUPInfo
#pushd package/lean/autocore/files/arm/sbin
#cp -f $GITHUB_WORKSPACE/scripts/cpuinfo cpuinfo
#popd
