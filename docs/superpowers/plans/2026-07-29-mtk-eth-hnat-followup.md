# MediaTek HNAT Ethernet Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add and validate an ordered follow-up patch for the QDMA SG PPE destination and per-packet PPD state.

**Architecture:** Keep the GSO fix in `999-9101` and install a separate `99961` patch after the source tree's `9996`. Validate behavior by replaying the real patch sequence against the Linux 6.6.94 plus MediaTek overlay fixture.

**Tech Stack:** OpenWrt kernel patches, POSIX shell, Git, Linux kernel C.

## Global Constraints

- Do not modify `immortalwrt-mt798x-6.6`.
- The new patch must modify only `drivers/net/ethernet/mediatek/mtk_eth_soc.c`.
- The installed order must be `9996`, `99961`, `9997`.
- Code Review must complete before push.

---

### Task 1: Add the ordered kernel follow-up

**Files:**
- Create: `patches/filogic/mtwifi-6.6/99961-hnat-mtk-eth-sg-ppd-fix.patch`
- Modify: `immortalwrt/diy-part3.sh`
- Test: `D:/Code/Luci-app/.tmp/kernel-9101-replay-20260729-123633`

**Interfaces:**
- Consumes: the `ext_ppe` and `sent_ppd` code introduced by `9996-ext-hnat.patch`
- Produces: a kernel patch installed as `99961-hnat-mtk-eth-sg-ppd-fix.patch`

- [ ] **Step 1: Verify the ordering test fails before implementation**

Reset the replay fixture to its `pre-9101` commit, apply `999-9101`, and
attempt to apply the not-yet-created follow-up before `9996`.

Expected: FAIL because the follow-up file or its `9996` context is absent.

- [ ] **Step 2: Generate the minimal follow-up patch**

Apply the unmodified `9996` to the replay fixture, edit only
`mtk_eth_soc.c`, and generate a patch containing:

```c
bool sent_ppd = false;
```

inside the RX `while` loop, plus an explicit PPE destination guard for
each scatter-gather descriptor.

- [ ] **Step 3: Install the patch from DIY3**

Add a second `install_kernel_patch` call:

```sh
install_kernel_patch \
    "${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/patches/filogic/mtwifi-6.6/99961-hnat-mtk-eth-sg-ppd-fix.patch" \
    "99961-hnat-mtk-eth-sg-ppd-fix.patch"
```

- [ ] **Step 4: Run the green patch-chain test**

Apply, in order:

```text
999-9101
9996
99961
9997
9998
9999
99999
```

Expected: every patch applies successfully.

- [ ] **Step 5: Verify final invariants**

Check that the replayed source contains exactly one `sent_ppd`
declaration inside the RX loop, and inspect the SG descriptor path for
the PPE destination assignment.

- [ ] **Step 6: Run static checks and Code Review**

Run:

```powershell
git diff --check
bash -n immortalwrt/diy-part3.sh
git apply --check patches/filogic/mtwifi-6.6/99961-hnat-mtk-eth-sg-ppd-fix.patch
```

Review correctness, ordering, ownership, error paths, portability, and
patch maintainability. Fix every finding and rerun all checks.

- [ ] **Step 7: Commit and push**

Commit only the design, plan, new patch, and DIY3 reference using the
configured `medyma` GitHub identity, then push `main`.

