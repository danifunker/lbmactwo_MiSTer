#!/usr/bin/env python3
"""Generate fsave_ea_corpus.json — FSAVE/FRESTORE memory-EA tests.

Covers the EA modes added by the Phase-A kernel fix (handoff item: the
MacsBug `FSAVE -$AF0(A5)` vec-11 wedge, docs/init_wedge_ltlk_scc_2026-06-11.md):
  (d16,An)  — the exact MacsBug shape, negative displacement
  (An)      — corpus test #6's mode, now with layout + An-preservation checks
  (xxx).W / (xxx).L
  (d16,PC)  — FRESTORE only
  -(An)/(An)+ regression
  NULL-frame FSAVE now writing the full 4-byte format long

Bench schema (sim_main.cpp): program bytes planted at $1000, run to STOP,
check D{result_reg} == expected. Frame layout is probed by MOVE.L'ing the
format long ($1F18_0000 for an 881 IDLE frame) out of the save buffer.

Run:  python3 gen_fsave_ea_corpus.py   (writes fsave_ea_corpus.json)
"""
import json

def hx(s: str) -> list[int]:
    s = s.replace(" ", "").replace("_", "")
    return [int(s[i:i+2], 16) for i in range(0, len(s), 2)]

IDLE_FMT = 0x1F180000  # 881 IDLE frame format long (version $1F, format $18)

tests = []

# T1 — MacsBug shape: FSAVE (d16,A5) with negative d16; format long lands at EA.
tests.append({
    "name": "FSAVE -$500(A5) IDLE frame: format long at EA -> D1",
    "program": hx("4BF8 2000"      # LEA ($2000).W,A5
                  "7005"           # MOVEQ #5,D0
                  "F200 4180"      # FMOVE.L D0,FP3   (non-null FPU state)
                  "F32D FB00"      # FSAVE -$500(A5)  (EA = $1B00)
                  "2238 1B00"      # MOVE.L ($1B00).W,D1
                  "4E72 2700"),    # STOP #$2700
    "result_reg": 1,
    "expected": IDLE_FMT - (1 << 32) if IDLE_FMT >= (1 << 31) else IDLE_FMT,
})

