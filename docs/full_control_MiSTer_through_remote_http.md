# Controlling the MiSTer from this dev box (HTTP + SSH)

A fresh-context cheat sheet so the next session can resume LBMacTwo
hardware debugging without re-discovering everything.

## Personal/local config lives in `scripts/local.env`

The IP, SSH key path, Quartus install path, and HTTP port are all
local to whoever's debugging. They live in `scripts/local.env` — a
**gitignored** file. There's a template at `scripts/local.env.example`
with the variable names and what they mean.

The four variables every script + the docs below expect:

- `$MISTER_HOST` — hostname or IP of the MiSTer on the LAN.
- `$MISTER_SSH_KEY` — absolute path to the SSH private key whose
  public half is in `/media/fat/linux/authorized_keys` on the MiSTer.
- `$QUARTUS_BIN` — directory containing `quartus_stp_tcl`,
  `quartus_pgm`, etc. (the project builds against Quartus 17.0).
- `$MISTER_HTTP_PORT` — mrext's HTTP port (defaults to `8182`).

Source it once per shell:

```bash
. scripts/local.env                   # sets MISTER_HOST etc.
export PATH="$QUARTUS_BIN:$PATH"      # so quartus_stp_tcl is on PATH
```

`scripts/deploy_test_floppy.sh` sources it automatically; the helpers
below assume you've sourced it too (or that the env vars are exported
in your shell profile).

## HTTP API — what works, what doesn't

The Remote app's "API" is mostly HTML routes that serve the SPA. The
ones the React UI actually uses, that are useful to us:

| Method | Path | Body | What it does |
|---|---|---|---|
| GET  | `/api/sysinfo`                  | – | IP, hostname, version, disk free. JSON. |
| GET  | `/api/systems`                  | – | List of every system mrext knows. JSON. **LBMacTwo is NOT registered** — its system id is unknown to mrext. |
| GET  | `/api/screenshots`              | – | List of every saved screenshot. JSON sorted by `modified`. |
| POST | `/api/screenshots`              | – | **Take a new screenshot.** Returns nothing useful; poll the list to find it. |
| GET  | `/api/screenshots/<core>/<file>` | – | Download a screenshot PNG. |
| POST | `/api/launch`                   | `{"path":"_Unstable/LBMacTwo.rbf"}`   | Cold-load that file. Works for `.rbf` and `.mgl`; **fails for `.dsk`** ("unknown file type"). |
| GET  | `/api/games/search`             | `{"query":"...","system":"..."}`      | Useless for LBMacTwo (unknown system). |
| WS   | `/api/ws`                       | text frames | Keyboard / OSD navigation. See next section. |

Anything else (`/api/control`, `/api/keyboard`, `/api/menu`, etc.) just
serves the SPA HTML — they're SPA routes, not real endpoints.

### Common patterns

Cold-load the latest local RBF:
```bash
. scripts/local.env
ssh -i "$MISTER_SSH_KEY" root@"$MISTER_HOST" \
    "rm -f /media/fat/config/LBMacTwo.s0"          # forget any mounted images
scp -i "$MISTER_SSH_KEY" -q output_files/LBMacTwo.rbf \
    root@"$MISTER_HOST":/media/fat/_Unstable/LBMacTwo.rbf
curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"path":"_Unstable/LBMacTwo.rbf"}' \
    "http://$MISTER_HOST:$MISTER_HTTP_PORT/api/launch"
```

Take + fetch the newest screenshot in one shot:
```bash
. scripts/local.env
HTTP="http://$MISTER_HOST:$MISTER_HTTP_PORT"
curl -s -X POST "$HTTP/api/screenshots" >/dev/null
sleep 2
P=$(curl -s "$HTTP/api/screenshots" | \
    python -c "import sys,json;d=json.load(sys.stdin);d.sort(key=lambda x:x['modified']);print(d[-1]['path'])")
curl -s -o shot.png "$HTTP/api/screenshots/$P"
```

