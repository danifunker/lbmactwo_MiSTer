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
