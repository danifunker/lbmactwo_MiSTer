# New SCC Integration Analysis

## Overview

A new, more complete SCC (Zilog 8530) module was integrated into the core, replacing the old
minimal `scc.v` (now renamed to `sccold.v`). This document captures the integration work and
boot analysis performed with the new SCC.

## Integration Fixes

The new SCC renamed two internal signals that `verilator/sim_main.cpp` referenced for debug logging:

| Old signal (sccold.v) | New signal (scc.v) | Purpose |
|---|---|---|
| `tx_ip` | `tx_irq_pend_a` | TX interrupt pending (ch A) |
| `rx_wr_a_latch` | `rx_wr_a_r` | RX write registered flag (ch A) |

Both fixes are in `sim_main.cpp` lines ~441 and ~465.

### New SCC Port Differences

The new SCC adds ports not present in the old one:

- `rxd_b` — Channel B serial RX input (for external loopback testing)
- `txd_b_out` — Channel B serial TX output

The new SCC also instantiates external `txuart` and `rxuart` modules for actual UART
serialization on both channels, with internal loopback support.

## Boot Analysis with New SCC

### What Works

The system boots through the full startup test sequence:

1. **StartTest1** (ROM offset `0x2A14`): All hardware tests pass
2. **Loopback/burn-in check** (ROM offset `0x2A76`): VIA SV1/SV2 check correctly detects
   NO factory jumper (VIA port A reads `0x82`, bit 1 is set → no jumper). Bit 26 of d7
   is NOT set.
3. **Normal boot path** (ROM offset `0x009A`): ROM proceeds through InitVIA (`0x6F2`),
   InitSCC (`0x7B4`), InitIWM (`0x6AA`), InitSCSI (`0x66C`), WhichCPU (`0x532`),
   RAMTest (`0x2BBC`), and the full startup init sequence
4. **Vector copy** at `0x2B9A`: Confirmed by BERR_VEC writes at PC=`40802B9C`
5. **Normal boot jump** to `0x009A` (STARTINIT1): Confirmed — ROM reaches normal startup
6. **Dongle check** at cycle ~6.6M: ROM reads VIA port A at `0x2A7C`

### Where It Fails

**The ROM eventually enters the Test Manager (diagnostic serial console).**

- **BERR at cycle 79,843,960**: PC=`40806A0E`, accessing address `A082D72C` (FC=6).
  This is ROM offset `0x6A0E` where code dereferences a pointer chain: `move.l (a0),a0`
  then `btst #6,(a0)` — the dereferenced address `A082D72C` doesn't exist.
