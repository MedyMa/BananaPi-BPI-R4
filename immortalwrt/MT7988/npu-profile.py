#!/usr/bin/env python3
"""Select and verify one MT7988 NPU firmware backend before compilation."""

import argparse
from pathlib import Path
import re


MODES = ("hnat", "flow", "dpdk")
BACKENDS = ("TUNNEL", "MCAST", "FLOW", "DPDK")
PROTOCOLS = ("GRE", "GRETAP", "PPP", "PPP_SOCKET", "L2TP", "L2TP_V2", "PPTP", "VXLAN")
PACKAGES = ("nf_hnat", "flow", "dpdk", "mcast")
VENDOR_WIFI = {"kmod-mediatek_hnat", "kmod-warp", "kmod-mt_wifi7",
               "kmod-mt_wifi_cmn", "kmod-mt_hwifi"}


def read_config(path):
    values = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"(CONFIG_[^= ]+)=(.*)", line)
        disabled = re.fullmatch(r"# (CONFIG_[^ ]+) is not set", line)
        if match:
            values[match[1]] = match[2]
        elif disabled:
            values[disabled[1]] = "n"
    return values


def selection(mode):
    values = {"CONFIG_MTK_NPU_24_10_" + name + "_BACKEND": "n" for name in BACKENDS}
    values.update({"CONFIG_MTK_NPU_" + name: "n" for name in PROTOCOLS})
    values.update({"CONFIG_MTK_NPU_" + name: "n" for name in ("HNAT", "FLOW", "DPDK", "MCAST")})
    for name in PACKAGES:
        for suffix in ("", "-autoload"):
            values["CONFIG_PACKAGE_kmod-npu-" + name + suffix] = "n"
    for name in ("kmod-npu", "kmod-npu-autoload", "npu-rebb-fw", "mtk-tops-accounting"):
        values["CONFIG_PACKAGE_" + name] = "y"
    for name in ("MTK_NPU", "MTK_NPU_SUPPORT", "MTK_NPU_REBB_SUPPORT"):
        values["CONFIG_" + name] = "y"
    values["CONFIG_MTK_NPU_24_10_OTHER_BACKENDS"] = "n"
    for name in ("ADPT_FWD", "L4S", "RATE_LIMIT"):
        values["CONFIG_MTK_NPU_" + name] = "n"
    enabled = ("TUNNEL", "MCAST") if mode == "hnat" else (mode.upper(),)
    adapters = ("nf_hnat", "mcast") if mode == "hnat" else (mode,)
    protocols = PROTOCOLS if mode == "hnat" else (
        ("PPP", "PPP_SOCKET", "L2TP", "L2TP_V2", "PPTP") if mode == "flow" else ())
    for name in enabled:
        values["CONFIG_MTK_NPU_24_10_" + name + "_BACKEND"] = "y"
    for name in adapters:
        for suffix in ("", "-autoload"):
            values["CONFIG_PACKAGE_kmod-npu-" + name + suffix] = "y"
    for name in protocols:
        values["CONFIG_MTK_NPU_" + name] = "y"
    values["CONFIG_MTK_NPU_" + ("HNAT" if mode == "hnat" else mode.upper())] = "y"
    if mode == "hnat":
        values["CONFIG_MTK_NPU_MCAST"] = "y"
        values["CONFIG_PACKAGE_kmod-mediatek_hnat"] = "y"
    elif mode == "flow":
        values["CONFIG_PACKAGE_kmod-nft-offload"] = "y"
        values["CONFIG_PACKAGE_firewall4"] = "y"
        for name in VENDOR_WIFI:
            values["CONFIG_PACKAGE_" + name] = "n"
    return values


