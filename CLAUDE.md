# CLAUDE.md

Project guidance for Claude Code working on the **LBMacTwo** (Macintosh II)
MiSTer FPGA core. See also `AGENTS.md` for repo conventions.

## If you are debugging on a real MiSTer / DE10-Nano FPGA

**Read [`docs/MISTER_HARDWARE_DEBUGGING.md`](docs/MISTER_HARDWARE_DEBUGGING.md) first.**

It is the field guide for hardware bring-up and covers:
- the build → program → probe loop (Quartus `auto_recompile.sh`, `quartus_pgm`);
- **JTAG In-System Probes** (`rtl/dbg_min.sv` + `scripts/cpu_state.tcl`) — how to
  add/read probes, and the fit budget that limits how many you can have;
- **SignalTap** for waveform-level debugging;
- the **MiSTer web UI / Remote API** for taking and fetching screenshots
  (`POST http://<ip>:8182/api/screenshots`);
- **ROM loading** quirks (only index 0 auto-loads; bake `boot1.rom` into the
  bitstream via `$readmemh`);
- the **sim-vs-hardware differences** (SDRAM arbiter, HPS `sd_buff` byte order,
  timing, FPU) that cause "works in sim, fails on hardware" bugs.

Hardware builds take 35–65 minutes, so plan probes carefully and run builds in
the background.

## Simulation

The Verilator simulator lives in `verilator/`. It is ideal-timing and bypasses
the SDRAM arbiter, real HPS, and FPU — so it will not reproduce coherency/timing
bugs that only appear on hardware. Treat sim and hardware as complementary.

**Scaler/aspect path is NOT simulated** (`verilator/sim.v` has no
`video_freak`): the OSD "Original" aspect once shipped as 256:171 — a Mac
Plus 512×342 leftover that overflowed integer scaling on 5:4 panels (blank
screen at 1280×1024) — now fixed to true 4:3 in `LBMacTwo.sv`. Gate any
change to the `video_freak` ARX/ARY wiring with `scripts/aspect_check.py`
(offline model of `sys/video_freak.sv`; exits non-zero on failure).

## WSL configuration (Verilator / GHDL / Yosys)

On Windows hosts the repo lives on the NTFS side and all sim/conversion
tooling runs inside **WSL Ubuntu-24.04**, not Windows. The repo path inside
WSL is the standard `/mnt/<drive>/<path>` translation of the Windows
checkout location.

**Two toolchains coexist; pick by task.**

1. **OSS-CAD-Suite** (install into your WSL home, e.g.
   `$HOME/oss-cad-suite/bin`) — required for **VHDL→Verilog conversion**
   via `ghdl synth`. The apt-installed `ghdl-llvm` is broken on Ubuntu-24.04
   (missing `libLLVM-18.so.18.1` soname); do **not** use it. Tested
   versions: GHDL 7.0.0-dev, Verilator 5.049, Yosys 0.64+308.
2. **System apt packages** — Verilator 5.020 from `apt`. Sufficient to build
   and run the bench once the `.v` files exist. No OSS-CAD path needed.

**Regenerate Verilog after a VHDL edit** (TG68 or mc68881) — run from the
repo root:

```bash
# TG68 kernel/ALU/Pack — after editing rtl/tg68k/*.vhd
wsl -d Ubuntu-24.04 -e bash -lc '
  export PATH=$HOME/oss-cad-suite/bin:$PATH
  cd "$(pwd)/rtl/tg68k" && ./convert_to_verilog.sh
'

# mc68881 FPU — after editing rtl/mc68881/vhdl/*.vhd
wsl -d Ubuntu-24.04 -e bash -lc '
  export PATH=$HOME/oss-cad-suite/bin:$PATH
  cd "$(pwd)/rtl/mc68881" && ./convert_to_verilog.sh
'
```

**Build + run the SingleStepTests cpu_fpu bench** (default `wsl` distro is
fine once .v files are regenerated):

```bash
wsl -e bash -lc 'cd SingleStepTests/cpu_fpu && make clean >/dev/null 2>&1 && make'
wsl -e bash -lc 'cd SingleStepTests/cpu_fpu && ./obj_dir/Vcpu_fpu_tests cpu_fpu_full_corpus.json | tail -1'
```

**Gotchas:**
- Quartus reads VHDL directly via `rtl/tg68k/TG68K.qip`, so an RBF rebuild
  does NOT need the `.v` regenerated — only the Verilator bench does.
- GHDL version drift: OSS-CAD-Suite ghdl emits a different `.v` than the
  apt-installed ghdl that produced the pre-generated file in git. The diff
  surfaces ~70 spurious FSQRT/FCMP+FDB/FSAVE Verilator failures that are
  **synth artifacts** (the FPU's own truth-table comes out wrong for some
  condition codes), not VHDL bugs. Hardware is the authoritative oracle —
  do not chase these in Verilator.
- `wsl ... 2>&1` may print a benign mount warning on some hosts; ignore.

## Scratch directory (`scratch/`)

The `scratch/` directory at the repo root is **gitignored** and is the
home for everything that is in-progress, ephemeral, or session-specific
and that does **not** belong in the repo. Put things here, not at the
repo root or under `docs/`:

- Hardware-debug captures (`scratch/hang_capture/<timestamp>/` — that's
  where `scripts/deploy_test_floppy.sh` writes by default).
- Ad-hoc screenshots from interactive testing (`scratch/*.png`).
- Session-specific notes, TODO lists, and resume prompts (e.g.
  `scratch/fresh_session_prompt.md`).
- Memory dumps, sample JTAG output files, ROM trace logs — anything
  generated during an investigation that doesn't need to be reviewed
  or merged.

What does NOT go in `scratch/`:

- RTL changes, scripts, and tests — those go in their normal homes.
- Documents intended for review or future reference — those go in
  `docs/`.
- Build artifacts handled by other gitignore entries (`output_files/`,
  `db/`, `incremental_db/`, etc.).

When an investigation produces something worth keeping (a writeup, a
new script, a permanent capture), move it out of `scratch/` into the
appropriate tracked location and add it to git. Until then it stays
in `scratch/`, where `git status` stays quiet.
