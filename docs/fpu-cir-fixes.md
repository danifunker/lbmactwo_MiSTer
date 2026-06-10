# Handoff — supervisor cpu/fpu bench test #1: post-FRESTORE wild PC

*2026-06-10, branch `fpu-cir-fixes` (off `boot-investigation` @ `6a51149`).*
*Supersedes `docs/handoff_fpu_respread_trap_2026-06-09.md` — that handoff's
leading theory (`din=0x0000` / `cp_read_resp_wait`) is DISPROVEN below.*

## TL;DR

The mission is unchanged: make the on-screen **supervisor CPU/FPU bench
test #1** go from `trap=1` to `ok=1` on the real MiSTer, then let the run
count up (`ok=` rising) without trapping.

**What this session proved:** test #1's trap is **NOT** in the FPU dialog.
The FSAVE/FRESTORE CIR dialog completes cleanly. The trap is a **wild /
corrupted PC after FRESTORE** — the CPU runs away into I/O space
(`0x50FFFFA2`, FC=6 supervisor instruction fetch) and takes an F-line trap
there. This is the exact "stale opcode → runaway branch" failure the kernel's
`cp_op_pc` / `cp_mem_refetch` machinery is meant to prevent, but it is
insufficient on real HW bus timing (classic sim-passes / HW-fails).

A **cp_op_pc bisection probe is built and committed** (RBF md5 `f1b8e023`) to
decide *which* of two fixes is needed — but the loop is **PAUSED here**: we are
switching to a different approach before deploying/reading it. The RBF is ready
to deploy whenever we return to this line. See "RESUME HERE".

---

## RESUME HERE

The **cp_op_pc bisection probe is BUILT and COMMITTED** — RBF
`output_files/LBMacTwo.rbf` md5 `f1b8e023` (clean structural build, 0 errors).
The 5 probe files (`LBMacTwo.sv`, `rtl/dbg_min.sv`,
`rtl/tg68k/TG68KdotC_Kernel.vhd`, `rtl/tg68k/tg68k.v`, `scripts/cpu_state.tcl`)
are committed on `fpu-cir-fixes`. The loop was paused here to try a different
approach; the RBF is ready to deploy. To pick the bisection back up:

1. **(Build already done — `f1b8e023`.)** Only rebuild if you changed RTL: always
   `rm -rf db incremental_db` first (incremental fitter crashes with `Fatal
   Error: Access Violation at 0x0`), then `bash scripts/auto_recompile.sh`,
   verify md5 CHANGED + `Full Compilation was successful`.
2. **(Probe already committed.)**
3. **Deploy** (see "Deploy" — DO NOT trust the OSD launcher; use
   `POST /api/launch`). Push the RBF (scp + md5), launch, verify
   `coreRunning:LBMacTwo`.
4. **Screenshot** (~18 s after load) to confirm `Test 1 ... trap=1` is
   showing (Remote API; OSD overlay not captured but the bench renders to the
   framebuffer so it IS captured).
5. **Read the probe:** `bash scripts/read_probes.sh` → the
   **`POST-FRESTORE BISECT: cp_op_pc = 0x........`** line decides the fix:
   - **`cp_op_pc` is a sane low-RAM address** (the instruction right after
     FRESTORE) ⇒ the restore PC is RIGHT, so `cp_mem_refetch` latched a
     **stale opcode** on HW bus latency. FIX: make `cp_mem_refetch_wait`
     hold until the fetch's DSACK instead of being a fixed single cycle —
     mirror the `cp_read_resp_wait` shape. (`TG68KdotC_Kernel.vhd:4941`.)
   - **`cp_op_pc` is garbage** (not RAM/ROM) ⇒ the **restore PC itself is
     wrong**. FIX: the `cp_op_pc` capture (`cp_op_pc <= tmp_TG68_PC` at
     `cp_write_opw`, `TG68KdotC_Kernel.vhd:890`) is off on HW — tmp_TG68_PC
     isn't where the comment claims at that moment.
   - Also read **`NONROM-TRAP: opcode=0x.... wild_addr=0x........`**
     (PFLO/PFLA) and **`nonROM_trap_cnt`** (PFLF[11:0]).
