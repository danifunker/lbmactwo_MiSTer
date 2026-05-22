# Debugging the LBMacTwo core on real MiSTer (DE10-Nano) hardware

This is the field guide for diagnosing the core **on real hardware** (as opposed
to the Verilator simulator). It covers the build/program/probe loop, the JTAG
in-system probes, SignalTap, the MiSTer web UI/Remote API for screenshots, ROM
loading quirks, and the sim-vs-hardware differences that cause "works in sim,
fails on hardware" bugs.

> If you are only running the Verilator sim, you do **not** need most of this —
> see `verilator/`. This document is specifically for the real FPGA.

---

## 0. TL;DR debugging loop

Most hardware bugs are invisible in sim. The loop is:

1. Form a hypothesis about what signal/state would confirm or refute the bug.
2. Add a **JTAG ISSP probe** (`rtl/dbg_min.sv`) that captures that state.
3. Build (`scripts/auto_recompile.sh`, ~35–65 min).
4. Program over JTAG (`quartus_pgm ... LBMacTwo.sof@2`).
5. Read the probes (`quartus_stp_tcl -t scripts/cpu_state.tcl`) and/or grab a
   screenshot via the web UI.
6. Iterate. **Remove probes whose question is answered** — the design is near
   the device's ALM limit and too many probes won't fit.

Builds are slow, so make each one count: add the *most diagnostic* probe(s),
and prefer read-only probes (they never change behavior, so you can bundle a
candidate fix + a confirming probe in one build).

---

## 1. Hardware / toolchain

- Board: **DE10-Nano**, Intel **Cyclone V 5CSEBA6U23I7**.
- Toolchain: **Quartus Prime 17.0.2 Lite** (`/c/intelFPGA_lite/17.0/quartus/bin64`).
- Project: `LBMacTwo.qpf` / `LBMacTwo.qsf` at the repo root.
- JTAG: USB-Blaster on the DE10-Nano shows up as cable **`DE-SoC [USB-1]`**.
  The JTAG chain has two devices: **`SOCVHPS` @1** (the HPS/ARM) and the
  **`5CSEBA6` FPGA @2**. The FPGA is **device 2**.
- Network: the MiSTer's Linux/HPS side runs the **Remote** web UI (see §6),
  reachable at `http://<mister-ip>:8182`.

Add the Quartus tools to PATH in a shell:

```bash
export PATH="/c/intelFPGA_lite/17.0/quartus/bin64:$PATH"
```

---

## 2. Building the bitstream

Use the helper, which waits for any in-progress compile, then runs a full flow:

```bash
bash scripts/auto_recompile.sh        # logs to output_files/auto_compile_*.log
# equivalent to: quartus_sh --flow compile LBMacTwo
```

Run it in the background (it takes 35–65 min) and check the log when done.

Outputs in `output_files/`:
- `LBMacTwo.sof` — for JTAG programming (volatile, RAM config).
- `LBMacTwo.rbf` — copy to the SD card root to boot the core normally.

**Verify success** before programming:

```bash
grep -E "Full Compilation|Error \(|Can't fit" output_files/auto_compile_*.log | tail
ls -la output_files/LBMacTwo.sof   # timestamp should be fresh
```

### Fit budget (important)
With the **lite** MC68881 FPU the design sits at roughly **80% ALMs**. Each JTAG
probe + its capture logic costs LUTs/registers. Adding too many probes triggers
`Error (11802): Can't fit design in device`. If a build fails to fit, **remove
probes whose questions are already answered** (see `rtl/dbg_min.sv`). Empirically
~19 `altsource_probe` instances is around the ceiling here.

> The **non-lite** FPU does **not** fit. Always keep `fpu_lite_g=true`
> (`packed_decimal_full_g=false`, divrem gated out). Missing FPU ops trap to
> software where the OS supports it.

### Timing closure caveat
The flow reports *"Design is not fully constrained for setup/hold"*. There are
unconstrained paths, so **behavior can change build-to-build** (different
fitting → different marginal-path timing). If a bug appears/disappears between
otherwise-identical builds, suspect a marginal timing path rather than a logic
change.