def blocked_dependents(metadata, values):
    """Drop vendor WiFi consumers as well as the HNAT provider in FLOW images."""
    dependencies = {}
    for block in re.split(r"(?m)(?=^Package: )", metadata.read_text()):
        name = re.match(r"Package: ([^\n]+)", block)
        depends = re.search(r"(?m)^Depends: (.*)$", block)
        if name and depends:
            dependencies[name[1]] = depends[1].split()
    blocked = set(VENDOR_WIFI)
    while True:
        added = set()
        for package, tokens in dependencies.items():
            for token in tokens:
                token = token.lstrip("+")
                if token.startswith("@"):
                    continue
                condition, separator, dependency = token.rpartition(":")
                if separator:
                    condition = condition.strip("()")
                    if values.get("CONFIG_" + condition, "n") not in ("y", "m"):
                        continue
                else:
                    dependency = token
                if dependency in blocked:
                    added.add(package)
        added -= blocked
        if not added:
            break
        blocked.update(added)
        for name in added:
            values["CONFIG_PACKAGE_" + name] = "n"
    if "kmod-npu" in blocked:
        raise ValueError("FLOW metadata still requires vendor HNAT through the NPU core")
    return blocked


def apply(config, metadata, mode):
    current = read_config(config)
    changes = selection(mode)
    if mode == "flow":
        values = dict(current, **changes)
        blocked = blocked_dependents(metadata, values)
        changes.update({"CONFIG_PACKAGE_" + name: "n" for name in blocked})
        removed = sorted(name for name in blocked if current.get("CONFIG_PACKAGE_" + name) in ("y", "m"))
        print("FLOW wired profile disables vendor HNAT/WiFi packages: " + ", ".join(removed))
    elif mode == "dpdk":
        # Use the standard capacity unless the caller already selected 128 entries.
        small = current.get("CONFIG_MTK_NPU_DPDK_MAC_FILTER_NUM_128") == "y"
        changes["CONFIG_MTK_NPU_DPDK_MAC_FILTER_NUM_128"] = "y" if small else "n"
        changes["CONFIG_MTK_NPU_DPDK_MAC_FILTER_NUM_1024"] = "n" if small else "y"
    lines = []
    for line in config.read_text().splitlines():
        key = re.match(r"(?:# )?(CONFIG_[^= ]+)(?:=| is not set$)", line)
        if not key or key[1] not in changes:
            lines.append(line)
    for key, value in sorted(changes.items()):
        lines.append(key + "=" + value if value != "n" else "# " + key + " is not set")
    config.write_text("\n".join(lines) + "\n")
    print("Selected NPU build mode: " + mode)


def check(config, mode):
    current = read_config(config)
    expected = selection(mode)
    errors = [key + ": expected " + value + ", got " + current.get(key, "n")
              for key, value in expected.items() if current.get(key, "n") != value]
    if mode == "flow":
        errors.extend(name + " must be disabled" for name in VENDOR_WIFI
                      if current.get("CONFIG_PACKAGE_" + name, "n") != "n")
    elif mode == "dpdk" and current.get("CONFIG_MTK_NPU_DPDK_MAC_FILTER_NUM") not in ("128", "1024"):
        errors.append("DPDK MAC-filter capacity must resolve to 128 or 1024")
    if errors:
        raise ValueError("NPU mode rejected after defconfig:\n" + "\n".join(errors))
    print("Verified resolved NPU build mode: " + mode)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("apply", "check"))
    parser.add_argument("--mode", choices=MODES, required=True)
    parser.add_argument("--config", type=Path, default=Path(".config"))
    parser.add_argument("--metadata", type=Path, default=Path("tmp/.packageinfo"))
    args = parser.parse_args()
    values = read_config(args.config)
    required = ("CONFIG_TARGET_mediatek", "CONFIG_TARGET_mediatek_filogic_a73",
                "CONFIG_TARGET_mediatek_filogic_a73_DEVICE_bananapi_bpi-r4")
    if any(values.get(name) != "y" for name in required):
        raise ValueError("NPU firmware profiles require the standard BPI-R4 filogic_a73 target")
    if args.action == "apply":
        apply(args.config, args.metadata, args.mode)
    else:
        check(args.config, args.mode)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
