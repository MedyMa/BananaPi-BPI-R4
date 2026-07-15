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

/* From 999-hnat-11: skb headroom copy function pointer.
 * Tentative definition — linker merges across translation units. */
struct sk_buff;
int (*mtk_skb_headroom_copy)(struct sk_buff *new, struct sk_buff *old);

#endif /* __HNAT_COMPAT_H */
