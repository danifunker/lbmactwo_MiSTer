#!/usr/bin/env python3
"""Generate cpgen_mem_corpus.json — cpGEN memory-EA transfer tests.

Phase B of the MacsBug work: the kernel's cpGEN dialog historically
supported only Dn and (d16,PC) EAs; every other mode ran a Dn-shaped
transfer AND left its EA extension words in the instruction stream.
These tests cover the new (An) / (d16,An) / (xxx).W support in BOTH
directions, including the FPU→memory write path (cp_xfer_mem_wr_*)
that MacsBug's context save needs:
    FMOVE.L fpcr,-$25A(a5) / FMOVEM fp0-fp7,-$24E(a5)
plus multi-long (.X) operands that loop one long per Response round.

Run:  python3 gen_cpgen_mem_corpus.py   (writes cpgen_mem_corpus.json)
"""
import json

def hx(s: str) -> list[int]:
    s = s.replace(" ", "").replace("_", "")
    return [int(s[i:i+2], 16) for i in range(0, len(s), 2)]

tests = []

# 1 — FPU→memory, (d16,An) with negative d16: the MacsBug data-register shape.
tests.append({
    "name": "FMOVE.L FP3,-$25A(A5) to memory -> D1=42",
    "program": hx("4BF8 2000"      # LEA ($2000).W,A5
                  "702A"           # MOVEQ #42,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F22D 6180 FDA6" # FMOVE.L FP3,-$25A(A5)   (EA=$1DA6)
                  "2238 1DA6"      # MOVE.L ($1DA6).W,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 42,
})

# 2 — memory→FPU, (d16,An).
tests.append({
    "name": "FMOVE.L -$25A(A5),FP5 from memory -> D1=42",
    "program": hx("702A"           # MOVEQ #42,D0
                  "21C0 1DA6"      # MOVE.L D0,($1DA6).W
                  "4BF8 2000"      # LEA ($2000).W,A5
                  "F22D 4280 FDA6" # FMOVE.L -$25A(A5),FP5
                  "F201 6280"      # FMOVE.L FP5,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 42,
})

# 3 — the EXACT MacsBug control-register sequence: FPCR saved to d16(A5),
# clobbered, restored from d16(A5), read back.
tests.append({
    "name": "FMOVE.L FPCR,-$25A(A5); clobber; restore from mem -> D1=$30",
    "program": hx("4BF8 2000"      # LEA ($2000).W,A5
                  "7030"           # MOVEQ #$30,D0
                  "F200 9000"      # FMOVE.L D0,FPCR
                  "F22D B000 FDA6" # FMOVE.L FPCR,-$25A(A5)
                  "7000"           # MOVEQ #0,D0
                  "F200 9000"      # FMOVE.L D0,FPCR        (clobber)
                  "F22D 9000 FDA6" # FMOVE.L -$25A(A5),FPCR (restore)
                  "F201 B000"      # FMOVE.L FPCR,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 0x30,
})

# 4 — multi-long .X operand BOTH directions through (An): three Response
# rounds each way, cp_ea_addr +4 per round.
tests.append({
    "name": "FMOVE.X FP3,(A0); FMOVE.X (A0),FP5 round-trip -> D1=-5",
    "program": hx("70FB"           # MOVEQ #-5,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "41F8 1B00"      # LEA ($1B00).W,A0
                  "F210 6980"      # FMOVE.X FP3,(A0)
                  "F210 4A80"      # FMOVE.X (A0),FP5
                  "F201 6280"      # FMOVE.L FP5,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": -5,
})

# 5 — FPU→memory via (xxx).W.
tests.append({
    "name": "FMOVE.L FP3,($1B00).W to memory -> D1=7",
    "program": hx("7007"           # MOVEQ #7,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F238 6180 1B00" # FMOVE.L FP3,($1B00).W
                  "2238 1B00"      # MOVE.L ($1B00).W,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 7,
})

# 6 — memory→FPU via (An), negative value.
tests.append({
    "name": "FMOVE.L (A0),FP5 from memory -> D1=-7",
    "program": hx("70F9"           # MOVEQ #-7,D0
                  "21C0 1B00"      # MOVE.L D0,($1B00).W
                  "41F8 1B00"      # LEA ($1B00).W,A0
                  "F210 4280"      # FMOVE.L (A0),FP5
                  "F201 6280"      # FMOVE.L FP5,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": -7,
})

# 7 — arithmetic with a memory source EA: FADD.L (d16,An),FP3.
tests.append({
    "name": "FADD.L -$25A(A5),FP3 (5+37) -> D1=42",
    "program": hx("7025"           # MOVEQ #37,D0
                  "21C0 1DA6"      # MOVE.L D0,($1DA6).W
                  "4BF8 2000"      # LEA ($2000).W,A5
                  "7005"           # MOVEQ #5,D0
                  "F200 4180"      # FMOVE.L D0,FP3
                  "F22D 41A2 FDA6" # FADD.L -$25A(A5),FP3
                  "F201 6180"      # FMOVE.L FP3,D1
                  "4E72 2700"),
    "result_reg": 1,
    "expected": 42,
})

with open("cpgen_mem_corpus.json", "w") as f:
    json.dump(tests, f, indent=1)
print(f"wrote cpgen_mem_corpus.json with {len(tests)} tests")