**Important caveat:** the MiSTer OSD overlay is **NOT** captured in
screenshots. The PNG returned is the raw core video output. If you
need to *see* the OSD state, you cannot — you have to rely on
on-screen state changes that happen *after* the OSD acts.

## WebSocket — keyboard, OSD, key names

Real-time keyboard + OSD control runs through
`ws://$MISTER_HOST:$MISTER_HTTP_PORT/api/ws` as plain text frames.

Message types the UI uses:

| Text frame | Effect |
|---|---|
| `kbd:<name>` | Send a NAMED key (see list below). |
| `kbdRaw:<code>` | Send a raw HID keycode press+release. |
| `kbdRawDown:<code>` | Just a key-down. |
| `kbdRawUp:<code>` | Just a key-up. |
| (server -> us) `coreRunning:<name>` | Currently loaded core. |
| (server -> us) `gameRunning:<path>` | Currently launched game/MGL/file. |
| (server -> us) `indexStatus:...` | Library index state. |

Named `kbd:` values (from `cmd/remote/control/control.go` upstream):
`up`, `down`, `left`, `right`,
`volume_up`, `volume_down`, `volume_mute`,
`menu`, `back`, `confirm`, `cancel`,
`osd`, `screenshot`, `raw_screenshot`,
`pair_bluetooth`, `change_background`,
`core_select`, `user`, `reset`,
`toggle_core_dates`, `console`, `exit_console`,
`computer_osd`.

The helper script `scripts/mister_ws.py` wraps the websocket. It
defaults `--host` and `--port` from `MISTER_HOST` /
`MISTER_HTTP_PORT`, so if you've sourced `scripts/local.env` you
don't need to pass them:

```bash
# Each positional arg is sent as "kbd:<arg>". "sleep:0.5" inserts a pause.
python scripts/mister_ws.py --delay 0.5 \
    osd sleep:1 confirm sleep:1 left sleep:0.4 down sleep:0.4 confirm
```

The websocket session is short-lived per invocation — drain the first
couple of server messages, send your keys, drain replies, exit.

## OSD navigation rules (LBMacTwo, user-confirmed)

These are the rules **the user explicitly gave** — follow them
literally, do not improvise:

1. **Press OSD ONCE at the start. NEVER twice.** The OSD does not need
   a closing `osd` press — after a mount/select the OSD closes itself.
   Pressing `osd` a second time *reopens* it, which is what previously
   landed me in trouble.
2. Default cursor when the OSD opens is on the first menu item
   ("Mount Pri Floppy").
3. File-picker layout: `..` is always at the top; first real file is
   one `down` away.
4. Inside the file picker: `left` returns the cursor to the top (the
   `..`), then `down` moves to the first file (alphabetically),
   `confirm` mounts.

**Canonical sequence to mount `Boot712.dsk` (the test image):**
```bash
python scripts/mister_ws.py --delay 0.5 \
    osd sleep:1 \
    confirm sleep:1 \
    left sleep:0.4 down sleep:0.4 confirm
```
After `confirm` the OSD closes itself; **do not** add a trailing
`osd`. The Mac immediately sees the disk and proceeds with the boot.

User scope discipline (from explicit instructions):
- **EITHER HDD or floppy mounted, never both.** Don't try to mount
  both as a "workaround"; that's not the test case.
- For floppy debugging, **only `Boot712.dsk`** is in scope. Disk605,
  Install71, etc. — the user has tried them, don't retest.
- MGL mounts work for `type="s" index="0"` (HDD) alone OR a single
  `type="f"` floppy, but mixing them is unreliable in our core.
  **Prefer OSD mounting** — it's the workflow the user uses and the
  user has validated it.

## Deploy + capture in one command

`scripts/deploy_test_floppy.sh` is the canonical "build is done, what
does it do?" runner. It sources `scripts/local.env` itself, so just:

```bash
bash scripts/deploy_test_floppy.sh
```