# T2 — MacsBug round-trip: FSAVE/FRESTORE (d16,A5); FPU usable after; IDLE
# restore does NOT reload FP regs (clobber survives).
tests.append({
    "name": "FSAVE/FRESTORE -$500(A5) round-trip; FP3 clobber 5->99 -> D1",
    "program": hx("4BF8 2000"      # LEA ($2000).W,A5
                  "7005"           # MOVEQ #5,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F32D FB00"      # FSAVE -$500(A5)
                  "7063"           # MOVEQ #99,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F36D FB00"      # FRESTORE -$500(A5)
                  "F201 6180"      # FMOVE.L FP3,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 99,
})

# T3 — control-mode EAs must NOT write back An.
tests.append({
    "name": "FSAVE/FRESTORE -$500(A5) leaves A5 intact -> D1=1",
    "program": hx("4BF8 2000"      # LEA ($2000).W,A5
                  "7005"           # MOVEQ #5,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F32D FB00"      # FSAVE -$500(A5)
                  "F36D FB00"      # FRESTORE -$500(A5)
                  "200D"           # MOVE.L A5,D0
                  "7200"           # MOVEQ #0,D1
                  "B0BC 0000 2000" # CMP.L #$2000,D0
                  "6602"           # BNE.S +2 (skip MOVEQ)
                  "7201"           # MOVEQ #1,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 1,
})

# T4 — (An) mode: frame at EA ascending (corpus #6's mode, layout-checked).
tests.append({
    "name": "FSAVE/FRESTORE (A0): format long at EA, A0 intact -> D1",
    "program": hx("41F8 1B00"      # LEA ($1B00).W,A0
                  "7007"           # MOVEQ #7,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F310"           # FSAVE (A0)
                  "F350"           # FRESTORE (A0)
                  "2238 1B00"      # MOVE.L ($1B00).W,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": IDLE_FMT - (1 << 32) if IDLE_FMT >= (1 << 31) else IDLE_FMT,
})

# T5 — null-restore then control-mode FSAVE overwrites a marker at EA.
# NOTE: this FPU keeps fpu_initialized_reg='1' across FRESTORE-NULL (Mac II
# boot-detect workaround, mc68881_top.vhd line ~2447), so the save emits an
# IDLE frame, never NULL — the kernel's 4-byte NULL writer stays untestable
# here (it is spec-correct per M68881UM 6.6 and symmetric with the restore
# side's 4-byte pop from commit 0b66b67).
tests.append({
    "name": "FRESTORE NULL (A7)+ then FSAVE (A0): IDLE frame at EA over marker",
    "program": hx("42A7"           # CLR.L -(A7)
                  "F35F"           # FRESTORE (A7)+   (null restore, FPU reset)
                  "41F8 1B00"      # LEA ($1B00).W,A0
                  "223C EEEE EEEE" # MOVE.L #$EEEEEEEE,D1
                  "21C1 1B00"      # MOVE.L D1,($1B00).W  (marker)
                  "F310"           # FSAVE (A0)
                  "2238 1B00"      # MOVE.L ($1B00).W,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": IDLE_FMT - (1 << 32) if IDLE_FMT >= (1 << 31) else IDLE_FMT,
})

# T6 — abs.W EA.
tests.append({
    "name": "FSAVE ($1B00).W: format long at EA -> D1",
    "program": hx("7005"           # MOVEQ #5,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F338 1B00"      # FSAVE ($1B00).W
                  "2238 1B00"      # MOVE.L ($1B00).W,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": IDLE_FMT - (1 << 32) if IDLE_FMT >= (1 << 31) else IDLE_FMT,
})

# T7 — stack-mode regression: -(A7)/(A7)+ unchanged by the EA work.
tests.append({
    "name": "FSAVE -(A7); FRESTORE (A7)+ regression; FP3=5 -> D1",
    "program": hx("7005"           # MOVEQ #5,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F327"           # FSAVE -(A7)
                  "F35F"           # FRESTORE (A7)+
                  "F201 6180"      # FMOVE.L FP3,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 5,
})

# T8 — abs.L FRESTORE (exercises the longaktion/last_data_read EA path).
tests.append({
    "name": "FSAVE ($1B00).W; FRESTORE ($00001B00).L; FP3 clobber -> D1=99",
    "program": hx("7005"           # MOVEQ #5,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F338 1B00"      # FSAVE ($1B00).W
                  "7063"           # MOVEQ #99,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F379 0000 1B00" # FRESTORE ($00001B00).L
                  "F201 6180"      # FMOVE.L FP3,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 99,
})

# T9 — (d16,PC) FRESTORE of the frame parked at $1B00 by an abs.W FSAVE.
# Program is at $1000 fixed (PROG_BASE), so the PC-relative reach is exact:
#   FRESTORE d16(PC) at $1010, d16 word at $1012, EA = $1012 + $0AEE = $1B00.
tests.append({
    "name": "FRESTORE $AEE(PC) of parked IDLE frame; FP3 clobber -> D1=99",
    "program": hx("7005"           # $1000 MOVEQ #5,D0
                  "F200 4180"      # $1002 FMOVE.L D0,FP3
                  "F338 1B00"      # $1006 FSAVE ($1B00).W
                  "7063"           # $100A MOVEQ #99,D0
                  "F200 4180"      # $100C FMOVE.L D0,FP3
                  "F37A 0AEE"      # $1010 FRESTORE $AEE(PC)  (EA=$1B00)
                  "F201 6180"      # $1014 FMOVE.L FP3,D1
                  "4E72 2700"),    # $1018 STOP
    "result_reg": 1,
    "expected": 99,
})

with open("fsave_ea_corpus.json", "w") as f:
    json.dump(tests, f, indent=1)
print(f"wrote fsave_ea_corpus.json with {len(tests)} tests")
