# Handoff — supervisor cpu/fpu bench test #1 F-line trap on MiSTer

*2026-06-09, branch `fpu-cir-fixes` (off `boot-investigation` @ `6a51149`)*

## RESUME HERE (session cleared 2026-06-09 late)

A **first-trap data-capture probe build is IN FLIGHT** (kicked via
`scripts/auto_recompile.sh`, log `output_files/auto_compile_session_firsttrap.log`,
~20-40 min). The dbg_min/cpu_state.tcl probe changes are UNCOMMITTED in the
working tree (PFLO/PFLA/PFLF first-trap capture; PADP+PFLT disabled to stay at
19 probes). When you resume:

1. **Check the build finished:** `.compile_in_progress` gone, md5 of
   `output_files/LBMacTwo.rbf` CHANGED from `7077955b`, log says
   `Full Compilation was successful`. If it failed, fix dbg_min and rebuild.
2. **Commit the probe** (it builds clean): `git add rtl/dbg_min.sv
   scripts/cpu_state.tcl && git commit` on branch `fpu-cir-fixes`.
3. **Deploy via OSD** (NOT MGL):
   ```
   . scripts/local.env
   python tools/misterdeploy/launch_unstable_core.py --host "$MISTER_HOST" \
       --ssh-key "$MISTER_SSH_KEY" --port "$MISTER_HTTP_PORT" \
       --core LBMacTwo.rbf --push output_files/LBMacTwo.rbf
   ```
   The bench `.hda` auto-mounts (config/LBMacTwo.s0/.s1). Wait ~10s, then
   screenshot (Remote API) to confirm `Test 1 ... trap=1` is showing.
4. **Read the probe:** `bash scripts/read_probes.sh` → look at the
   `FIRST-TRAP: din=0x.... addr=0x.... ` line. Its classification (already
   printed by the tcl) tells you the next move:
   - `din=0x0000` => the Response read still hasn't landed when cp_idle_resp
     decodes on HW. The cp_read_resp_wait wait state advances before the real
     FPU DSACK. FIX: make cp_read_resp_wait HOLD until DSACK (loop on itself
     while the read is outstanding) instead of a fixed single cycle, OR gate
     the decode on a "response valid" condition. This is the leading theory.
   - `din=0x09xx / 0x96xx` (a real primitive) => cp_idle_resp ELSE is decoding
     a primitive it should handle — re-check the decode bits vs AN-947, the
     value tells you which branch is mis-matching.
   - `din=0xFxxx` => it's the cpID-decode trap (kernel ~3721/3726), a DIFFERENT
     bug — the FPU dialog isn't even the trap source; chase the F-line opcode
     dispatch instead.
   Also `addr`/`cpuFC` (PFLF line): FC=7 + addr~$0002xxxx => trap in the CIR
   dialog; FC=6 => trap during an instruction fetch.
5. **Fix → rebuild → redeploy → re-read.** Loop until the screenshot shows
   `ok=1`. Each HW build is ~20-40 min; `rm -rf db incremental_db` before each.

Everything below is the standing context.

---


## The mission (this is the loop)

Make the **supervisor cpu/fpu bench test #1 pass on the real MiSTer**:
the on-screen `Test 1 ... trap=1` must become `ok=1`. Then let the run
continue and confirm it counts up (`ok=` rising) without trapping.

Run the loop autonomously: **fix → build → deploy (OSD) → screenshot/probe
→ evaluate → repeat**, until hardware shows `ok=1`.

## What is solid (do NOT re-litigate)

1. **Operand-CIR 2-beat adapter** (`94f05a1`, in `LBMacTwo.sv`) — was
   missing after the FPU went long-word (2dfbafc). Engages correctly on
   HW: JTAG PADP probe shows clean 14→7 pairing, frame data reaches the
   Operand CIR. Keep it.
2. **cp_read_resp_wait** (`3c68a27`, in `TG68KdotC_Kernel.vhd`) — fixes a
   real combinational hazard: `cp_idle_resp` decoded combinational
   `data_in` before the Response-CIR read completed (saw `0x0000` → fell
   through to ELSE → `trap_1111`). Mirrors `cp_save_wait`. **Correct in
   shape, proven 8/8 in the Verilator UNIT bench, but does NOT clear the
   HW trap.** Keep it (harmless, just insufficient).
3. **Boot712.dsk** reaches "Welcome to Macintosh" with **no bomb** on the
   adapter builds (historical bomb is gone). Real progress.

## The core problem