- **SCC poll loop entry**: cycle ~181,997,681
- **Test Manager SCC init** confirmed by SCC writes from PC `4080340E`/`40803412`
  (ROM offset `0x340E-3412`, the test manager's InitSCC routine at `0x33FA`)

The gap between the BERR (cycle 79M) and the test manager loop (cycle 181M) is ~100M cycles.
Something in this window causes the ExceptionHandler (`0x694`) → Error1Handler (`0x2C3C`) →
TMEntry1 (`0x2E96`) path.

### The Stuck Loop

The test manager main loop:

```
2EDC: lea     (PC,$6), a6       ; set return address
2EE0: jmp     (PC,$3B4)         ; call GetChar at $3296
2EE4: tst.w   d5                ; test result
2EE6: bmi.w   $320E             ; no char (d5=$8000) → Continue
...
320E: btst    #16, d7           ; "test mode" flag
3212: beq.s   $3284             ; if not set, skip to loop back
3214: btst    #22, d7           ; echo flag
...
3284: bra.w   $2EDC             ; loop back to GetChar
```

GetChar at `0x3296`:
```
3296: move.w  #$8000, d5        ; default = no char
329A: btst    #17, d7           ; SCC initialized?
329E: beq.s   $32FA             ; if not, exit
32A0: lea     $50F04000, a2     ; SCC base
32A6: btst    #0, (a2,2)        ; RR0 bit 0 = RX buffer full?
32AC: beq.s   $32FA             ; no char → exit
```

RR0 returns `0x2C` = `00101100`:
- Bit 0 = 0: No RX character available (loop continues)
- Bit 2 = 1: TX buffer empty
- Bit 3 = 1: DCD
- Bit 5 = 1: CTS

**This is not a hang — it's the test manager waiting for serial console input.**
The ROM entered diagnostic mode after a startup failure and is polling for commands
on channel A.

### Error1Handler Path (ROM offset `0x2C3C`)

```
2C3C: btst    #26, d7           ; SCC already initialized?
2C40: bne.s   $2C70             ; yes → skip init
2C42-2C68: ... initialize SCC for test manager ...
2C6C: bra.w   $2E96             ; → TMEntry1

2C70: bset    #16, d7           ; SET "test mode" bit
2C74: bset    #22, d7           ; SET "echo" bit
2C78: move.w  #12, d4           ; set timer
...
2C8C: bra.w   $2E96             ; → TMEntry1
```

Bit 16 (test mode) is set at `0x2C70` when bit 26 is already set (SCC was previously
initialized — meaning this is NOT the first time through Error1Handler).

## ROM Details

- **ROM file**: `releases/boot0.rom` (256KB, September 1987 Mac II ROM)
- **ROM base address**: `0x40800000` (32-bit mode)
- **NOT the same ROM** as the supermario source (which targets later universal ROMs)
- The test manager code is structurally similar to supermario's `USTTestMgr.a` but
  at different offsets and with older logic

### Key ROM Offset Map (our ROM)

| Offset | Function |
|---|---|
| `0x009A` | STARTINIT1 — normal boot entry after tests pass |
| `0x0532` | WhichCPU |
| `0x066C` | InitSCSI |
| `0x06AA` | InitIWM |
| `0x06F2` | InitVIA |
| `0x07B4` | InitSCC (normal boot) |
| `0x07D6`+ | WriteSCC helper |
| `0x2806` | Exception vector table base |
| `0x2A14` | StartTest1 — entry point, hardware tests |
| `0x2A76` | CheckLoopBack — VIA SV1/SV2 burn-in jumper check |
| `0x2BBC` | RAMTest |
| `0x2C3C` | Error1Handler — fatal error, enters test manager |
| `0x2CFE` | TestManager (trap entry) |
| `0x2E96` | TMEntry1 — test manager main entry |
| `0x2EDC` | Test manager main loop (GetChar polling) |
| `0x3296` | GetChar — read SCC ch A for serial input |
| `0x33CC` | OutChar — write SCC ch A for serial output |
| `0x33FA` | InitSCC (test manager version) |
| `0x343C` | SCC register init table (for test manager) |

### Supermario Cross-Reference

From supermario `USTStartUp.a`, the test manager is entered via:
- `Error1Handler` / `Error2Handler` in `USTPostProc.a` — after any fatal startup test failure
- `TMRestart` — from critical error handler
- `TMEntry1` — from board burn-in or `_TestManager` trap ($A06B)

The burn-in jumper check (supermario `CheckLoopBack`):
- Tests VIA port A SV1/SV2 pins for factory loopback connector
- On Mac II: clears SV1 (bit 0), reads SV2 (bit 1); if SV2 follows SV1, jumper present
- Our ROM does the same check at offset `0x2A76`, and it correctly finds NO jumper

## Old vs New SCC Comparison

Ran the sim with the old SCC (`sccold.v`) swapped back in for a direct comparison.

**Result: Identical behavior.** Both SCCs produce the same boot failure:

| Metric | Old SCC (`sccold.v`) | New SCC (`scc.v`) |
|---|---|---|
| SCC poll loop first entry | cycle 181,997,681 | cycle 181,997,681 |
| SCC poll loop last entry | cycle ~411,074,881 | cycle ~411,074,881 |
| Total poll loop iterations | 572,685 | 572,694 |
| Dongle check cycle | 6,620,017 | 6,620,017 |
| BERR at cycle 79M | same | same |
| Final state | stuck in GetChar loop | stuck in GetChar loop |

The old SCC output appeared to end with VIA ORA reads instead of SCC reads, but this
was misleading — the VIA reads are interleaved with SCC reads as part of the test
manager's `Continue` path (which checks VIA timer status between `GetChar` calls).
The old SCC simply has fewer `$display` debug statements, so the VIA reads were more
visible at the tail of the output. Both SCCs are stuck in the identical loop.

**Conclusion: The test manager entry is a pre-existing startup failure, not caused by
the SCC module.** The new SCC is safe to keep and provides better functionality
(dual-channel UART, loopback support, more complete register emulation).

## Next Steps

1. **Add trace window covering cycles ~70M-182M** to capture the exact failure path
   that leads to Error1Handler. The current trace windows miss this critical period.
2. **Investigate the BERR at cycle 79M**: PC=`40806A0E` accessing `A082D72C` — this
   may be the trigger. The address suggests a bad pointer dereference during driver
   or toolbox initialization.
3. **Identify the startup failure**: The ROM passes all hardware tests and enters the
   normal boot path at `0x009A`, but something between cycle ~14M (SCC init) and
   cycle ~181M (test manager entry) causes `Error1Handler` to be invoked. The
   exception handler at ROM offset `0x694` catches faults and jumps to `0x2C3C`.