It does:
1. SCPs `output_files/LBMacTwo.rbf` to the MiSTer.
2. Clears `/media/fat/config/LBMacTwo.s0`.
3. Cold-loads the core via `/api/launch`.
4. Mounts Boot712.dsk via the canonical OSD sequence.
5. Waits 25 s, screenshots.
6. Three rounds of `quartus_stp_tcl -t scripts/cpu_state.tcl` with
   30 s gaps + screenshots between.
7. Writes everything to a fresh `docs/hang_capture/<timestamp>/`
   (the directory is gitignored — it's run-output, not source).

## JTAG probes (cpu_state.tcl)

`scripts/cpu_state.tcl` reads every ISSP probe present in the
bitstream and decodes it. The current probe set (after the overnight
debug session) includes the standard ones plus:

- **PFLP** — floppy byte stream: `byte_cnt`, `slot_miss_cnt` (both
  wrap-16). `slot_miss_cnt > 0` would mean SDRAM is starving the
  floppy slot timer. Tonight: always `0`.
- **PIWM** — IWM live state: `sdram_grants` (wrap-16),
  `readDataLatch[7]` (= "byte avail"), `staged` (= floppy has fresh
  byte queued), `armDelayHi` (post-motor-on arm-delay countdown).
- **PFLT** — floppy track + step: `driveTrack`, `driveSide`,
  `step_cnt`. Watching this confirms the Sony driver is actually
  seeking and reading — tonight it climbed 34 -> 62 then stopped.
- **PIOA** — IORB pointer: the first non-ROM bus address that
  follows an instruction fetch at `0x40006C36` (the IOWait poll
  `move.w $10(a0),d0`). That captures `a0+0x10`; the IORB itself
  is at `cap - 0x10`. Tonight: `$3A4` (Params) then `$21FF6`
  (System dynamic IORB).
- **PIOC** — IOWait iteration count (wrap-16). Tracks how aggressively
  the OS is spinning the IOWait poll loop.
- **PIR1** — writes to `$0000_03B4` (= Params.ioResult).
  `write_cnt` (wrap-16) + `last_value`. If `write_cnt` grows the
  driver IS completing I/Os; if it stays at 0 the I/O is wedged.

When adding more probes, the ALM/JTAG fit budget is tight. Disable
the least-relevant existing probe (PMSE is already disabled, PVID /
PVFC / PSC4-PSC7 / PSCF / PSLT / PSRR / PSRL too) before adding new
ones.

## Hardware build flow

Builds take **~22–25 min** on this box (the docs say 35–65; we're at
the fast end). Background-friendly:

```bash
bash scripts/auto_recompile.sh > /tmp/build.log 2>&1 &
# Watch for completion via the flag file
until [ ! -f output_files/.compile_in_progress ]; do sleep 60; done
md5sum output_files/LBMacTwo.rbf
```

`scripts/auto_recompile.sh` waits for any in-flight Quartus to exit
first, touches `output_files/.compile_in_progress` for the duration,
logs to `output_files/auto_compile_<timestamp>.log`. Successful
finish prints `Compile exit=0`. A **"Critical Warning (332148):
Timing requirements not met"** at the end is the *normal* current
state — the design is right at the device limit. The RBF still gets
written.

**Build mistakes that cost a full ~25-min cycle:**
- Bash `$3B4` inside a TCL format string — TCL reads it as a
  variable. Escape: `\$3B4`. (One iteration was burned on this.)
- Forgetting to wire a new dbg port through ALL of:
  `rtl/floppy.v` → `rtl/iwm.v` → `rtl/dataController_top.sv` →
  `LBMacTwo.sv` → `rtl/dbg_min.sv` (input list) → probe instance
  → `scripts/cpu_state.tcl` decoder. Every intermediate file
  needs touch.

## How the build/notify loop actually flows

When you kick off a build in background, you'll get FOUR kinds of
notifications:

1. **Launcher shell exit** (`Background command "Kick off build #N" completed`).
   This is the foreground shell exiting after `&` — **does NOT mean
   the build finished**. The quartus_sh process continues in
   background.
2. **Monitor events** for stage banners:
   - `Quartus Prime Shell was successful` appears TWICE — once for
     the startup `build_id.tcl` eval, once at the very end. Don't
     mistake the first one for completion.
   - `Quartus Prime Analysis & Synthesis was successful` (~5 min in)
   - `Quartus Prime Fitter was successful` (~17 min in)
   - `Quartus Prime Assembler was successful` (~20 min in)
   - `Critical Warning (332148): Timing requirements not met` (~22 min)
   - `Compile exit=0 at <date>` ← **this is the real end signal**
3. **`BUILD<N> DONE`** from the wait-task (polling `.compile_in_progress`
   flag).
4. **Monitor timeout** — if you left an old Monitor armed from an
   earlier build, it'll time out hours later. Ignore stale ones; the
   task id won't match the current build.

The pair (Monitor `Compile exit=0` + Wait task completion) is what
you should treat as "go".

## The Welcome hang investigation — TL;DR

The point of all the probes above is to investigate a specific known
hang. Status as of the overnight run (see
`docs/welcome_hang_overnight_findings.md` for full details):

- Mac boots from `Boot712.dsk` (via OSD-mount), chime plays, "Welcome
  to Macintosh" renders. Then no further visible change.
- **Floppy + IWM + Sony driver are NOT the bug.** byte_cnt grows,
  slot_miss=0, driveTrack steps cleanly 34 -> 62, step_cnt grows,
  ioResult is written 449 times in ~7 minutes.
- **Phase 1 (~7 min after Welcome):** the OS does ~225 disk I/Os on
  the Mac low-mem "Params" IORB at `$0000_03A4` and completes them
  cleanly. Sony driver is healthy. Then it transitions to a
  different IORB.
- **Phase 2 (HARD HALT):** OS is now polling an IORB at `$0002_1FF6`
  (in low-RAM, allocated by System file). driveTrack frozen at 22,
  step_cnt frozen at 596, byte_cnt frozen at 43316, no further
  ioResult writes to `$3B4`. CPU keeps executing but in some non-I/O
  loop.

Full handoff: `docs/welcome_hang_overnight_findings.md`. The earlier
hypothesis writeup is `docs/welcome_hang_floppy_2026-05-30.md`
(superseded — the IWM byte-stall theory it explored was disproved
by the probes; kept for historical context).

The OBVIOUS next probe is a **"dynamic IORB ioResult write watcher"**
— PIR1 only watches the fixed `$3B4`. The OS now writes ioResult at
*whatever* address `$21FF6` is. To know if the new IORB ever
completes, we need a probe that uses the address PIOA captured and
counts writes to it. That's a ~25 min build.

Probable culprits for the Phase-2 hang (none confirmed; please
verify with probes before guessing):

1. **SCSI Manager bus scan.** Throughout the hang the SCSI ICR is
   stuck at `out_en=1 SEL=1 data=0xA0` (host selecting ID5, no
   target). Our chip emits no IRQ for selection-timeout — the host
   has to poll out. If the timeout depends on something we get wrong
   (VIA timer cadence, instruction-cycle count under SDRAM stalls),
   the scan never returns.
2. **ASC Sound IRQ.** `asc_irq_cnt = 0` across every probe — the
   ASC chip has never asserted its FIFO refill IRQ. `rtl/asc.sv`
   only sets `asc_fifo_irq` when `asc_mode == 8'h01` (FIFO mode);
   if the Sound Manager polls `$50F14804` while in wavetable mode
   it sees 0 forever.
3. **AppleTalk init.** Boot712.dsk's System has AppleTalk. Previous
   work fixed XPRAM SPValid magic bytes; verify that's still right
   for this disk's System (see `docs/bootproblems.md`).
4. **A System INIT.** Boot712 has INITs in System Folder; one of
   them may poke hardware we don't emulate fully.

## Things that wasted time in the overnight run, don't repeat

- **Pressing `kbd:osd` twice.** Once at the start. Done. The OSD
  closes itself on a file-mount confirm.
- **Mounting `.dsk` via `/api/launch`.** Returns "unknown file type:
  .dsk" with HTTP 500. Use OSD or an MGL.
- **Mixing HDD + floppy mounts** to see if SCSI scan was the cause.
  The user said "this is a bad idea, it should boot without scsi
  drives mounted" — they're right; don't propose it.
- **Trying alternate boot disks** (Disk605.dsk, Install71.dsk).
  User has tried them; only Boot712.dsk is in scope.
- **Saturating 16-bit counters.** Use wrapping counters and compute
  deltas between samples instead.
- **`$3B4` in TCL `format` strings.** Escape `\$3B4`.
- **Treating the first "Quartus Prime Shell was successful" line as
  build completion.** That's the startup banner. Wait for
  `Compile exit=0`.
- **Misinterpreting a Monitor-event `kbd:osd` task notification as
  user input.** Notifications are not user replies.
- **Polling the build by hand.** Use Monitor + `run_in_background`
  with an `until` loop — don't sleep-poll.
- **Pretending you've found the bug because byte_cnt grows.** The
  Mac OS does 200+ healthy I/Os and STILL hangs at Welcome. Always
  check `write_cnt`/`last_value` for the IORB you're actually
  watching, and CHECK that PIOA hasn't moved to a new IORB.

## File map for the diagnostic infra

| File | Role |
|---|---|
| `LBMacTwo.sv` | Top — wires every dbg port up to `dbg_min`. |
| `rtl/floppy.v` | Adds `dbg_byte_cnt`, `dbg_miss_cnt`, `dbg_disk_image_data`, `dbg_drive_track`, `dbg_drive_side`, `dbg_step_cnt`. |
| `rtl/iwm.v` | Adds `dbg_dsk_ack_cnt`, `dbg_read_data_latch`, `dbg_arm_delay_high` + pass-through of floppy's outputs. |
| `rtl/dataController_top.sv` | Routes all of the above up to `LBMacTwo.sv`. |
| `rtl/dbg_min.sv` | The probe definitions: PFLP / PIWM / PFLT / PIOA / PIOC / PIR1. |
| `scripts/cpu_state.tcl` | Reads all probes via JTAG ISSP; decodes them human-readably. |
| `scripts/pc_histogram.tcl` | (Less useful; pc_histogram_long.tcl has been crashing — separate bug.) |
| `scripts/mister_ws.py` | WebSocket helper for `kbd:` commands. |
| `scripts/deploy_test_floppy.sh` | End-to-end deploy + capture. |
| `scripts/auto_recompile.sh` | Build orchestrator. |
| `scripts/local.env.example` | Template for personal/local config. |
| `scripts/local.env` | **Gitignored** — your actual MISTER_HOST etc. live here. |
| `docs/welcome_hang_overnight_findings.md` | THE overnight handoff. |
| `docs/hang_capture/<timestamp>/` | (gitignored) Local probe captures + screenshots from each run of `deploy_test_floppy.sh`. |
| `docs/MISTER_HARDWARE_DEBUGGING.md` | The pre-existing field guide. |

## One-shot resume recipe (after `/clear`)

```bash
# 0. Make sure scripts/local.env exists with your MISTER_HOST etc.
[ -r scripts/local.env ] || cp scripts/local.env.example scripts/local.env

# 1. Read the handoff
cat docs/welcome_hang_overnight_findings.md

# 2. Verify the MiSTer is reachable and identity is right
. scripts/local.env
curl -s "http://$MISTER_HOST:$MISTER_HTTP_PORT/api/sysinfo" | python -m json.tool
ssh -i "$MISTER_SSH_KEY" root@"$MISTER_HOST" "uname -a"

# 3. See the current state of the working tree
git status
git diff --stat

# 4. Run the canonical deploy + capture (uses CURRENT output_files/LBMacTwo.rbf)
bash scripts/deploy_test_floppy.sh

# 5. Look at the latest capture
ls -t docs/hang_capture/ 2>/dev/null | head -1
```

If the user asks for a new probe / fix:
- Pick which existing probe to disable (ALM budget tight).
- Wire through every file in the "File map" table above.
- Build (~25 min); watch `Compile exit=0`.
- Deploy with the canonical script; read the new capture.