The Verilator **unit** bench (`SingleStepTests/cpu_fpu`) is NOT a
faithful HW oracle. After I added a taken-trap detector
(`trap_1111 && trapmake`) it went from a false 8/8 to a true 0/8 pre-fix,
and the `cp_read_resp_wait` fix takes it back to 8/8 — but **real silicon
still shows `trap=1`** with byte-identical probes
(`FPU-FSM max=RESTORE_FRAME resp_prim=0x0900`, adapter 14/2/7). The unit
bench has idealized DSACK/bus timing; HW has the real FPU handshake +
SDRAM arbiter. The trap is HW-timing-specific.

## Strategy — CURRENT: iterate on hardware with maximal info

**2026-06-09 late update:** the full-system sim build (Path A below) was
taking too long (imgui + `--timing`, may have toolchain issues) and is NOT
worth blocking on. **Iterate directly on hardware.** First HW build in
flight: a first-trap data-capture probe (dbg_min, no kernel plumbing —
the kernel's `std_logic_unsigned` conflicts with `numeric_std`, so don't
try to export `micro_state` via a port without care):
- **PFLO** `[31:16]=cpu_din at the FIRST trap_1111 edge (sticky)`,
  `[15:0]=trap count`. The din value classifies the trap: `0x0000` =>
  Response read still not landed on HW (the cp_read_resp_wait wait state
  doesn't hold to DSACK on real timing); `0x09xx/0x96xx` => real Response
  primitive hit cp_idle_resp ELSE; `0xFxxx` => an F-line opcode fetch (the
  cpID-decode trap site, a DIFFERENT bug).
- **PFLA** `[31:0]=cpuAddr at first trap` ($0002xxxx+FC7=CIR, $40xxxxxx=ROM IF).
- **PFLF** `[31:16]=last_fpu_resp, [15:13]=cpuFC, [12]=cpuRW, [11:0]=addr[11:0]`.
- Disabled PADP + PFLT to stay under the ~19-20 JTAG ceiling.
Decode added to `scripts/cpu_state.tcl`. Read with `bash scripts/read_probes.sh`.

After reading: the din classification tells you which of the 4 trap_1111
sites fires and whether cp_read_resp_wait's capture works on HW. Fix
accordingly, rebuild, redeploy (OSD), re-read. Repeat.

### Path A (deferred): full-system Verilator sim
`verilator/` boots the actual SCSI `.hda` payload through the real bus +
arbiter — far closer to HW than the unit bench. Already prepped this
session (`41c9f05`): ported the Operand-CIR adapter into `verilator/sim.v`
and removed `USE_FPU_STUB` (real mc68881 always). Build was compiling at
handoff time (imgui is slow; use OSS-CAD verilator: `export
PATH=$HOME/oss-cad-suite/bin:$PATH`; apt verilator 5.020 rejects
`-Wno-ALWNEVER`).

Run it:
```
cd verilator
./obj_dir/Vemu --headless --no-memtest \
   --scsi0 /tmp/cpufputestbench.hda \
   --screenshot 1500,2000,2500 --stop-at-frame 2600
```
(`.hda` copy is at `/tmp/cpufputestbench.hda`; or extract the fixture
`SingleStepTests/preboot/supervisor_bench/fixtures/cpufputestbench.hda.zip`.
Screenshots land as `screenshot_frame_NNNN.png` in `verilator/`.) Also
extract `/Results.jsonl` from the `.hda` after (hfsutils `hmount` the HFS
partition at sector 96, `hcopy -r :Results.jsonl`).

- **If the full-system sim REPRODUCES `trap=1`** → it's the faithful
  oracle. Iterate the fix there (minutes/run, not 40-min HW builds), then
  do ONE HW build to confirm.
- **If it does NOT** (passes like the unit bench) → the trap is even more
  HW-specific. Go to Path B.

### Path B: data-capturing JTAG probe on HW
The current PFLO probe latches `last_fpu_resp` with a 1-cycle lag and only
catches the resting `0x0900`. Build a probe that latches `cpu_din` at the
EXACT `trap_1111` rising edge, **sticky-on-FIRST** (not last), plus the
micro_state and PC at that edge. That tells us the precise response value
and state the kernel trapped on, on real silicon. Then fix and rebuild.
~40 min/iteration — use only if Path A can't reproduce.

### Likely real causes to investigate (HW-specific)
- The real FPU's DSACK timing during the Response read differs from the
  bench, so `last_data_read` still latches stale/wrong data even with
  cp_read_resp_wait — i.e. the wait state needs to hold until DSACK, not
  a fixed cycle. Check `update_ld`/`nextpass` gating on the real DSACK.
- A SECOND trap_1111 site (kernel has 4: lines ~3721, 3726, 4717, 4964)
  firing — the PFLO/data-capture probe disambiguates which.
- Operand read path (FSAVE side) corrupting the saved frame so FRESTORE
  delivers garbage (PADP only counts writes, not read values).

## The loop mechanics

### Build
```
rm -rf db incremental_db output_files/.compile_in_progress   # force structural
bash scripts/auto_recompile.sh > output_files/auto_compile_session_X.log 2>&1 &
```
Watch the `.compile_in_progress` flag; ~20-40 min. **Verify md5 CHANGED**
(`output_files/LBMacTwo.rbf`) and `Full Compilation was successful`. If
you edited VHDL, the RBF picks it up (Quartus reads VHDL via
`rtl/tg68k/TG68K.qip`); regen the `.v` only for the Verilator benches
(`rtl/tg68k/convert_to_verilog.sh` under OSS-CAD path). **Never edit the
.qsf or any project file while a compile is in flight** — Quartus
rewrites the qsf at compile start and your edit races/corrupts it.

### Deploy + load via OSD (NOT MGL — user directive)
Use the OSD launcher (copied from MacLC_MiSTer):
```
. scripts/local.env
python tools/misterdeploy/launch_unstable_core.py \
    --host "$MISTER_HOST" --ssh-key "$MISTER_SSH_KEY" --port "$MISTER_HTTP_PORT" \
    --core LBMacTwo.rbf --push output_files/LBMacTwo.rbf
```
It scp's the rbf (md5-verified), reboots to a clean menu, reads the LIVE
menu via `POST /api/menu/view`, computes down*N/confirm keystrokes, and
sends them over `ws /api/ws`. The SCSI bench `.hda` auto-mounts (MiSTer
persists it via `config/LBMacTwo.s0`/`.s1` → `games/LBMacTwo/cpufpubench.hda`),
so the bench boots on core load — no disk nav needed. `--dry-run` previews
keystrokes. (`scripts/mister_ws.py` is the lower-level OSD key sender if
manual nav is ever needed; OSD rule = one `osd` at start, nav keys, no
closing press.)

### Observe
```
# Screenshot (Remote API; OSD overlay NOT captured):
curl -s -X POST http://$MISTER_HOST:8182/api/screenshots >/dev/null ; sleep 2
LATEST=$(ssh ... 'ls -t /media/fat/screenshots/LBMacTwo/*.png | head -1')
scp ... "root@$MISTER_HOST:$LATEST" scratch/...png   # then Read it
# JTAG probes (must NOT run during a Quartus compile — JTAG contends):
bash scripts/read_probes.sh   # decodes PADP/PFLO/PFST/FPU-FSM via cpu_state.tcl
```
Wait ~5-10 s after core load for the bench to run before screenshotting.

### Evaluate
Pass = screenshot shows `Test 1 ... ok=1` (was `trap=1`), and `ok=`
rises as the run continues. Read `/Results.jsonl` from the `.hda` for
exact per-test pass/fail if needed (hfsutils, as above).

## The bench

`cpufputestbench.hda` (fixture committed `8fb4068`, md5 `a21bcdd1`,
on MiSTer at `/media/fat/games/LBMacTwo/cpufpubench.hda`). Test #1 =
`FSAVE -(A7); FRESTORE (A7)+; FPU still usable, FP3=5 -> D1`. Source:
`SingleStepTests/preboot/supervisor_bench/` (payload + `recovery.s` VBR
handler that takes the trap and reports `vec=11`). If the corpus needs
regenerating, that's allowed — rebuild the `.hda` and re-push. The
real-Mac-II oracle for the FPU corpus is 1319/1320
(`SingleStepTests/results/cpu_fpu/hw_2026-06-05.jsonl`).

## Don't

- Don't use MGL to launch (user directive — use the OSD launcher).
- Don't edit project files (.qsf etc.) during a live Quartus compile.
- Don't trust the unit bench as the HW oracle — it's the thing that
  misled us. Use the full-system sim or HW probes.
- Don't delete the adapter or cp_read_resp_wait — both correct, both kept.

## Key files / memory

- `rtl/tg68k/TG68KdotC_Kernel.vhd` — `cp_idle_resp` (~4655), `cp_read_resp`
  + `cp_read_resp_wait` (~4647). 4 `trap_1111` sites.
- `LBMacTwo.sv` — Operand-CIR adapter (~489) + dbg_min instance.
- `rtl/dbg_min.sv` — PADP/PFLO/PFST probes; `scripts/cpu_state.tcl` decodes.
- `verilator/sim.v` — full-system top (adapter ported, stub removed).
- Memory: `project_operand_cir_adapter_fix.md` (full thread),
  `project_fpu_corpus_fixes.md`, `project_bug6_cpu_hypothesis.md`.
