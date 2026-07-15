/* HNAT compat — symbols from MTK patches not applied by plaintext quilt */
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

/* From 999-hnat-11: skb headroom copy function pointer */
#ifndef mtk_skb_headroom_copy
#define mtk_skb_headroom_copy		mtk_hnat_skb_headroom_copy
#endif

#endif /* __HNAT_COMPAT_H */
