#!/usr/bin/env python3
"""
Decode ISSP capture text into per-signal time series, then summarize.

Probe layout (matches rtl/debug_probes.sv):
  probe 0 (CP0_):  [31:8]=cpuAddr[23:0], [7]=cpuAS_n, [6]=cpuRW,
                   [5]=cpuUDS_n, [4]=cpuLDS_n, [3]=cpuDTACK_n,
                   [2]=video_en, [1:0]=0
  probe 1 (DATA):  [31:16]=memoryDataOut, [15:0]=arb_mac_dout
  probe 2 (MAC_):  [31:8]=arb_mac_addr[23:0], [7]=arb_mac_we, [6]=arb_mac_oe,
                   [5]=grant_video, [4]=video_clean, [3]=mac_stall, [2:0]=0
  probe 3 (VID_):  [31:8]=arb_vram_addr[23:0], [7]=arb_vram_rd,
                   [6]=arb_vram_wr, [5]=arb_vram_ready, [4:2]=vram_state,
                   [1:0]=0
  probe 4 (SDRA):  [31:16]=sdram_out, [15:12]=mac_idle_cnt, [11:4]=cpuAddr[31:24], [3:0]=0
"""

import re
import sys
from collections import Counter


def parse(path):
    """Returns list[dict[probe_idx, int]] -- one dict per sample."""
    samples = []
    cur = None
    for line in open(path):
        m = re.match(r"------ Sample (\d+) ------", line)
        if m:
            if cur is not None:
                samples.append(cur)
            cur = {}
            continue
        m = re.match(r"\s*probe (\d+) \(([^\)]+)\): (\S+)", line)
        if m and cur is not None:
            idx = int(m.group(1))
            val_str = m.group(3).strip()
            # Tcl returns binary string like 00010110... or 0x...
            if val_str.startswith("0x"):
                v = int(val_str, 16)
            else:
                try:
                    v = int(val_str, 2)
                except ValueError:
                    try:
                        v = int(val_str, 16)
                    except ValueError:
                        v = -1
            cur[idx] = v
    if cur is not None:
        samples.append(cur)
    return samples


def decode(samples):
    series = {k: [] for k in [
        "cpuAddr", "cpuAS_n", "cpuRW", "cpuUDS_n", "cpuLDS_n",
        "cpuDTACK_n", "video_en",
        "memoryDataOut", "arb_mac_dout",
        "arb_mac_addr", "arb_mac_we", "arb_mac_oe",
        "grant_video", "video_clean", "mac_stall",
        "arb_vram_addr", "arb_vram_rd", "arb_vram_wr",
        "arb_vram_ready", "vram_state",
        "sdram_out", "mac_idle_cnt",
    ]}
    for s in samples:
        p0 = s.get(0, 0)
        series["cpuAddr"].append((p0 >> 8) & 0xFFFFFF)
        series["cpuAS_n"].append((p0 >> 7) & 1)
        series["cpuRW"].append((p0 >> 6) & 1)
        series["cpuUDS_n"].append((p0 >> 5) & 1)
        series["cpuLDS_n"].append((p0 >> 4) & 1)
        series["cpuDTACK_n"].append((p0 >> 3) & 1)
        series["video_en"].append((p0 >> 2) & 1)
        p1 = s.get(1, 0)
        series["memoryDataOut"].append((p1 >> 16) & 0xFFFF)
        series["arb_mac_dout"].append(p1 & 0xFFFF)
        p2 = s.get(2, 0)
        series["arb_mac_addr"].append((p2 >> 8) & 0xFFFFFF)
        series["arb_mac_we"].append((p2 >> 7) & 1)
        series["arb_mac_oe"].append((p2 >> 6) & 1)
        series["grant_video"].append((p2 >> 5) & 1)
        series["video_clean"].append((p2 >> 4) & 1)
        series["mac_stall"].append((p2 >> 3) & 1)
        p3 = s.get(3, 0)
        series["arb_vram_addr"].append((p3 >> 8) & 0xFFFFFF)
        series["arb_vram_rd"].append((p3 >> 7) & 1)
        series["arb_vram_wr"].append((p3 >> 6) & 1)
        series["arb_vram_ready"].append((p3 >> 5) & 1)
        series["vram_state"].append((p3 >> 2) & 7)
        p4 = s.get(4, 0)
        series["sdram_out"].append((p4 >> 16) & 0xFFFF)
        series["mac_idle_cnt"].append((p4 >> 12) & 0xF)
        cpu_addr_hi = (p4 >> 4) & 0xFF
        # Stitch full PC from probe 0's [23:0] and probe 4's [31:24]
        series["cpuAddr"][-1] = (cpu_addr_hi << 24) | series["cpuAddr"][-1]
    return series