---

## 3. Programming over JTAG

Detect the chain first (optional sanity check):

```bash
quartus_pgm --list                    # lists "DE-SoC [USB-1]"
quartus_pgm -c 1 -a                   # auto-detect: SOCVHPS @1, 5CSEBA6 @2
```

Program the FPGA (**device 2** in the chain):

```bash
quartus_pgm -c 1 -m jtag -o "p;output_files/LBMacTwo.sof@2"
# expect: "Configuration succeeded -- 1 device(s) configured"
```

Programming reconfigures the FPGA and **restarts the core** (a fresh boot). The
HPS/Linux side keeps running. Disk image mounts come from the HPS — after a
JTAG reprogram you may need to confirm the SCSI image is still mounted.

---

## 4. JTAG In-System Sources & Probes (ISSP) — the primary live-debug tool

This is how we watch internal state on the running FPGA without rebuilding for
every question (probes are read at runtime over JTAG).

### How it's wired
- `rtl/dbg_min.sv` instantiates Altera **`altsource_probe`** megafunctions, one
  per 32-bit "window". Each has a 4-character `instance_id` (e.g. `"PADR"`).
- `dbg_min` is instantiated in `LBMacTwo.sv` (`dbg_min_inst`) and fed live core
  signals (cpuAddr, bus state, SCSI debug, video counters, ...).
- `scripts/cpu_state.tcl` reads every probe and pretty-prints it.

### Reading the probes
```bash
quartus_stp_tcl -t scripts/cpu_state.tcl
```
The script finds the `DE-SoC` cable and the `5CSE` device automatically, then
samples each probe a few times (so you can tell if the CPU is executing or
frozen).

### Adding a new probe
1. In `rtl/dbg_min.sv`, register the signal of interest onto `clk` (coherent
   snapshot), e.g.:
   ```verilog
   reg [31:0] my_r;
   always @(posedge clk) my_r <= { ...signals... };
   altsource_probe #(
       .instance_id ("PXYZ"), .probe_width(32),
       .source_width(1), .sld_auto_instance_index ("YES")
   ) cp_pxyz (.probe(my_r), .source(), .source_clk(clk), .source_ena(1'b1));
   ```
2. If the signal isn't already an input to `dbg_min`, add a port and wire it in
   the `dbg_min_inst` instantiation in `LBMacTwo.sv`. (Thread it up from
   sub-modules like `dataController_top`/`ncr5380`/the video card as needed.)
3. Add a decode block to `scripts/cpu_state.tcl` (look up the probe by
   `instance_id`, then format the bits).

### Probe techniques that work well here
- **Free-running counter** (e.g. `PACT` counts `_cpuAS` edges): if it stops
  advancing, the CPU is hung. Great first check.
- **Coherent snapshot**: latch related signals together on one `clk` edge so the
  decoded view is consistent.
- **Sticky/OR latches**: accumulate "did X ever happen" across the run (survives
  the event), e.g. "any unsupported SCSI opcode seen", "max phase reached".
- **Edge-triggered capture**: latch a full state snapshot at the rising edge of
  a rare event (e.g. capture the SCSI phase the instant a bus-reset count
  increments) so you see *context* of a transient.
- **Survive-reset latches**: deliberately omit a reset clause so a flag
  accumulates truth across the device's own reset/retry cycles.

### Current probe catalog (`dbg_min.sv` — may drift; check the file)
- `PADR` cpuAddr, `PSTA` packed bus/decoder state, `PACT` `_cpuAS` cycle counter.
- `PVID`/`PVFC` video: `video_en`, VRAM CPU-write count, scanout fetch count.
- `PSCS`/`PSC2..PSC7` SCSI: register reads, selection snapshot, phase, REQ/ACK
  handshake observations, bus-reset count, live NCR state.
- `PSCF` SCSI bus-reset context snapshot (phase/io at the reset edge).
- `PSCG`/`PSCH` HPS ioctl write counts per ROM index (verify ROMs load).
- `PSC6` last SCSI opcode per target.