6. **Fix → rebuild → redeploy → re-read.** Loop until the screenshot shows
   `ok=1` and the count rises.

---

## The diagnostic chain (how we got here — don't repeat it)

1. **First-trap probe (committed `9dfff5c`, build `c0c399bd`)** sticky-latched
   `cpu_din`/`addr`/`fc` at the first `trap_1111`. It read
   **`din=0xF008 addr=0x40003B06 FC=6`** every run.
2. That is the **Mac II ROM's OWN benign FPU self-probe** — disasm of
   `releases/boot0.rom` at ROM offset `0x3AF8` shows the ROM installs a
   temporary vec-`$2C` (F-line, vector 11) handler, deliberately executes the
   cpID=0 F-line opcode `0xF008` at `0x40003B06`, and CATCHES ITS OWN TRAP.
   It fires on every boot and is correct/benign. The sticky-FIRST capture was
   masking the real fault. (Memory: `reference_rom_fpu_selfprobe_redherring`.)
3. **Refined probe to skip ROM-region traps (committed `625107a`, build
   `d7fc9097`)** → first NON-ROM trap = **`addr=0x50FFFFA2 FC=6`**. That is a
   supervisor INSTRUCTION FETCH from I/O space ⇒ a **wild PC**.
   `nonROM_trap_cnt=2`, `last_fpu_resp=0x0900`.
4. **The FPU dialog is fine.** `cp_idle_resp` correctly decodes the resting
   `0x0900` as Null-DONE (`TG68KdotC_Kernel.vhd:4713`), `exc_seen=0`,
   `max_seen=RESTORE_FRAME`, `frame_seen=1`. So neither CIR-dialog trap site
   (4761 `cp_idle_resp` ELSE, 5008 `cp_except_trap`) fired. FSAVE/FRESTORE
   complete.
5. **Therefore the trap is post-FRESTORE control-flow corruption.** The
   kernel's own comment (`TG68KdotC_Kernel.vhd:405`) names it: a stale opcode
   word loaded after the dialog = "sndOPC half of FMOVE.L FP3,D1 = $6180 →
   BSR -128 runaway". The bench's "FPU still usable, FP3=5 -> D1" check is an
   FMOVE.L FP3,D1; if the post-FRESTORE PC restore feeds a stale word, the CPU
   runs away → wild PC → trap.

### The 4 `trap_1111` sites (for classifying any future capture)
- **3726** — F-line, cpID≠0, unrecognized type. FC=6 instruction fetch.
- **3731** — F-line, cpID=0. FC=6. *(= the benign ROM self-probe site.)*
- **4761** — `cp_idle_resp` ELSE, unimplemented Response primitive. FC=7, CIR.
- **5008** — `cp_except_trap`, FPU EXCEPTION primitive ACK then F-line. FC=7.

### The post-cpSAVE/cpRESTORE PC-restore machinery (the suspect)
- `cp_op_pc` / `cp_pc_restore_pending` declared `TG68KdotC_Kernel.vhd:405-412`.
- Captured at `cp_write_opw`: `cp_op_pc <= tmp_TG68_PC` (`:890`).
- `cp_idle_resp` Null-DONE routes cpRESTORE to `cp_mem_refetch` (`:4725`).
- PC mux force-loads `TG68_PC <= cp_op_pc` when next=`cp_mem_refetch` (`:1546`).
- `cp_mem_refetch` → `cp_mem_refetch_wait` → idle re-fetch (`:4941`). This
  2-state fixed sequence is the prime suspect for latching stale data on HW.

---

## Deploy — the OSD launcher is BROKEN; use `/api/launch`