def summarize(series, name="capture"):
    out = []
    n = len(series["cpuAddr"])
    out.append("=" * 70)
    out.append(f"Capture: {name}  ({n} samples)")
    out.append("=" * 70)

    def histo(key, top=8):
        c = Counter(series[key])
        items = c.most_common(top)
        return ", ".join(f"{v:#x}={n}" for v, n in items)

    def is_changing(key):
        return len(set(series[key])) > 1

    def fraction(key, val):
        n = len(series[key])
        if n == 0:
            return 0.0
        return sum(1 for x in series[key] if x == val) / n

    out.append(f"video_en:        {dict(Counter(series['video_en']))}  (1 = card enabled)")
    out.append(f"cpuAddr range:   {min(series['cpuAddr']):#x} .. {max(series['cpuAddr']):#x}, distinct={len(set(series['cpuAddr']))}")
    out.append(f"cpuAddr top vals: {histo('cpuAddr')}")
    out.append(f"_cpuAS=0 (active): {fraction('cpuAS_n', 0)*100:.1f}%")
    out.append(f"_cpuDTACK=0 (ack): {fraction('cpuDTACK_n', 0)*100:.1f}%")
    out.append(f"arb_mac_we=1:    {fraction('arb_mac_we', 1)*100:.1f}%")
    out.append(f"arb_mac_oe=1:    {fraction('arb_mac_oe', 1)*100:.1f}%")
    out.append(f"grant_video=1:   {fraction('grant_video', 1)*100:.1f}%")
    out.append(f"video_clean=1:   {fraction('video_clean', 1)*100:.1f}%")
    out.append(f"mac_stall=1:     {fraction('mac_stall', 1)*100:.1f}%")
    out.append(f"arb_vram_rd=1:   {fraction('arb_vram_rd', 1)*100:.1f}%")
    out.append(f"arb_vram_wr=1:   {fraction('arb_vram_wr', 1)*100:.1f}%")
    out.append(f"arb_vram_ready=1:{fraction('arb_vram_ready', 1)*100:.1f}%")
    out.append(f"vram_state dist: {dict(Counter(series['vram_state']))}")
    out.append(f"mac_idle_cnt:    avg={sum(series['mac_idle_cnt'])/n:.2f}, max={max(series['mac_idle_cnt'])}")
    out.append(f"arb_mac_addr top: {histo('arb_mac_addr')}")
    out.append(f"arb_vram_addr top: {histo('arb_vram_addr')}")
    out.append(f"sdram_out top:    {histo('sdram_out')}")

    # Heuristic interpretation
    out.append("")
    out.append("---- interpretation ----")
    if not is_changing("cpuAddr"):
        out.append("  CPU PC frozen — Mac CPU not advancing.")
    elif len(set(series["cpuAddr"])) < 5:
        out.append("  CPU stuck in a tight loop (few distinct addresses).")
    else:
        out.append(f"  CPU is running ({len(set(series['cpuAddr']))} distinct addrs across {n} JTAG samples).")
    if not any(series["video_en"]):
        out.append("  video_en NEVER set — Mac's slot driver hasn't enabled the card.")
    else:
        out.append("  video_en went high — slot driver did run.")
    rd_attempts = sum(series["arb_vram_rd"])
    rd_ready    = sum(series["arb_vram_ready"])
    if rd_attempts > 0:
        out.append(f"  vram_rd asserted in {rd_attempts}/{n} samples; ready in {rd_ready}/{n}. ")
    return "\n".join(out)


def main():
    if len(sys.argv) < 2:
        print("Usage: analyze_capture.py <probes.txt> [more.txt ...]")
        return 1
    for p in sys.argv[1:]:
        samples = parse(p)
        if not samples:
            print(f"{p}: no samples found")
            continue
        series = decode(samples)
        print(summarize(series, p))
    return 0


if __name__ == "__main__":
    sys.exit(main())
