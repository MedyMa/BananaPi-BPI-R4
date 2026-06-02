#!/bin/bash

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

patch_makefile_dep() {
    local file_path="$1"
    local old_text="$2"
    local new_text="$3"
    local perl_status

    [ -f "$file_path" ] || return 0
    grep -qF "$old_text" "$file_path" || return 0

    PATCH_OLD_TEXT="$old_text" PATCH_NEW_TEXT="$new_text" \
        perl -0pi -e 'BEGIN { $old = $ENV{"PATCH_OLD_TEXT"}; $new = $ENV{"PATCH_NEW_TEXT"}; }
            $count = s/\Q$old\E/$new/g;
            END { exit($count > 0 ? 0 : 2); }' "$file_path"
    perl_status=$?

    [ "$perl_status" -eq 0 ] || {
        echo "Failed to apply literal patch to $file_path" >&2
        return "$perl_status"
    }
}

apply_workspace_patch() {
    local patch_file="$1"

    [ -f "$patch_file" ] || return 0

    if git apply --ignore-space-change --ignore-whitespace --reverse --check "$patch_file" >/dev/null 2>&1; then
        return 0
    fi

    git apply --ignore-space-change --ignore-whitespace "$patch_file"
}

# Remove feeds packages that will be replaced by community clones below.
# This MUST run after the workflow's initial feeds update but BEFORE feeds install.
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-modemband
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}

# Clone community packages to package/community
mkdir -p package/community
pushd package/community
git clone --depth=1 https://github.com/fw876/helloworld
# rm -rf helloworld/{naiveproxy,shadowsocks-libev,shadowsocksr-libev,shadow-tls,simple-obfs,tcping,tuic-client,v2ray-plugin,xray-core,xray-plugin}
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
[ -f openwrt-passwall-packages/haproxy/Makefile ] && sed -i '/^[[:space:]]*ADDON+=USE_QUIC=1$/d' openwrt-passwall-packages/haproxy/Makefile
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall.git
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki
# rm -rf OpenWrt-nikki/{mihomo-meta,mihomo-alpha}
git clone --depth=1 https://github.com/1522042029/luci-app-socat
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
# git clone --depth=1 https://github.com/Siriling/5G-Modem-Support
# merge_package https://github.com/DHDAXCW/dhdaxcw-app dhdaxcw-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-fan
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-sfp-status
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-adguardhome
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-modemband
merge_package https://github.com/MedyMa/luci-app luci-app/Luci-app/luci-app-turboacc-mtk
merge_package https://github.com/kenzok8/jell jell/wrtbwmon
# merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/relevance/ddnsto
# merge_package "-b Immortalwrt https://github.com/shidahuilang/openwrt-package" openwrt-package/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages-luci" nas-packages-luci/luci/luci-app-ddnsto
merge_package "-b ddnsto-beta https://github.com/linkease/nas-packages" nas-packages/network/services/ddnsto
popd

# Replace immortalwrt mt76 with BPI-R4PRO custom mt76;
# also pull mtk_hnat driver + mtk_eth_dbg dependency + hnat kernel patches.
rm -rf package/kernel/mt76
git clone --depth=1 --filter=blob:none --sparse \
    https://github.com/BPI-SINOVOIP/BPI-R4PRO-8X-OPENWRT-V24.10.0-Master-Devel \
    bpi-r4pro-src
pushd bpi-r4pro-src
git sparse-checkout set \
    package/kernel/mt76 \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek \
    target/linux/mediatek/files-6.6/include \
    target/linux/mediatek/patches-6.6
popd

mv bpi-r4pro-src/package/kernel/mt76 package/kernel/mt76

# Fix BPI-R4PRO mt76 API incompatibilities with ImmortalWrt's mac80211 backports-6.12.61.
# Root cause: BPI-R4PRO mt76 vendor patches add TTLM/ATTLM hooks and a WED PPE helper
# that do not match ImmortalWrt 24.10's backported mac80211 / WED APIs.
# Strategy: rewrite the incompatible blocks after patch application but before compile,
# using function/block-level substitutions instead of brittle line deletions.
cat > package/kernel/mt76/fix-compat.sh << 'FIXSCRIPT'
#!/bin/sh
D="$1"
[ -d "$D/mt7996" ] || exit 0

