# Resume prompt — HMMU / 24-bit addressing fix

Paste the block below into a fresh Claude Code session in this repo.

---

I'm continuing work on the Mac II FPGA core boot. Previous session diagnosed the
root cause of the persistent BERR at PC=$40807580 (addr $A0830E80) that leaves
boot stuck in the SCC Channel A RR0 polling loop at $40803296.

## What we confirmed with instrumentation (see sim_main.cpp additions)

1. **Format $B BERR frame is pushed correctly** — 46 word writes = 92 bytes,
   `$B008` format/vector at SP+6, PC $40807582 at SP+2, valid SSW `$0115` at
   SP+10. Size and layout are fine.

2. **POST handler at $408020FA never RTEs.** It runs BSR/RTS subroutines, does
   `ADDQ.L #6, A7` at $408020F6, then `BRA.S $40802136`, eventually jumping
   through $40801DF8 → $40801EA0 → $40802E98 (ROM re-init path), which falls
   into the SCC poll at $40803296. Frame-size/format-$A vs $B is moot because
   there is no RTE.

3. **BERR vector install is not the bug.** Vector $8 ping-pongs between
   Slot Manager catcher ($4080E590) and POST handler ($408020FA). The
   pattern is `install SlotMgr → probe → restore POST`. At fault time
   (cycle 71,014,218) the POST handler is the legitimately-installed one.

4. **The "KMAP master pointer" is NOT corrupted after the fact.** The store
   at $4080788A writes `$A083_0E7C` to `(A2)=$00002B5C` *as the initial value*.
   Later reads see the same value. On real Mac II, `$A0` is master-pointer
   flag bits (locked=$80, resource=$20). In 24-bit mode the high byte is
   masked by the HMMU/AMU before hitting the bus.

5. **Root cause: our core has no HMMU/AMU.** TG68K runs permanent 32-bit mode,
   `$A083_0E7C + 4` → `$A083_0E80` → NuBus slot A (empty) → BERR. Real
   Mac II (`maciihmu`) translates `$A083_0E7C & 0xFFFFFF = $0083_0E7C` →
   RAM.

## Snow and MAME agree on the translation

- Snow: `core/src/mac/macii/bus.rs:587 amu_translate()`, gated by
  `amu_active = self.via2.ddrb.vfc3() && !self.via2.b_out.vfc3()`
  (VIA2 port B bit 3: DDR=1 AND output=0 → active).
- MAME: `src/devices/cpu/m68000/m68kmmu.h:1270 hmmu_translate_addr()`,
  gated by `macii.cpp:714`
  `set_hmmu_enable((data & 0x8) ? DISABLE : ENABLE_II)`
  (VIA2 PB3 low → enable; high → disable).

Translation (both byte-identical):
```
addr24 = addr & 0xFFFFFF
  0x00_0000..0x7F_FFFF  → addr24                                    RAM
  0x80_0000..0x8F_FFFF  → 0x40000000 | (addr24 & 0xFFFFF)           ROM
  0x90_xxxx..0xEF_xxxx  → 0xF0000000 | ((addr24 & 0xF00000)<<4)
                                     | (addr24 & 0xFFFFF)           NuBus
  0xF0_0000..0xFF_FFFF  → 0x50000000 | (addr24 & 0xFFFFF)           I/O
```

## MAME commit `afed5d3` review

Not relevant to the BERR. It's ASC rewrite, pseudovia rewrite, SCC
printer/modem port swap fix. Two side-findings for later:
- ASC rewrite could help the earlier `$40805E4A` ASC FIFO RAM-test blocker
  (see `docs/bootproblems.md:228-324`), **not** our current issue.
- SCC port swap (txda ↔ txdb) — quick sanity check on our wiring at some
  point, not blocking.

## Next steps (do these, in order)

### Step 1 — Verify VIA2 PB3 timing

