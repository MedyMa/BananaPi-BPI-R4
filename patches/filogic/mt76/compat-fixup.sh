#!/bin/sh

build_dir="$1"

perl -0pi -e 's/^.*WLAN_EXT_CAPA5_QOS_MAP.*\r?\n//mg; s/^.*WLAN_EXT_CAPA7_SCS_SUPPORT.*\r?\n//mg; s/^.*WLAN_EXT_CAPA11_MIRRORED_SCS_SUPPORT.*\r?\n//mg; s/^.*NL80211_EXT_FEATURE_STAS_COUNT.*\r?\n//mg' "$build_dir/mt7996/init.c"
perl -0pi -e 's/\n\s*ieee80211_tsf_offset_notify\(vif, rpted_linkid, rpted_mconf->tsf_offset,\n\s*sizeof\(rpted_mconf->tsf_offset\), GFP_KERNEL\);\n/\n/s' "$build_dir/mt7996/main.c"
perl -0pi -e 's/\n\s*cfg80211_background_radar_update_channel\(hw->wiphy, c, expand\);\n/\n/s' "$build_dir/mt7996/main.c"
perl -0pi -e 's/\n\s*ieee80211_tpt_led_trig_tx\(mphy->hw, tx_bytes\);\n\s*ieee80211_tpt_led_trig_rx\(mphy->hw, rx_bytes\);\n/\n/s' "$build_dir/mt7996/mcu.c"
perl -0pi -e 's/^\s*struct mt7996_mcu_mld_ap_reconf_event \*reconf = \(void \*\)data->data;\n//m; s/\n\s*ieee80211_links_removed\(vif, le16_to_cpu\(reconf->link_bitmap\)\);\n/\n/s' "$build_dir/mt7996/mcu.c"
perl -0pi -e 's@static inline void\nmt7996_get_merged_ttlm\(struct ieee80211_vif \*vif,\n\s*struct ieee80211_neg_ttlm \*merged_ttlm\)\n\{.*?\n\}@static inline void\nmt7996_get_merged_ttlm(struct ieee80211_vif *vif,\n\t\t       struct ieee80211_neg_ttlm *merged_ttlm)\n{\n\tu16 map = vif->valid_links;\n\tint tid;\n\n\tfor (tid = 0; tid < IEEE80211_TTLM_NUM_TIDS; tid++) {\n\t\tmerged_ttlm->downlink[tid] = map;\n\t\tmerged_ttlm->uplink[tid] = map;\n\t}\n}@s' "$build_dir/mt7996/mt7996.h"
perl -0pi -e 's@static inline void mt7996_set_pse_drop\(struct mt7996_dev \*dev, bool enable\)\n\{.*?\n\}@static inline void mt7996_set_pse_drop(struct mt7996_dev *dev, bool enable)\n{\n#ifdef CONFIG_NET_MEDIATEK_SOC_WED\n\tif (!is_mt7996(&dev->mt76) || !mtk_wed_device_active(&dev->mt76.mmio.wed))\n\t\treturn;\n\n\t/* backport WED PPE API is incompatible */\n#endif /* CONFIG_NET_MEDIATEK_SOC_WED */\n}@s' "$build_dir/mt7996/mt7996.h"
