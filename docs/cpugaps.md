# TG68K CPU Gaps vs Mac II ROM Requirements

Comparison of instructions/features found in the Mac II NoMMU ROM disassembly against
what the TG68K core (cpu=2'b11, 68020 mode) actually implements.

## Instruction Gaps

### RTM (Return from Module) / CALLM (Call Module)
- **Present in ROM disassembly:** Yes (likely data misinterpreted as code by objdump)
- **TG68K status:** Not implemented — listed as "to do" in kernel comments. Traps as illegal instruction.
- **Risk:** Very low. Motorola removed RTM/CALLM from the 68030 and later. No Mac software uses these. Almost certainly data regions that objdump tried to disassemble.

### PMMU (68851) Instructions
- **Instructions:** PBBS, PBSS, PBWS, PMOVE, PRESTORE, PSAVE, PTESTW
- **Present in ROM disassembly:** Yes (residual dead code or data)
- **TG68K status:** Not implemented — cpID=0 is explicitly trapped as line-F exception.
- **Risk:** None. This is the "NoMMU" ROM variant; MMU code paths are stripped. These are data remnants.

## Bus Signal Gaps

### HALT
- **Real 68020:** Active-low bidirectional pin. As input: pauses the processor. As output: signals double bus fault. HALT+BERR together triggers bus retry.
- **TG68K status:** No HALT pin at all. Double bus faults are handled internally but not signaled externally.
- **Impact:** No bus retry mechanism. Not needed for Mac II without MMU (retry is used for page fault handling).

### DSACK[1:0] (Dynamic Bus Sizing)
- **Real 68020:** Replaces DTACK. Two-bit response from devices indicating port width (8/16/32-bit). CPU auto-sizes transfers.
- **TG68K status:** Not implemented. Bus wrapper uses 68000-style single `dtack_n` with 16-bit data bus. The kernel splits 32-bit accesses into two 16-bit bus cycles internally.
- **Impact:** No 32-bit bus transfers. All accesses go through 16-bit bus. Functionally correct but slower for 32-bit-capable devices (e.g., NuBus could benefit from 32-bit transfers).

### SIZ[1:0] (Transfer Size Output)
- **Real 68020:** Output indicating the size of the current bus transfer (byte/word/3-byte/long).
- **TG68K status:** Not implemented. UDS/LDS (68000-style) are used instead to indicate byte lane selection.
- **Impact:** External devices cannot distinguish transfer sizes beyond byte/word. Not an issue since the bus is 16-bit anyway.

## BERR (Bus Error) — Partial

- **TG68K status:** Implemented — takes bus error exception (vector $08) with correct stack frame for 68000 and 68010/020 modes.
- **Gap:** No retry support. Real 68020 can retry the faulted cycle when HALT is asserted with BERR. TG68K always takes the exception.
- **Impact:** Adequate for Mac II without MMU. BERR is used for unmapped address detection, not page fault retry.

## Summary

| Feature | Status | Impact |
|---------|--------|--------|
| All 68000 base instructions | Fully implemented | None |
| All 68020 extensions (bitfield, CAS, long MUL/DIV, MOVEC, MOVES, EXTB, PACK/UNPK, RTD, TRAPcc, etc.) | Fully implemented | None |
| FPU (MC68881) instructions | Coprocessor protocol implemented; arithmetic via external core | None |
| RTM/CALLM | Not implemented | None (not used by any Mac software) |
| PMMU instructions | Not implemented | None (NoMMU ROM) |
| HALT | Not implemented | No bus retry (not needed without MMU) |
| DSACK/SIZ | Not implemented | 16-bit bus only (functionally correct, minor perf cost) |
| BERR | Implemented (no retry) | Adequate for Mac II |