Probes are added/removed as investigations open and close — don't assume this
list is current; read `rtl/dbg_min.sv` and `scripts/cpu_state.tcl`.

---

## 5. SignalTap II (waveform-level)

ISSP gives you *sampled values*; when you need *cycle-accurate waveforms*
(timing relationships, glitches, exact handshake sequences) use the **SignalTap
II Logic Analyzer**:
- Add a `.stp` file to the project (Tools → SignalTap), pick a sample clock,
  choose nodes, set a trigger condition, recompile.
- It instantiates an on-chip RAM buffer, so it costs **block RAM + fit budget**
  — be mindful given the ~80% ALM usage. Keep the sample depth and node count
  small.
- Good for: confirming a suspected race (e.g. SDRAM arbiter grant flipping
  mid-transaction), verifying DTACK/REQ/ACK timing, catching a one-shot glitch.
- ISSP is cheaper and usually enough; reach for SignalTap when you need the
  time axis.

---

## 6. MiSTer web UI / Remote API (screenshots & control)

The MiSTer **Remote** app (mrext) serves a web UI at `http://<mister-ip>:8182`
(here: `http://10.3.89.233:8182`). Use it to **see the actual video output** and
correlate it with the `PVID`/`PVFC` probes.

Screenshots (note the method — `/take` is **not** an API route; it returns the
single-page-app HTML):

```bash
# List screenshots (newest last when sorted by "modified"):
curl -s http://10.3.89.233:8182/api/screenshots

# TAKE a new screenshot (POST to the base endpoint):
curl -s -X POST http://10.3.89.233:8182/api/screenshots

# Fetch an image by its path (core/filename from the list):
curl -s -o shot.png http://10.3.89.233:8182/api/screenshots/LBMacTwo/<file>.png
```

Find the newest and download it in one go:

```bash
curl -s -X POST http://10.3.89.233:8182/api/screenshots >/dev/null
P=$(curl -s http://10.3.89.233:8182/api/screenshots \
    | python -c "import sys,json;d=json.load(sys.stdin);d.sort(key=lambda x:x['modified']);print(d[-1]['path'])")
curl -s -o shot.png "http://10.3.89.233:8182/api/screenshots/$P"
```

Then view `shot.png` (the Read tool renders images). Interpreting the screen:
- **Uniform checkerboard** = Mac 50% gray desktop dither (good — ROM drew it).
- **Shifting noise / solid-color streaks that change between captures** =
  video scanout reading VRAM **incoherently** from shared SDRAM (arbiter
  starvation / stale `vram_din_reg`), *not* a CLUT/addressing constant.
- **Happy Mac / "?" disk / Sad Mac** = boot-device stage; the Sad Mac code
  pinpoints the fault.

---

## 7. ROM loading on hardware (and the bake-in trick)

The core needs two ROMs, mapped by ioctl download index in `LBMacTwo.sv`:
- **index 0** = `boot0.rom` — Mac II 256K system ROM.
- **index 1** = `boot1.rom` — NuBus **Hi-Res (TFB/341-0660)** video card
  **declaration ROM** (8 KB). *Not* the 4 KB Toby `342-0008-a.bin` — that's a
  different card and the Slot Manager will reject it.

**GOTCHA (discovered the hard way):** the MiSTer firmware auto-loads only the
**single** primary ROM (index 0). There is no `.mra` here, so **`boot1.rom`
never reaches index 1** on hardware — the video card never gets its declaration
ROM, the Slot Manager can't initialize it, and you get **no video at all**
(`video_en=0`, zero VRAM writes, not even a gray screen). This is independent of
any disk/boot problem.

Confirm with the ioctl-count probe (`PSCG`/`PSCH`): on hardware you'll see
~131072 word-writes at index 0 and **0** at index 1.