perl -0pi -e 's@#define MT7996_NEG_TTLM_SUPPORT FIELD_PREP_CONST\(\s*IEEE80211_MLD_CAP_OP_TID_TO_LINK_MAP_NEG_SUPP,\s*IEEE80211_MLD_CAP_OP_TID_TO_LINK_MAP_NEG_SUPP_DIFF\)\n\n@@s; s@2 \| MT7996_NEG_TTLM_SUPPORT@2@g' "$D/mt7996/init.c"
perl -0pi -e 's@\n\t\[4\] = WLAN_EXT_CAPA5_QOS_MAP,@@; s@\n\t\[6\] = WLAN_EXT_CAPA7_SCS_SUPPORT,@@; s@\n\t\[10\] = WLAN_EXT_CAPA11_MIRRORED_SCS_SUPPORT,@@; s@\n\twiphy_ext_feature_set\(wiphy, NL80211_EXT_FEATURE_STAS_COUNT\);@@; s@\n\teht_cap_elem->mac_cap_info\[1\] \|=\n\t\tIEEE80211_EHT_MAC_CAP1_UNSOL_EPCS_PRIO_ACCESS;@@' "$D/mt7996/init.c"

perl -0pi -e 's@\n\tif \(ieee80211_is_action\(fc\) &&\s*mgmt->u\.action\.category == WLAN_CATEGORY_PROTECTED_EHT &&\s*\(mgmt->u\.action\.u\.ttlm_req\.action_code ==\s*WLAN_PROTECTED_EHT_ACTION_TTLM_REQ \|\|\s*mgmt->u\.action\.u\.ttlm_req\.action_code ==\s*WLAN_PROTECTED_EHT_ACTION_TTLM_RES \|\|\s*mgmt->u\.action\.u\.ttlm_req\.action_code ==\s*WLAN_PROTECTED_EHT_ACTION_TTLM_TEARDOWN\)\)\s*\n\t\treturn true;\n@@s' "$D/mt7996/mac.c"
perl -0pi -e 's@\n\tstruct ieee80211_neg_ttlm merged_ttlm;@@; s@\n\tmt7996_get_merged_ttlm\(vif, &merged_ttlm\);\n\tret = mt7996_mcu_peer_mld_ttlm_req\(dev, vif, sta, &merged_ttlm\);\n\tif \(ret\)\n\t\tgoto fail;\n@\n\tret = 0;\n@s' "$D/mt7996/mac.c"

