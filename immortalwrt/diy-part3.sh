#!/bin/bash
set -e

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

# Patch luci-app-hypermodem for mainline PCIe/MHI runtime
function patch_hypermodem_runtime(){
python3 - <<'PY'
from pathlib import Path
import re

def replace_once(path: Path, old: str, new: str):
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Patch anchor not found: {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

def regex_replace_once(path: Path, pattern: str, repl: str):
    text = path.read_text(encoding="utf-8")
    new_text, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Regex patch failed: {path}\nPattern: {pattern}")
    path.write_text(new_text, encoding="utf-8")

lua_matches = list(Path("package").rglob("luci-app-hypermodem/luasrc/model/cbi/hypermodem.lua"))
init_matches = list(Path("package").rglob("luci-app-hypermodem/root/etc/init.d/hypermodem"))

if len(lua_matches) != 1 or len(init_matches) != 1:
    raise SystemExit(f"Unexpected file count: lua={len(lua_matches)}, init={len(init_matches)}")

lua_path = lua_matches[0]
init_path = init_matches[0]

replace_once(
    lua_path,
    """device = s:option(Value, "device", translate("Modem device"))
device.rmempty = false

local device_suggestions = nixio.fs.glob("/dev/cdc-wdm*")

if device_suggestions then
\tlocal node
\tfor node in device_suggestions do
\t\tdevice:value(node)
\tend
end""",
    """device = s:option(Value, "device", translate("Modem device"))
device.rmempty = false

local seen_devices = {}
local device_patterns = {
    "/dev/cdc-wdm*",
    "/dev/mhi_*"
}

for _, pattern in ipairs(device_patterns) do
    local device_suggestions = nixio.fs.glob(pattern)
    if device_suggestions then
        local node
        for node in device_suggestions do
            if not seen_devices[node] then
                seen_devices[node] = true
                device:value(node)
            end
        end
    end
end"""
)

helper_block = """

find_base_network_interface_by_path()
{
    local search_path="$1"
    local net_path
    local net_name

    while [ -n "$search_path" ] && [ "$search_path" != "/" ]; do
        for net_path in "${search_path}"/net/*; do
            [ -e "$net_path" ] || continue
            net_name="$(basename "${net_path}")"
            case "$net_name" in
                rmnet_mhi*|mhi_hwip*|wwan*|rmnet_data*)
                    echo "$net_name"
                    return 0
                    ;;
            esac
        done
        search_path="$(dirname "${search_path}")"
    done

    return 1
}

resolve_network_interface_name()
{
    local base_name="$1"

    [ -z "$base_name" ] && return 1

    if [ -d "/sys/class/net/${base_name}_1" ]; then
        echo "${base_name}_1"
    elif [ -d "/sys/class/net/${base_name}.1" ]; then
        echo "${base_name}.1"
    else
        echo "${base_name}"
    fi
}

find_network_interface_by_device()
{
    local device="$1"
    local devname
    local devicepath
    local devpath
    local base_name

    devname="$(basename "${device}")"
    devicepath="$(find /sys/class -name "${devname}" 2>/dev/null | head -n 1)"
    [ -z "$devicepath" ] && return 1

    devpath="$(readlink -f "${devicepath}/device/" 2>/dev/null)"
    [ -z "$devpath" ] && return 1

    base_name="$(find_base_network_interface_by_path "${devpath}")"
    [ -z "$base_name" ] && return 1

    resolve_network_interface_name "${base_name}"
}
"""

regex_replace_once(
    init_path,
    r"\nset_interface\(\)\n\{",
    helper_block + "\nset_interface()\n{"
)

regex_replace_once(
    init_path,
    r'devname="\$\(basename "\$\{device\}"\)"\s*devicepath="\$\(find /sys/class/? -name\s*\$\{devname\}\)"\s*devpath="\$\(readlink -f \$\{devicepath\}/device/\)"\s*network="\$\( ls "\$\{devpath\}"/net\s*\)"',
    """devname="$(basename "${device}")"
        devicepath="$(find /sys/class -name "${devname}" 2>/dev/null | head -n 1)"
        devpath="$(readlink -f "${devicepath}/device/" 2>/dev/null)"
        network="$(find_network_interface_by_device "${device}")"
        [ -z "$network" ] && [ -n "$devpath" ] && network="$(resolve_network_interface_name "$(ls "${devpath}"/net 2>/dev/null | head -n 1)")" """
)

regex_replace_once(
    init_path,
    r'if \[ "\$device" != "" \];\s*then\s*procd_append_param command -i "\$network"\s*fi',
    """if [ -n "$network" ]; then
            procd_append_param command -i "$network"
        fi"""
)

regex_replace_once(
    init_path,
    r'local network_interface\s*if \[ -d /sys/class/net/rmnet_mhi0 \];\s*then\s*network_interface="rmnet_mhi0\.1"\s*elif \[ -d /sys/class/net/wwan0_1 \];\s*then\s*network_interface="wwan0_1"\s*elif \[ -d /sys/class/net/wwan0\.1 \];\s*then\s*network_interface="wwan0\.1"\s*elif \[ -d /sys/class/net/wwan0 \];\s*then\s*network_interface="wwan0"\s*fi\s*set_interface "\$\{network_interface\}"',
    """local network_interface="$network"
        [ -z "$network_interface" ] && network_interface="$(find_network_interface_by_device "${device}")"
        [ -n "$network_interface" ] && set_interface "${network_interface}" """
)
PY
}

rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
# Clone community packages to package/community
mkdir -p package/community
pushd package/community
git clone --depth=1 https://github.com/fw876/helloworld
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
git clone --depth=1 https://github.com/1522042029/luci-app-socat
# git clone --depth=1 https://github.com/Siriling/5G-Modem-Support
# merge_package https://github.com/kenzok8/jell jell/luci-app-fan
merge_package https://github.com/Siriling/5G-Modem-Support 5G-Modem-Support/luci-app-modem
merge_package https://github.com/Siriling/5G-Modem-Support 5G-Modem-Support/luci-app-hypermodem
merge_package https://github.com/Siriling/5G-Modem-Support 5G-Modem-Support/ndisc
merge_package https://github.com/DHDAXCW/dhdaxcw-app dhdaxcw-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app-sfp-status luci-app-sfp-status/Luci-app
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
# merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/relevance/ddnsto
# merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages-luci" nas-packages-luci/luci/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages" nas-packages/network/services/ddnsto
popd

# Mainline adaptation for 5G modem apps
find package -path '*/luci-app-modem/Makefile' -exec sed -i '/+kmod-pcie_mhi \\/d' {} \;
find package -path '*/luci-app-hypermodem/Makefile' -exec sed -i '/+kmod-pcie_mhi \\/d' {} \;
patch_hypermodem_runtime

# add luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# add luci-app-OpenClash
mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash
git config core.sparsecheckout true
popd

# wireless-regdb modification
# rm -rf package/firmware/wireless-regdb/patches/*.*
# rm -rf package/firmware/wireless-regdb/Makefile
# cp -f $GITHUB_WORKSPACE/patches/filogic/500-tx_power.patch package/firmware/wireless-regdb/patches/500-tx_power.patch
# cp -f $GITHUB_WORKSPACE/patches/filogic/regdb.Makefile package/firmware/wireless-regdb/Makefile

./scripts/feeds update -a