**Fix:** bake the declaration ROM into the bitstream so the card is
self-contained (like real hardware, where the ROM lives on the card):
```verilog
// in rtl/nubus/nubus_video_highres.sv, on the rom[] block:
initial $readmemh("boot1.hex", rom);
```
Generate `boot1.hex` (4096 big-endian 16-bit words) at the repo root so Quartus
`$readmemh` resolves it:
```bash
xxd -p -c 2 releases/boot1.rom > boot1.hex
```
The ioctl download path still overwrites `rom[]` when a host *does* provide the
ROM (the Verilator sim), so sim behavior is unchanged.

---

## 8. Sim vs hardware — why "works in sim, fails on hardware"

The Verilator sim (`verilator/`) is ideal-timing and bypasses several real
subsystems. Bugs in those subsystems are **invisible in sim**:

| Subsystem        | Sim                              | Hardware                                    |
|------------------|----------------------------------|---------------------------------------------|
| Video VRAM       | private `sim_vram` (instant)     | shared **SDRAM via `sdram_arbiter`**        |
| Disk backend     | C++ model, instant delivery      | real **HPS** over the avalon bridge         |
| `sd_buff` packing| **big-endian** (`byte1<<8\|byte2`)| real HPS packs **little-endian**            |
| Timing           | instant, no contention           | real clocks, SDRAM contention, HPS latency  |
| FPU              | stubbed                          | real `mc68881_fpu_lite`                     |
| ROMs             | loaded directly via ioctl        | HPS loads index 0 only (see §7)             |

Concrete consequences proven this session:
- **SCSI disk byte order**: sim's model packs `sd_buff` big-endian to match the
  RTL; the real HPS is little-endian, so every disk byte-pair was swapped on
  hardware (block 0 read as `0x5245` 'RE' instead of `0x4552` 'ER'). Fixed with
  an `\`ifdef VERILATOR`-guarded byte-lane swap in `rtl/scsi.v` (sim untouched).
- **Video coherency**: sim's `sim_vram` never exercises the arbiter, so video
  scanout corruption (stale/garbage VRAM reads under Mac bus contention) only
  shows on hardware.
- **SDRAM read coherency (CPU)**: the shared SDRAM means a Mac read can latch the
  in-flight *video* word. Fixed by deferring `_cpuDTACK` until the arbiter's
  `mac_dout_valid` (synced to the SDRAM `clk8_en_p` slot). See `LBMacTwo.sv` and
  `sdram_arbiter.v`.

When something works in sim but not on hardware, **suspect these first**:
byte order, the arbiter/SDRAM coherency, HPS latency/timing, and ROM loading.

---

## 9. Recurring gotchas checklist

- **No video / gray screen never appears** → declaration ROM not loaded (§7) or
  video card not initialized; check `PVID` (`video_en`, VRAM write count).
- **Garbage/streaky/shifting video** → arbiter video-fetch coherency/starvation
  (`sdram_arbiter.v`); video needs guaranteed SDRAM slots, not just Mac-idle
  gaps. Mac is bus-active ~57% of boot.
- **CPU executes garbage / random BERR** → SDRAM read coherency; ensure
  `mac_dout_valid` gates DTACK for RAM/ROM reads.
- **Byte-swapped data** (disk, ROM lanes) → HPS WIDE packing is little-endian;
  NuBus declaration ROMs are single-byte-lane.
- **Build won't fit** → too many probes; trim `dbg_min.sv`.
- **Behavior changes between identical builds** → unconstrained timing path.
- **CPU frozen** → `PACT` counter stops; then `PADR`/`PSTA` snapshot shows the
  offending access.
- **`$readmemh` file not found** → put the `.hex` at the repo root (project dir),
  reference it by bare filename.

---

## 10. Quick command reference

```bash
export PATH="/c/intelFPGA_lite/17.0/quartus/bin64:$PATH"

bash scripts/auto_recompile.sh                              # build (~35-65 min)
quartus_pgm -c 1 -m jtag -o "p;output_files/LBMacTwo.sof@2" # program FPGA (dev 2)
quartus_stp_tcl -t scripts/cpu_state.tcl                    # read JTAG probes
curl -s -X POST http://10.3.89.233:8182/api/screenshots     # take screenshot
```