perl -0pi -e 's@if \(\(changed & BSS_CHANGED_MLD_VALID_LINKS\) &&\s*\(changed & \(BSS_CHANGED_MLD_ADV_TTLM \| BSS_CHANGED_MLD_NEG_TTLM\)\)\)\s*\n\s*mt7996_mcu_peer_mld_ttlm_req\(dev, vif, changed\);\n@@s' "$D/mt7996/main.c"
perl -0pi -e 's@static int\s+mt7996_set_ttlm\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif\)\s*\{.*?\n\}\n\nstatic int@static int\nmt7996_set_ttlm(struct ieee80211_hw *hw, struct ieee80211_vif *vif)\n{\n\treturn -EOPNOTSUPP;\n}\n\nstatic int@s' "$D/mt7996/main.c"
perl -0pi -e 's@static int\s+mt7996_set_sta_ttlm\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\s*struct ieee80211_sta \*sta, struct ieee80211_neg_ttlm \*neg_ttlm\)\s*\{.*?\n\}\n\nstatic int@static int\nmt7996_set_sta_ttlm(struct ieee80211_hw *hw, struct ieee80211_vif *vif,\n\t\t    struct ieee80211_sta *sta, struct ieee80211_neg_ttlm *neg_ttlm)\n{\n\treturn -EOPNOTSUPP;\n}\n\nstatic int@s' "$D/mt7996/main.c"
perl -0pi -e 's@static enum ieee80211_neg_ttlm_res\s+mt7996_can_neg_ttlm\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\s*struct ieee80211_neg_ttlm \*neg_ttlm\)\s*\{.*?\n\}\n\nstatic void@static enum ieee80211_neg_ttlm_res\nmt7996_can_neg_ttlm(struct ieee80211_hw *hw, struct ieee80211_vif *vif,\n\t\t    struct ieee80211_neg_ttlm *neg_ttlm)\n{\n\treturn 0;\n}\n\nstatic void@s' "$D/mt7996/main.c"
perl -0pi -e 's@\n\s*\.set_attlm = mt7996_set_attlm,@@; s@\n\s*\.set_sta_ttlm = mt7996_set_sta_ttlm,@@; s@\n\s*\.can_neg_ttlm = mt7996_can_neg_ttlm,@@; s@\n\s*\.set_ttlm = mt7996_set_ttlm,@@' "$D/mt7996/main.c"
perl -0pi -e 's@static int\Rmt7996_set_ttlm\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif\)\R\{.*?\R\}\R\Rstatic int\Rmt7996_set_sta_ttlm\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\R\t\t    struct ieee80211_sta \*sta, struct ieee80211_neg_ttlm \*neg_ttlm\)\R\{.*?\R\}\R\Rstatic int\Rmt7996_set_attlm\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\R\t\t u16 disabled_links, u16 switch_time, u32 duration\)\R\{.*?\R\}\R\Rstatic enum ieee80211_neg_ttlm_res\Rmt7996_can_neg_ttlm\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\R\t\t    struct ieee80211_neg_ttlm \*neg_ttlm\)\R\{.*?\R\}\R\R@@s' "$D/mt7996/main.c"
perl -0pi -e 's@\n\t\tieee80211_tsf_offset_notify\(vif, rpted_linkid, rpted_mconf->tsf_offset,\R\t\t\t\t\t    sizeof\(rpted_mconf->tsf_offset\), GFP_KERNEL\);@@; s@\n\t\tcfg80211_background_radar_update_channel\(hw->wiphy, c, expand\);@@; s@\n\tu8 dscp = path->mtk_wdma\.tid >> 2;@@; s@\n\tpath->mtk_wdma\.tid = mvif->qos_map\[dscp\];@@' "$D/mt7996/main.c"
perl -0pi -e 's@mt7996_get_txpower\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\R\t\t   unsigned int link_id, int \*dbm\)@mt7996_get_txpower(struct ieee80211_hw *hw, struct ieee80211_vif *vif, int *dbm)@; s@(mt7996_get_txpower\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif, int \*dbm\)\R\{\R\tstruct mt7996_dev \*dev = mt7996_hw_dev\(hw\);\R)(?:\tunsigned int link_id = 0;\R)+@$1\tunsigned int link_id = 0;\n@s; s@(mt7996_get_txpower\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif, int \*dbm\)\R\{\R\tstruct mt7996_dev \*dev = mt7996_hw_dev\(hw\);\R)(?!\tunsigned int link_id = 0;)@$1\tunsigned int link_id = 0;\n@s' "$D/mt7996/main.c"
perl -0pi -e 's@static void mt7996_sta_link_statistics\(struct ieee80211_hw \*hw,\R\t\t\t\t       struct ieee80211_vif \*vif,\R\t\t\t\t       struct ieee80211_sta \*sta,\R\t\t\t\t       unsigned int link_id,\R\t\t\t\t       struct station_link_info \*linfo\)\R\{.*?\R\}\R\R@@s' "$D/mt7996/main.c"
perl -0pi -e 's@static void mt7996_link_sta_rc_update\(struct ieee80211_hw \*hw,\R\t\t\t\t      struct ieee80211_vif \*vif,\R\t\t\t\t      struct ieee80211_link_sta \*link_sta,\R\t\t\t\t      u32 changed\)\R\{\R\tstruct ieee80211_sta \*sta = link_sta->sta;@static void mt7996_link_sta_rc_update(struct ieee80211_hw *hw,\n\t\t\t\t      struct ieee80211_vif *vif,\n\t\t\t\t      struct ieee80211_sta *sta,\n\t\t\t\t      u32 changed)\n{@' "$D/mt7996/main.c"
perl -0pi -e 's@mt7996_set_bitrate_mask\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\R\t\t\tconst struct cfg80211_bitrate_mask \*mask,\R\t\t\tunsigned int link_id\)@mt7996_set_bitrate_mask(struct ieee80211_hw *hw, struct ieee80211_vif *vif,\n\t\t\tconst struct cfg80211_bitrate_mask *mask)@; s@(mt7996_set_bitrate_mask\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\R\t\t\tconst struct cfg80211_bitrate_mask \*mask\)\R\{\R\tstruct mt7996_dev \*dev = mt7996_hw_dev\(hw\);\R)(?:\tunsigned int link_id = 0;\R)+@$1\tunsigned int link_id = 0;\n@s; s@(mt7996_set_bitrate_mask\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\R\t\t\tconst struct cfg80211_bitrate_mask \*mask\)\R\{\R\tstruct mt7996_dev \*dev = mt7996_hw_dev\(hw\);\R)(?!\tunsigned int link_id = 0;)@$1\tunsigned int link_id = 0;\n@s' "$D/mt7996/main.c"
perl -0pi -e 's@static int\Rmt7996_set_qos_map\(struct ieee80211_hw \*hw, struct ieee80211_vif \*vif,\R\t\t   struct cfg80211_qos_map \*qos_map\)\R\{.*?\R\}\R\R@@s' "$D/mt7996/main.c"
perl -0pi -e 's@\n\s*\.link_sta_rc_update = mt7996_link_sta_rc_update,@\n\t.sta_rc_update = mt7996_link_sta_rc_update,@; s@\n\s*\.sta_link_statistics = mt7996_sta_link_statistics,@@; s@\n\s*\.set_qos_map = mt7996_set_qos_map,@@' "$D/mt7996/main.c"
perl -0pi -e 's@static int\nmt7996_set_ttlm@static int __maybe_unused\nmt7996_set_ttlm@; s@static int\nmt7996_set_sta_ttlm@static int __maybe_unused\nmt7996_set_sta_ttlm@; s@static int\nmt7996_set_attlm@static int __maybe_unused\nmt7996_set_attlm@; s@static enum ieee80211_neg_ttlm_res\nmt7996_can_neg_ttlm@static enum ieee80211_neg_ttlm_res __maybe_unused\nmt7996_can_neg_ttlm@' "$D/mt7996/main.c"