The handoff directive was "use the OSD launcher, not MGL". **The OSD launcher
(`tools/misterdeploy/launch_unstable_core.py`) does not work** and cannot be
made reliable: MiSTer persists the menu cursor across reboot, so "down ×N from
assumed-top" lands on the wrong core (observed: it launched `Genesis`, then
`MiSTerLaggy`). I added cursor-homing (up*N) but subfolders also persist/wrap,
and there is NO cursor feedback anywhere (`/api/menu/view` has no cursor field;
screenshots don't capture the OSD). The WS only broadcasts
`coreRunning`/`gameRunning`/`indexStatus`.

**Working deploy** (bare-RBF core load — NOT an `.mgl`, so it honors "no MGL",
loads `boot0.rom`, and auto-mounts the bench `.hda`):
```bash
. scripts/local.env
LM=$(md5sum output_files/LBMacTwo.rbf | cut -d' ' -f1)
scp -q -i "$MISTER_SSH_KEY" -o StrictHostKeyChecking=no \
    output_files/LBMacTwo.rbf "root@$MISTER_HOST:/media/fat/_Unstable/LBMacTwo.rbf"
RM=$(ssh -i "$MISTER_SSH_KEY" -o StrictHostKeyChecking=no "root@$MISTER_HOST" \
    'md5sum /media/fat/_Unstable/LBMacTwo.rbf' | cut -d' ' -f1)
[ "$LM" = "$RM" ] && echo "MD5 OK" || echo "MD5 MISMATCH"
curl -s -X POST "http://$MISTER_HOST:$MISTER_HTTP_PORT/api/launch" \
    -H "Content-Type: application/json" -d '{"path":"_Unstable/LBMacTwo.rbf"}'
# verify: WS coreRunning should report LBMacTwo
```
`scripts/local.env`: `MISTER_HOST=192.168.99.143`, `MISTER_HTTP_PORT=8182`,
`MISTER_SSH_KEY=/c/Users/spam/.ssh/mister_only`.

## Observe
```bash
# screenshot (framebuffer; bench text IS captured):
curl -s -X POST http://$MISTER_HOST:8182/api/screenshots >/dev/null ; sleep 3
LATEST=$(ssh ... 'ls -t /media/fat/screenshots/LBMacTwo/*.png | head -1')
scp ... "root@$MISTER_HOST:$LATEST" scratch/shot.png   # then Read it
# JTAG probes (must NOT run during a Quartus compile — JTAG contends):
bash scripts/read_probes.sh
```

## Build
```bash
rm -rf db incremental_db output_files/.compile_in_progress   # ALWAYS structural
nohup bash scripts/auto_recompile.sh > output_files/auto_compile_session_X.log 2>&1 &
# watch output_files/.compile_in_progress; ~30-40 min.
# Verify md5 CHANGED + "Full Compilation was successful".
```
- Quartus reads the kernel **VHDL** (`rtl/tg68k/TG68K.qip`) + the hand-written
  wrapper `rtl/tg68k/tg68k.v`. An RBF rebuild does NOT need the generated
  `TG68KdotC_Kernel.v` regenerated — that's only for the Verilator benches.
  **Note:** this session added 2 dbg ports to the kernel entity + `tg68k.v`
  wrapper + `LBMacTwo.sv` + `dbg_min.sv`. The generated `TG68KdotC_Kernel.v`
  was NOT updated, so the Verilator full-system sim / unit bench will FAIL to
  elaborate until you regen it (`rtl/tg68k/convert_to_verilog.sh` under the
  OSS-CAD path) or guard the new ports. RBF is unaffected.
- Quartus rewrites the `.qsf` at compile start — never edit project files
  while a compile is in flight.
- Incremental builds intermittently crash the fitter (`Access Violation at
  0x0`). Always `rm -rf db incremental_db` first.

---

## The bisection probe (committed; RBF `f1b8e023`)

Exports two kernel-internal signals to JTAG through the hierarchy
(kernel VHDL → `tg68k.v` → `LBMacTwo.sv` → `dbg_min`), mirroring the existing
`dbg_fline_trap` path:
- `dbg_cp_op_pc` (= `cp_op_pc`, the restored PC) and `dbg_opcode` (= the
  `opcode` register).
- `dbg_min` latches both sticky at the first NON-ROM trap.
- **PFL2** = `cp_op_pc`. **PFLO[31:16]** repurposed from the useless lagged
  `din` to the registered trap `opcode`. PFLA = wild addr, PFLF as before.
- `cpu_state.tcl` prints `POST-FRESTORE BISECT:` with the verdict.
- 20 active JTAG probes after this (was 19; PADP+PFLT stay disabled). At the
  ceiling — do not add more without freeing one.

Type-safety note: exporting `cp_op_pc`/`opcode` is safe because both are
already `std_logic_vector` (no `numeric_std`/`std_logic_unsigned` conversion).
The earlier warning was specifically about exporting `micro_state` (an enum).

---

## What is SOLID — do not re-litigate

1. **Operand-CIR 2-beat adapter** (`94f05a1`, `LBMacTwo.sv`) — engages on HW
   (PADP clean 14→7). Keep.
2. **`cp_read_resp_wait`** (`3c68a27`) — registered-response decode in
   `cp_idle_resp`; correct in shape, 8/8 in the unit bench. Keep; it's not the
   HW trap cause but it's correct.
3. **The FPU CIR dialog completes** on HW (RESTORE_FRAME, 0x0900 Null-DONE,
   exc_seen=0). The trap is post-FRESTORE control flow, not the dialog.
4. **`0xF008 @ 0x40003B06` is the ROM's own benign FPU self-probe.** Ignore it.
5. **The unit bench (`SingleStepTests/cpu_fpu`) is NOT a faithful HW oracle**
   for this — idealized DSACK/bus timing hides the wild-PC bug.

---

## Commits this session (branch `fpu-cir-fixes`)
- `9dfff5c` — dbg_min first-trap sticky probe (caught the ROM red herring).
- `625107a` — dbg_min first NON-ROM trap probe (found the wild PC 0x50FFFFA2).
- *(latest)* — cp_op_pc bisection probe (5 files, RBF `f1b8e023`) + this
  handoff + the `tools/misterdeploy/` deploy tool. See `git log --oneline`.

## "Try something different" — alternative angles
- **Full-system Verilator sim** (`verilator/`, handoff Path A). Real bus +
  arbiter; may reproduce the wild PC for minutes-per-iteration vs 40-min HW
  builds. Adapter already ported, stub removed (`41c9f05`). **Caveat:** the
  generated `TG68KdotC_Kernel.v` now lacks this session's 2 new dbg ports — regen
  it or the sim won't build.
- **Fix the post-FRESTORE PC restore directly** without waiting for the
  bisection: the two candidate fixes are spelled out in RESUME HERE step 5.
  Highest-confidence single fix is making `cp_mem_refetch_wait` DSACK-gated.
- **Regenerate the corpus / bench** if test #1's instruction sequence is worth
  changing — but the wild PC reproduces the real HW bug, so keep it.
- **SingleStepTests trace** of the exact FSAVE/FRESTORE/FMOVE.L FP3,D1
  sequence to see the prefetch state the unit bench produces, then diff vs HW.

## Key files
- `rtl/tg68k/TG68KdotC_Kernel.vhd` — `cp_op_pc`/`cp_pc_restore_pending`
  (`:405`, `:890`, `:1546`); `cp_mem_refetch`/`_wait` (`:4941`); 4 trap sites
  (`:3726 :3731 :4761 :5008`); `cp_idle_resp` (`:4693`); new dbg exports
  (`:5414`).
- `rtl/tg68k/tg68k.v` — wrapper; new dbg ports + kernel inst connections.
- `LBMacTwo.sv` — tg68k_inst (`:721`), dbg ports/wires (`:755`), Operand-CIR
  adapter (~`:489`), dbg_min inst (~`:1410`).
- `rtl/dbg_min.sv` — trap capture + PFLO/PFLA/PFLF/PFL2 probes (~`:1389`).
- `scripts/cpu_state.tcl` — probe decode (`NONROM-TRAP`, `POST-FRESTORE
  BISECT`); `scripts/read_probes.sh` runs it.
- `releases/boot0.rom` / `boot0-nomemtest.rom` — the bench needs no-memtest;
  FPU self-probe at offset `0x3AF8`.

## Memory pointers
- `project_operand_cir_adapter_fix` — the full FPU-trap thread + this session's
  resume pointer + deploy gotcha.
- `reference_rom_fpu_selfprobe_redherring` — the 0xF008 red herring.
- `project_bug6_cpu_hypothesis` — the 4 trap_1111 sites.
