# MediaTek HNAT Ethernet Follow-up Patch Design

## Goal

Add a standalone kernel patch that is applied after
`9996-ext-hnat.patch` and contains the two `mtk_eth_soc.c` corrections
removed from the earlier `999-9101` patch.

## Scope

- Keep `999-9101-hnat-cpu-wifi-fix.patch` limited to CPU-to-WiFi GSO
  segmentation.
- Do not modify `immortalwrt-mt798x-6.6`.
- Add the follow-up patch to the BananaPi-BPI-R4 build repository.
- Install it from `immortalwrt/diy-part3.sh`.
- Use a destination filename that sorts after `9996-ext-hnat.patch` and
  before `9997-drop-hash.patch`.

## Patch behavior

The follow-up patch modifies only
`drivers/net/ethernet/mediatek/mtk_eth_soc.c`:

1. Preserve the PPE destination for every descriptor emitted for a QDMA
   scatter-gather packet.
2. Move `sent_ppd` into the RX packet loop and use a boolean initialized
   to `false`, so PPD state cannot leak into a later packet handled by the
   same NAPI poll.

## Ordering

The installed patch name is
`9996-zz-hnat-mtk-eth-sg-ppd-fix.patch`. The required order is:

```text
999-9101-hnat-cpu-wifi-fix.patch
9996-ext-hnat.patch
9996-zz-hnat-mtk-eth-sg-ppd-fix.patch
9997-drop-hash.patch
9998-dsa.patch
```

## Verification

1. Demonstrate that applying the follow-up before `9996` fails.
2. Apply `999-9101`, the unmodified `9996`, the new follow-up, and the
   remaining HNAT patches in production order.
3. Confirm that the final source contains one loop-local `sent_ppd`
   declaration and that every intended SG descriptor retains the PPE
   destination.
4. Run whitespace and shell syntax checks.
5. Perform Code Review and fix all findings before committing or pushing.
