#!/usr/bin/env python3
"""Generate fmovem_corpus.json — FMOVEM.X through the CIR dialog.

Phase C of the MacsBug work: the FPU previously misdecoded FMOVEM
register-list command words as single-operand transfers (corpus
#1304-#1319 "FP1 keeps a stale value"), and the kernel had no
predec/postinc cpGEN EAs. Covers:
  - the exact failing corpus shape: FMOVEM.X FP0,-(A7); (A7)+,FP1
  - the exact MacsBug context save/restore: FMOVEM fp0-fp7 <-> d16(A5)
  - A7 integrity across predec/postinc round-trips
  - partial multi-register lists (ordering + EA-drop arithmetic)

List conventions (Musashi oracle, m68kfpu.c fmovem):
  control/postinc (cmd mode 10): bit i = FP(7-i)
  predecrement    (cmd mode 00): bit i = FP(i)

Run:  python3 gen_fmovem_corpus.py   (writes fmovem_corpus.json)
"""
import json

def hx(s: str) -> list[int]:
    s = s.replace(" ", "").replace("_", "")
    return [int(s[i:i+2], 16) for i in range(0, len(s), 2)]

tests = []

# 1 — the corpus-failing shape, byte-for-byte the same instruction pair.
tests.append({
    "name": "FMOVEM.X FP0,-(A7); (A7)+,FP1 a=-38 -> D1",
    "program": hx("70DA"           # MOVEQ #-38,D0
                  "F200 4000"      # FMOVE.L D0,FP0
                  "F227 E001"      # FMOVEM.X FP0,-(A7)    (predec list: bit0=FP0)
                  "F21F D040"      # FMOVEM.X (A7)+,FP1    (postinc list: bit6=FP1)
                  "F201 6080"      # FMOVE.L FP1,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": -38,
})

# 2 — MacsBug context save/restore: all eight registers through d16(A5),
# negative displacement, control addressing both directions.
tests.append({
    "name": "FMOVEM.X FP0-FP7,-$24E(A5); clobber; restore -> D1=11",
    "program": hx("4BF8 2000"      # LEA ($2000).W,A5
                  "700B"           # MOVEQ #11,D0
                  "F200 4100"      # FMOVE.L D0,FP2
                  "F22D F0FF FDB2" # FMOVEM.X FP0-FP7,-$24E(A5)  (EA=$1DB2)
                  "7063"           # MOVEQ #99,D0
                  "F200 4100"      # FMOVE.L D0,FP2        (clobber)
                  "F22D D0FF FDB2" # FMOVEM.X -$24E(A5),FP0-FP7  (restore)
                  "F201 6100"      # FMOVE.L FP2,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 11,
})

# 3 — A7 must come back to its starting value after push 8 + pop 8.
tests.append({
    "name": "FMOVEM.X FP0-FP7 -(A7)/(A7)+ leaves A7 balanced -> D1=1",
    "program": hx("200F"           # MOVE.L A7,D0
                  "F227 E0FF"      # FMOVEM.X FP0-FP7,-(A7)   (predec list $FF)
                  "F21F D0FF"      # FMOVEM.X (A7)+,FP0-FP7   (postinc list $FF)
                  "7200"           # MOVEQ #0,D1
                  "B08F"           # CMP.L A7,D0
                  "6602"           # BNE.S +2
                  "7201"           # MOVEQ #1,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 1,
})

# 4 — partial list (FP1/FP3), predec save + postinc restore, value checked
# through FP3. predec list: FP1|FP3 = bits 1,3 = $0A; postinc list:
# FP1=bit6, FP3=bit4 = $50.
tests.append({
    "name": "FMOVEM.X FP1/FP3 partial list round-trip -> D1=43",
    "program": hx("7015"           # MOVEQ #21,D0
                  "F200 4080"      # FMOVE.L D0,FP1
                  "702B"           # MOVEQ #43,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F227 E00A"      # FMOVEM.X FP1/FP3,-(A7)
                  "7063"           # MOVEQ #99,D0
                  "F200 4080"      # FMOVE.L D0,FP1        (clobber both)
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F21F D050"      # FMOVEM.X (A7)+,FP1/FP3
                  "F201 6180"      # FMOVE.L FP3,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 43,
})

# 5 — FMOVEM to (An) control mode with memory layout probe: FP0 list only;
# .X of integer 1 (FMOVE.L D0,FP0 with D0=1) — first long of the .X image
# is {sign+exp, reserved} = $3FFF0000 for 1.0.
tests.append({
    "name": "FMOVEM.X FP0,(A0): .X sign+exp long at EA -> D1=$3FFF0000",
    "program": hx("7001"           # MOVEQ #1,D0
                  "F200 4000"      # FMOVE.L D0,FP0
                  "41F8 1B00"      # LEA ($1B00).W,A0
                  "F210 F080"      # FMOVEM.X FP0,(A0)     (control list: bit7=FP0)
                  "2238 1B00"      # MOVE.L ($1B00).W,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 0x3FFF0000,
})

with open("fmovem_corpus.json", "w") as f:
    json.dump(tests, f, indent=1)
print(f"wrote fmovem_corpus.json with {len(tests)} tests")
