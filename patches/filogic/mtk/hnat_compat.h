/* HNAT compat — symbols from MTK patches not applied by plaintext quilt.
 * This header is force-included via -include BEFORE any kernel #includes,
 * so we must use raw C types and forward declarations only. */
#ifndef __HNAT_COMPAT_H
#define __HNAT_COMPAT_H

/* From 999-hnat-02: PPE flow check interrupt */
#ifndef MTK_FE_INT_ENABLE2
#define MTK_FE_INT_ENABLE2		0x2C
#endif
#ifndef MTK_FE_INT2_PPE0_FLOW_CHK
#define MTK_FE_INT2_PPE0_FLOW_CHK	BIT(28)
#endif
#ifndef MTK_FE_INT2_PPE1_FLOW_CHK
#define MTK_FE_INT2_PPE1_FLOW_CHK	BIT(29)
#endif

/* From 999-hnat-11: skb headroom copy function pointer.
 * Tentative definition — linker merges across translation units. */
struct sk_buff;
int (*mtk_skb_headroom_copy)(struct sk_buff *new, struct sk_buff *old);

/* From 999-hnat-03/07/09: HW offload path descriptor.
 * Quilt skips hnat-*/net-* patches — provide the complete final struct.
 * Raw C types used because linux/types.h and linux/if_ether.h are not
 * yet included at the point this header is force-injected. */
struct net_device;
struct flow_offload_hw_path {
	struct net_device *dev;
	struct net_device *virt_dev;
	unsigned int flags;
	unsigned char eth_src[6];   /* ETH_ALEN */
	unsigned char eth_dest[6];
	unsigned short vlan_proto;
	unsigned short vlan_id;
	unsigned short pppoe_sid;
	unsigned short dsa_port;
};

/* From 999-net-03: tunnel device path type (bit position in flags) */
#ifndef DEV_PATH_TNL
#define DEV_PATH_TNL  8
#endif

#endif /* __HNAT_COMPAT_H */