perl -0pi -e 's@\s*ieee80211_attlm_notify\([^;]*;\s*@@g' "$D/mt7996/mcu.c"
perl -0pi -e 's@wiphy_ext_feature_isset\(mphy->hw->wiphy,\s*NL80211_EXT_FEATURE_STAS_COUNT\)@false@s' "$D/mt7996/mcu.c"
perl -0pi -e 's@__dev_sw_netstats_rx_add\(wdev->netdev,\s*rx_packets,\s*rx_bytes\)@dev_sw_netstats_rx_add(wdev->netdev, rx_bytes)@g; s@\n\s*ieee80211_tpt_led_trig_tx\(mphy->hw, tx_bytes\);@@; s@\n\s*ieee80211_tpt_led_trig_rx\(mphy->hw, rx_bytes\);@@; s@\n\s*ieee80211_links_removed\(vif, le16_to_cpu\(reconf->link_bitmap\)\);@@; s@\n\tstruct mt7996_mcu_mld_attlm_timeout_event \*ttlm = \(void \*\)data->data;@@; s@\n\s*ieee80211_crit_update_notify\(vif, link_id,\R\s*NL80211_CRIT_UPDATE_NONE,\R\s*GFP_ATOMIC\);@@; s@enum ieee80211_sta_rx_bandwidth cap_bw = ieee80211_link_sta_cap_bw\(link_sta\);@enum ieee80211_sta_rx_bandwidth cap_bw = link_sta->bandwidth;@; s@u8 cap_nss = ieee80211_link_sta_cap_nss\(link_sta\);@u8 cap_nss = link_sta->rx_nss;@; s@eht_mld->eml_cap = cpu_to_le16\(sta->eml_capa\);@eht_mld->eml_cap = 0;@; s@WLAN_CAPABILITY_NON_TX_BSSID_CU@0@g' "$D/mt7996/mcu.c"
perl -0pi -e 's@static void\Rmt7996_mcu_beacon_sta_prof_csa\(struct sk_buff \*rskb,\R\s*struct ieee80211_bss_conf \*conf,\R\s*struct ieee80211_mutable_offsets \*offs\)\R\{.*?\R\}\R\Rstatic void\Rmt7996_mcu_beacon_cont@static void\nmt7996_mcu_beacon_sta_prof_csa(struct sk_buff *rskb,\n\t\t\t       struct ieee80211_bss_conf *conf,\n\t\t\t       struct ieee80211_mutable_offsets *offs)\n{\n}\n\nstatic void\nmt7996_mcu_beacon_cont@s' "$D/mt7996/mcu.c"