Confirm the ROM sets VIA2 DDRB[3]=1 and ORB[3]=0 **before** cycle 71M (the
BERR cycle). If so, HMMU activates in time. If not, we'd need a different
default. Instrument `sim_main.cpp` to log every write to VIA2 ORB ($50F02000)
and DDRB ($50F02400) with PC and cycle, tracking bit 3 specifically.
Build and run with `cd verilator && ./obj_dir/Vemu --stop-at-frame 100 2>sim_err.log`
(flag is `--stop-at-frame N`, NOT `--frames`).

### Step 2 — Decide the splice point

Two candidates:
- `rtl/addrDecoder.v` — simplest, but decoder consumers also see `cpuAddr`
  elsewhere.
- `rtl/addrController_top.v` — single choke point where `cpuAddr` is
  defined for everything downstream. **Preferred.**

Expose VIA2 PB3 direction+output bits from `rtl/via6522.sv` (VIA2 instance
in `rtl/dataController_top.sv`) up to `addrController_top.v`.

### Step 3 — Draft the RTL

~15 lines of pure combinational:

```verilog
wire hmmu_24bit = via2_ddrb[3] & ~via2_orb[3];
function [31:0] hmmu_xlate(input [31:0] a);
    reg [23:0] lo;
    begin
        lo = a[23:0];
        casez (lo[23:20])
            4'b0???: hmmu_xlate = {8'h00, lo};                        // 0-7 RAM
            4'b1000: hmmu_xlate = {8'h40, lo};                        // 8   ROM
            4'b1001,4'b1010,4'b1011,
            4'b1100,4'b1101,4'b1110:
                     hmmu_xlate = {4'hF, lo[23:20], 4'h0, lo[19:0]};  // 9-E NuBus
            4'b1111: hmmu_xlate = {8'h50, lo};                        // F   I/O
        endcase
    end
endfunction
wire [31:0] bus_addr = hmmu_24bit ? hmmu_xlate(cpu_addr) : cpu_addr;
```

Feed `bus_addr` to the decoder, RAM/ROM selects, NuBus arbiter, peripheral
dispatch. Do NOT translate addresses that are only internal to the CPU
(e.g. CPU's own instruction fetch PC register). Apply at the bus boundary.

### Step 4 — Regression check

Keep the CPU in 32-bit mode for now (nothing toggles `cpu=2'b11`). After
HMMU is wired:
- Expect the BERR at $40807580 / $A0830E80 to vanish.
- Expect the SCC poll loop at $40803296 to not be reached via the
  POST-handler restart path.
- Run `./obj_dir/Vemu --stop-at-frame 400 2>sim_err.log` and check
  `grep "SCC POLL LOOP" sim_err.log | wc -l` — should be 0 or very few.
- Watch for new blockers — likely the ASC FIFO test at $40805E4A next,
  already documented.

## Key files

- `rtl/addrController_top.v` — splice point candidate
- `rtl/addrDecoder.v` — has existing `$80→$00` mirror (line ~173)
- `rtl/dataController_top.sv` — VIA2 instantiation
- `rtl/via6522.sv` — need to expose DDRB/ORB or their bit 3
- `verilator/sim_main.cpp` — instrumentation (BERR frame tracer, KMAP
  watchpoint, VEC2_WR tracker) already added
- `docs/bootproblems.md` — full boot timeline
- `/Users/dani/repos/snow/core/src/mac/macii/bus.rs` — reference (AMU)
- `/Users/dani/repos/mame/src/devices/cpu/m68000/m68kmmu.h` — reference (HMMU)

## Don't forget

- Target machine is `maciihmu` (Mac II without 68851), NOT plain `macii`.
- Run sim from `verilator/` so ROM paths resolve.
- Use `--stop-at-frame N`, not `--frames N`.
- Run sim once to `sim_err.log`, then grep — don't re-run per query.
- `$display` in Verilog goes to **stdout**, not stderr — split redirects.
- Present findings and wait for user approval before editing Snow repo.

Start with Step 1: verify VIA2 PB3 write timing in the current
`sim_err.log` (or re-run if needed) and report back before touching RTL.
