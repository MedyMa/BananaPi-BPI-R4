# BPI-R4 HNAT secondary WAN validation

The `1013` driver patch and `1014` device tree patch add an optional `mtketh-wan2`
device lookup for `sfp-wan`. The upstream WAN bridge patch already classifies
`sfp-wan` as WAN. The new lookup is used by external device fast learning and
MAP-E ping-pong paths; this patch does not configure dual-WAN routing.
These patches are not installed by default. Set
`HNAT_SECONDARY_WAN_EXPERIMENTAL=1` when running `diy-mtk.sh` only for an
experimental build.

The source-level test replays the HNAT patches in the given ImmortalWrt source
checkout, compiles selected **actual patched C functions** against small host
`net_device` stubs, and checks classification, both ifindex lookups, device
registration, release, reference counts and optional property validation.

On Linux, before running `diy-mtk.sh`:

```sh
python3 scripts/test-hnat-secondary-wan.py openwrt --cc gcc \
  --with-patch patches/filogic/25.12/1013-mtk-hnat-secondary-wan.patch
```

After running `diy-mtk.sh` with `HNAT_SECONDARY_WAN_EXPERIMENTAL=1`:

```sh
python3 scripts/test-hnat-secondary-wan.py openwrt --cc gcc
```

The test requires GNU `patch`, Python 3 and a C99 compiler. It does not compile
the kernel. The baseline without 1013 is expected to fail at the secondary WAN
ifindex lookup, which confirms the test detects the original gap.

Before using a firmware build, confirm that the full kernel patch set applies,
the BPI-R4 DTB contains `mtketh-wan2 = "sfp-wan"`, and HNAT probes. On the
device, test traffic through RJ45 `wan` and `sfp-wan` separately; check PPE
entries and byte counters, bridge membership, disconnect/reconnect and traffic
app interface totals. No router-side checks are claimed by this host test.