perl -0pi -e 's@static void mt7996_dma_config\(struct mt7996_dev \*dev\)\R\{\R\tstruct mtk_wed_device \*wed = &dev->mt76\.mmio\.wed;\R@static void mt7996_dma_config(struct mt7996_dev *dev)\n{\n@; s@if \(mtk_wed_device_active\(wed\) && wed->version == MTK_WED_HW_V3_1\) \{@if (false) {@g; s@if \(wed->version == MTK_WED_HW_V3_1\)@if (false)@g; s@if \(mdev->mmio.wed.version == MTK_WED_HW_V3_1\)@if (false)@g; s@if \(mt76_wed_check_rx_cap\(wed\) && wed->version != MTK_WED_HW_V3_1\)@if (mt76_wed_check_rx_cap(wed))@g; s@if \(mt76_wed_check_rx_cap\(wed\) && wed->version == MTK_WED_HW_V3_1\)@if (false)@g' "$D/mt7996/dma.c"
perl -0pi -e 's#\R\tint wed_hw_ver;##; s#wed_hw_ver = mtk_wed_device_get_hw_version\(\);\R\ttx_token_size = MT7996_WED_TOKEN_SIZE;\R\R\tswitch \(wed_hw_ver\) \{.*?\R\t\treturn 0;\R\t\}#tx_token_size = MT7996_WED_TOKEN_SIZE;\n\tdev->mt76.hwrro_mode = MT76_HWRRO_V3;\n\trx_token_size = dev->hif2 ? 32768 : 24576;#s; s@wed_hw_ver == MTK_WED_HW_V3@1@g' "$D/mt7996/mmio.c"
perl -0pi -e 's@mdev->mmio.wed.version == MTK_WED_HW_V3_1@false@g' "$D/mt7996/mtk_debugfs.c"

perl -0pi -e 's@\s*if \(vif->neg_ttlm.valid\) \{.*?return;\s*\}@@s; s@\s*if \(vif->adv_ttlm.active\)\s*map &= vif->adv_ttlm.map;@@s' "$D/mt7996/mt7996.h"
perl -0pi -e 's@mtk_wed_device_ppe_drop\(&dev->mt76\.mmio\.wed, enable\);@/* backport WED PPE API is incompatible */@' "$D/mt7996/mt7996.h"
FIXSCRIPT

# Inject the script call as the FIRST line of Build/Compile using awk.
# Use -v to pass make-variable strings; awk's $ would otherwise expand them
# as field references ($0), corrupting the Makefile recipe line.
awk -v cmd='sh $(TOPDIR)/package/kernel/mt76/fix-compat.sh $(PKG_BUILD_DIR)' \
    '/^define Build\/Compile$/{print; print "\t" cmd; next}1' \
    package/kernel/mt76/Makefile > package/kernel/mt76/Makefile.tmp \
  && mv package/kernel/mt76/Makefile.tmp package/kernel/mt76/Makefile

mkdir -p target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek
cp -r bpi-r4pro-src/target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/
cp bpi-r4pro-src/target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_eth_dbg.{c,h} \
    target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/

# ra_nat.h and other kernel headers needed by hnat/skbuff patches
if [ -d bpi-r4pro-src/target/linux/mediatek/files-6.6/include ]; then
    cp -r bpi-r4pro-src/target/linux/mediatek/files-6.6/include/. \
        target/linux/mediatek/files-6.6/include/
fi

for patch in \
    999-2735-netfilter-nf_flow_table-support-hw-offload-through-v.patch \
    999-2736-net-8021q-support-hardware-flow-table-offload.patch \
    999-2737-net-bridge-support-hardware-flow-table-offload.patch \
    999-2738-net-pppoe-support-hardware-flow-table-offload.patch \
    999-2739-net-dsa-support-hardware-flow-table-offload.patch \
    999-2740-net-macvlan-support-hardware-flow-table-offload.patch \
    999-2741-mtkhnat-add-support-for-virtual-interface-a.patch \
    "999-2742-mtkhnat-tnl-interface-offload-check.patch.patch" \
    999-2743-mtkhnat-ipv6-fix-pskb-expand-head-limitatio.patch \
    999-2744-mtk-gso-skb-headroom-copy.patch \
    999-2745-mtkhnat-add-mtkhnat-driver-support.patch
do
    src="bpi-r4pro-src/target/linux/mediatek/patches-6.6/$patch"
    [ -f "$src" ] && cp "$src" target/linux/mediatek/patches-6.6/
done

# 999-2746 failed to apply (context mismatch); inject its defines directly into
# hnat.h so hnat.c compiles. MTK_FE_INT_STATUS2 is called MTK_INT_STATUS2 in
# ImmortalWrt — provide both names so the driver builds regardless of base.
# MTK_QTX_PER_PAGE: defined in BPI-R4PRO's mtk_eth_soc patches (not copied).
cat >> target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat/hnat.h << 'EOF'

/* PPE flow-check interrupt registers (injected; normally patched via 999-2746) */
#ifndef MTK_FE_INT_STATUS2
#define MTK_FE_INT_STATUS2		0x28
#endif
#ifndef MTK_FE_INT_ENABLE2
#define MTK_FE_INT_ENABLE2		0x2C
#endif
#ifndef MTK_FE_INT2_PPE0_FLOW_CHK
#define MTK_FE_INT2_PPE0_FLOW_CHK	BIT(28)
#endif
#ifndef MTK_FE_INT2_PPE1_FLOW_CHK
#define MTK_FE_INT2_PPE1_FLOW_CHK	BIT(29)
#endif

/* QDMA QTX per page (from BPI-R4PRO mtk_eth_soc patches; NETSYS V3 = 16) */
#ifndef MTK_QTX_PER_PAGE
#define MTK_QTX_PER_PAGE		16
#endif
EOF

# flow_offload_hw_path.tnl_type is added by BPI-R4PRO's 999-4100 TOPS patch
# which we do not carry.  Inject it via a numbered patch so it applies after
# 999-2741 (which already added virt_dev to the struct).
cat > target/linux/mediatek/patches-6.6/999-2741b-flow-offload-add-tnl-type.patch << 'PATCH'
--- a/include/net/netfilter/nf_flow_table.h
+++ b/include/net/netfilter/nf_flow_table.h
@@ -183,6 +183,7 @@ struct flow_offload_hw_path {
	struct net_device *dev;
	struct net_device *virt_dev;
+	u32 tnl_type;
	u32 flags;

	u8 eth_src[ETH_ALEN];
PATCH

rm -rf bpi-r4pro-src

# Kernel config symbols introduced by BPI-R4PRO hnat patches (999-2745).
# Without explicit values, syncconfig blocks in non-interactive CI.
# MT7988A is NETSYS V3; V3 selects V2 as base, so both are needed.
for kcfg in \
    CONFIG_MEDIATEK_NETSYS_V2=y \
    CONFIG_MEDIATEK_NETSYS_V3=y \
    CONFIG_MEDIATEK_NETSYS_RX_V2=y \
    CONFIG_NET_MEDIATEK_HNAT=m
do
    key="${kcfg%%=*}"
    grep -qF "$key" target/linux/mediatek/filogic/config-6.6 || \
        echo "$kcfg" >> target/linux/mediatek/filogic/config-6.6
done

# add luci-app-mosdns
rm -rf feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
rm -rf feeds/packages/net/mosdns
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# add luci-app-OpenClash
mkdir -p package/OpenClash
pushd package/OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash
popd

# merge_package "-b openwrt-24.10-6.6 https://github.com/padavanonly/immortalwrt-mt798x-6.6" immortalwrt-mt798x-6.6/package/mtk/applications/mtkhqos_util

# openwrt-24.10 compatibility fixes for floating packages feed metadata.
patch_makefile_dep \
    feeds/packages/lang/python/python-ubus/Makefile \
    'PKG_BUILD_DEPENDS:=python-setuptools/host' \
    'PKG_BUILD_DEPENDS:=python3/host'
patch_makefile_dep \
    package/feeds/packages/python-ubus/Makefile \
    'PKG_BUILD_DEPENDS:=python-setuptools/host' \
    'PKG_BUILD_DEPENDS:=python3/host'

patch_makefile_dep \
    feeds/packages/admin/zabbix/Makefile \
    'libnetsnmp-ssl' \
    'libnetsnmp'
patch_makefile_dep \
    package/feeds/packages/zabbix/Makefile \
    'libnetsnmp-ssl' \
    'libnetsnmp'
    
# Shrink the BPI-R4 U-Boot autoboot wait so boot time is not dominated by a 30s delay.
patch_makefile_dep \
    package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch \
    'CONFIG_BOOTDELAY=30' \
    'CONFIG_BOOTDELAY=10'

./scripts/feeds install -a
[ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/60_wifi.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1000-luci-status-overview-wifi7-mlo.patch"

[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1001-luci-network-wireless-station-hints.patch"

[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/999-luci-wireless-mtk-mode-matrix.patch"

[ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/60_wifi.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1002-luci-status-overview-rate-mhz-hi.patch"    

[ -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js ] && \
    apply_workspace_patch "$GITHUB_WORKSPACE/patches/filogic/1003-luci-wireless-mtk-mlo-ofdma-controls.patch"
