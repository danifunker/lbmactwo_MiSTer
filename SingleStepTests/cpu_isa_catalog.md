# MC68020 Instruction Set Catalog

**Source:** *M68000 Family Programmer's Reference Manual* (M68000PM/AD), Sections 3
and Appendix A.2. Cross-referenced with *M68020 User's Manual* (MC68020UM).

This document is the authoritative scope for what the CPU test bench should
eventually cover. Each instruction is annotated with:

- **Mnemonic** — the assembler mnemonic
- **Sizes** — operand sizes the instruction accepts (.B/.W/.L)
- **EAs** — which addressing-mode classes the instruction accepts
  for its operands (see §EA Class Codes below)
- **Flags** — XNZVC effects per the PRM Table 3-18
- **From** — earliest processor that supports it
- **Priv** — `S` if supervisor-only
- **Status** — `✓ tested` / `partial` / `gap` / `blocked` / `oos`
  (oos = out of scope — see §Out-of-Scope below)

## EA class codes

Compact notation for the per-instruction `EAs` column. M68k allowed-mode columns
in the PRM use these category sets:

- **D** — `Dn` (data register direct)
- **A** — `An` (address register direct)
- **M** — `(An)` (address-register indirect)
- **+** — `(An)+`
- **−** — `-(An)`
- **d16A** — `(d16,An)`
- **d8AX** — `(d8,An,Xn)` brief extension (includes 020+ scaled form)
- **bdAX** — `(bd,An,Xn)` full extension (68020+ only)
- **MI**  — memory indirect `([bd,An],Xn,od)` / `([bd,An,Xn],od)` (68020+)
- **PC** — `(d16,PC)`, `(d8,PC,Xn)`, etc. (PC-relative variants)
- **abs** — `(xxx).W` / `(xxx).L`
- **#**  — immediate

Common PRM groupings:
- **data alterable** = D + M+ + d16A + d8AX + bdAX + MI + abs
- **memory alterable** = M+ + d16A + d8AX + bdAX + MI + abs
- **control** = M + d16A + d8AX + bdAX + MI + PC + abs (no D/A/+/−/#)
- **any** = all of the above

## CCR / flag effects key

From PRM Table 3-18:
- `*` — set per definition (per-instruction formula)
- `?` — set, see special-definition column
- `0` — always cleared
- `1` — always set
- `U` — undefined (manual says don't rely on it)
- `—` — not affected

---

## Status legend

| Status | Meaning |
|---|---|
| ✓ | All currently-tested forms pass against MAME oracle |
| ◐ | Some forms tested, more variations would add coverage |
| ☐ | Not tested in current corpus |
| ⚙ | Out of scope for ISA bench (needs different harness) |
| ⛔ | Blocked (e.g., CPU+FPU integration blocked on CIR bug) |

---

## 1. Data Movement Instructions (PRM §3.1.1, Table 3-2)

| Mnemonic | Sizes | Source EAs | Dest EAs | Flags | From | Priv | Status |
|---|---|---|---|---|---|---|---|
| **MOVE** | B/W/L | any | data-alterable | NZVC=*\*00 | 68000 | — | ◐ Dm,Dn + d16(A6) + (An)/(An)+/-(An) + #imm; no PC-rel, no abs.L src |
| **MOVEA** | W/L | any | An | — | 68000 | — | ◐ via MOVE.L Dm,Dn pattern; no explicit MOVEA tests |
| **MOVEQ** | L (8→32) | #imm-8 | Dn | NZ=*, VC=0 | 68000 | — | ✓ |
| **MOVEM** | W/L | any/list | list/any | — | 68000 | — | ◐ `(A6)` only; pre/postincrement forms untested |
| **MOVEP** | W/L | Dn↔(d16,An) | — | — | 68000 | — | ☐ peripheral (obsolete; Mac never uses); skip |
| **EXG** | L | Dn↔Dn, An↔An, Dn↔An | — | — | 68000 | — | ☐ |
| **LEA** | L | control | An | — | 68000 | — | ◐ (A6),An + d16(A6),An; need more EA modes incl. PC-rel |
| **PEA** | L | control | -(SP) | — | 68000 | — | ☐ stack op — needs control-flow harness |
| **LINK** | W/L (disp) | An,#disp | — | — | 68000 / 68020(.L) | — | ☐ stack op |
| **UNLK** | — | An | — | — | 68000 | — | ☐ stack op |
| **MOVES** | B/W/L | Rn↔(any) | — | — | 68010 | S | ✓ (skipped on user-mode bench) |
| **MOVEC** | L | Rc↔Rn | — | — | 68010 | S | ⚙ supervisor harness needed |
| **MOVE from CCR** | W | CCR | data-alterable | — | 68010 | — | ◐ Dn-direct only |
| **MOVE to CCR** | W | data-source | CCR | XNZVC=src | 68000 | — | ◐ Dn-direct only |
| **MOVE from SR** | W | SR | data-alterable | — | 68000 / 68010(S) | S on 010+ | ⚙ |
| **MOVE to SR** | W | data-source | SR | XNZVC=src | 68000 | S | ⚙ |
| **MOVE USP** | L | USP↔An | — | — | 68000 | S | ⚙ |
| **SWAP** | L | Dn | — | NZ=*, VC=0 | 68000 | — | ✓ |

---

## 2. Integer Arithmetic Instructions (PRM §3.1.2, Table 3-3)

| Mnemonic | Sizes | Source EAs | Dest EAs | Flags | From | Status |
|---|---|---|---|---|---|---|
| **ADD** | B/W/L | any↔data-alterable | — | XNZVC=* | 68000 | ◐ Dm,Dn ✓; (A6),Dn ✓; D0,(A6) ✓. No abs/PC-rel/memory-indirect |
| **ADDA** | W/L | any | An | — | 68000 | ◐ #imm,An ✓; no Dn,An or mem,An |
| **ADDI** | B/W/L | #imm | data-alterable | XNZVC=* | 68000 | ◐ #imm,Dn ✓ only |
| **ADDQ** | B/W/L | #1-8 | alterable | XNZVC=* (—,—,—,—,— if An dst) | 68000 | ☐ |
| **ADDX** | B/W/L | Dn,Dn or -(An),-(An) | — | XNZVC=* | 68000 | ✓ Dm,Dn only; predec-predec untested |
| **CLR** | B/W/L | — | data-alterable | NZ=01, VC=0 | 68000 | ✓ Dn |
| **CMP** | B/W/L | any | Dn | NZVC=* | 68000 | ✓ Dm,Dn |
| **CMPA** | W/L | any | An | NZVC=* | 68000 | ✓ A1,A0 (.W and .L) |
| **CMPI** | B/W/L | #imm | data-alterable | NZVC=* | 68000 | ✓ #imm,Dn |
| **CMPM** | B/W/L | (An)+ | (An)+ | NZVC=* | 68000 | ✓ |
| **CMP2** | B/W/L | control | Rn | NZVC=? | 68020 | ☐ |
| **DIVS / DIVU** (.W) | 32÷16→16:16 | data-source | Dn | NZVC=*, C=0 | 68000 | ✓ |
| **DIVSL / DIVUL** (.L) | 32÷32 or 64÷32 | data-source | Dq or Dr-Dq | NZVC=*, C=0 | 68020 | ✓ |
| **EXT** | B→W, W→L | Dn | — | NZ=*, VC=0 | 68000 | ✓ |
| **EXTB** | B→L | Dn | — | NZ=*, VC=0 | 68020 | ✓ |
| **MULS / MULU** (.W) | 16×16→32 | data-source | Dn | NZVC=*, C=0 | 68000 | ✓ |
| **MULS.L / MULU.L** | 32×32→32 or 64 | data-source | Dl or Dh-Dl | NZVC=*, C=0 | 68020 | ✓ |
| **NEG** | B/W/L | data-alterable | — | XNZVC=* | 68000 | ✓ Dn |
| **NEGX** | B/W/L | data-alterable | — | XNZVC=* | 68000 | ☐ |
| **SUB** | B/W/L | any↔data-alterable | — | XNZVC=* | 68000 | ◐ Dm,Dn only |
| **SUBA** | W/L | any | An | — | 68000 | ◐ #imm,An ✓ |
| **SUBI** | B/W/L | #imm | data-alterable | XNZVC=* | 68000 | ◐ #imm,Dn ✓ |
| **SUBQ** | B/W/L | #1-8 | alterable | XNZVC=* | 68000 | ☐ |
| **SUBX** | B/W/L | Dn,Dn or -(An),-(An) | — | XNZVC=* | 68000 | ✓ Dm,Dn only |
| **TST** | B/W/L | data-alterable (PC-rel on 020+) | — | NZ=*, VC=0 | 68000 | ✓ Dn |

---

## 3. Logical Instructions (PRM §3.1.3, Table 3-4)

| Mnemonic | Sizes | Source EAs | Dest EAs | Flags | From | Status |
|---|---|---|---|---|---|---|
| **AND** | B/W/L | data-source↔data-alterable | — | NZ=*, VC=0 | 68000 | ✓ Dm,Dn |
| **ANDI** | B/W/L | #imm | data-alterable | NZ=*, VC=0 | 68000 | ✓ #imm,Dn |
| **ANDI to CCR** | B | #imm | CCR | XNZVC=src∧CCR | 68000 | ☐ |
| **ANDI to SR** | W | #imm | SR | XNZVC=src∧SR | 68000(S) | ⚙ |
| **EOR** | B/W/L | Dn | data-alterable | NZ=*, VC=0 | 68000 | ✓ Dn,Dm |
| **EORI** | B/W/L | #imm | data-alterable | NZ=*, VC=0 | 68000 | ✓ #imm,Dn |
| **EORI to CCR** | B | #imm | CCR | XNZVC=src⊕CCR | 68000 | ☐ |
| **EORI to SR** | W | #imm | SR | XNZVC=src⊕SR | 68000(S) | ⚙ |
| **NOT** | B/W/L | data-alterable | — | NZ=*, VC=0 | 68000 | ✓ Dn |
| **OR** | B/W/L | data-source↔data-alterable | — | NZ=*, VC=0 | 68000 | ✓ Dm,Dn |
| **ORI** | B/W/L | #imm | data-alterable | NZ=*, VC=0 | 68000 | ✓ #imm,Dn |
| **ORI to CCR** | B | #imm | CCR | XNZVC=src∨CCR | 68000 | ☐ |
| **ORI to SR** | W | #imm | SR | XNZVC=src∨SR | 68000(S) | ⚙ |

---

## 4. Shift and Rotate Instructions (PRM §3.1.4, Table 3-5)

Reg-shift: B/W/L size, count from #1-8 imm OR Dm modulo 64.
Mem-shift: W size only, single-bit shift on memory operand.

| Mnemonic | Sizes | Forms | Flags | From | Status |
|---|---|---|---|---|---|
| **ASL** | B/W/L | #imm,Dn / Dm,Dn / <ea> mem-W | XNZVC=* | 68000 | ✓ #imm,Dn .L; ◐ Dm,Dn .L; mem ✓ |
| **ASR** | B/W/L | #imm,Dn / Dm,Dn / <ea> mem-W | XNZVC=* | 68000 | ✓ #imm,Dn .L; ☐ Dm,Dn; ☐ mem |
| **LSL** | B/W/L | #imm,Dn / Dm,Dn / <ea> mem-W | XNZVC=* | 68000 | ✓ #imm,Dn .L; ◐ Dm,Dn .L; ☐ mem |
| **LSR** | B/W/L | #imm,Dn / Dm,Dn / <ea> mem-W | XNZVC=* | 68000 | ✓ #imm,Dn .L; ✓ Dm,Dn .L; ✓ mem |
| **ROL** | B/W/L | #imm,Dn / Dm,Dn / <ea> mem-W | NZVC=*, V=0, X=— | 68000 | ✓ #imm,Dn .L; ✓ Dm,Dn .L; ☐ mem |
| **ROR** | B/W/L | #imm,Dn / Dm,Dn / <ea> mem-W | NZVC=*, V=0, X=— | 68000 | ✓ #imm,Dn .L; ☐ Dm,Dn; ☐ mem |
| **ROXL** | B/W/L | #imm,Dn / Dm,Dn / <ea> mem-W | XNZVC=* | 68000 | ✓ #imm,Dn .L; ☐ Dm,Dn; ☐ mem |
| **ROXR** | B/W/L | #imm,Dn / Dm,Dn / <ea> mem-W | XNZVC=* | 68000 | ✓ #imm,Dn .L; ☐ Dm,Dn; ☐ mem |
| **SWAP** | L | Dn | NZ=*, VC=0 | 68000 | ✓ |

**Gap notes**: We tested all 8 shift/rotate ops in #imm,Dn .L form. The .W/.B
sizes, register-count form (`Dm,Dn`), and memory single-bit form are mostly
gaps. The mem-W form has a separate decode path in the kernel and is worth
covering for at least 2-3 ops.

---

## 5. Bit Manipulation Instructions (PRM §3.1.5, Table 3-6)

| Mnemonic | Sizes | Forms | Flags | From | Status |
|---|---|---|---|---|---|
| **BCHG** | B (mem) / L (Dn) | Dn,<ea> / #imm,<ea> | Z=* | 68000 | ✓ Dn,Dm (dynamic .L) |
| **BCLR** | B / L | Dn,<ea> / #imm,<ea> | Z=* | 68000 | ✓ Dn,Dm (dynamic .L) |
| **BSET** | B / L | Dn,<ea> / #imm,<ea> | Z=* | 68000 | ✓ Dn,Dm + #imm,Dn |
| **BTST** | B / L | Dn,<ea> / #imm,<ea> | Z=* | 68000 | ✓ Dn,Dm + #imm,Dn |

**Gap notes**: All four currently tested in Dn-direct form only. The B-size
memory form (e.g., `BTST D0,(A1)`) has a separate decode path and is untested.

---

## 6. Bit Field Instructions (PRM §3.1.6, Table 3-7)

All bit-field ops: variable width 1-32, EA = data-alterable for memory dst
(Dn-direct also supported).

| Mnemonic | EAs | Flags | Status |
|---|---|---|---|
| **BFTST** | Dn or control | N=Field MSB, Z=Field==0, VC=0 | ✓ Dn-only |
| **BFEXTU** | Dn or control + Dn dst | N=Field MSB, Z=Field==0, VC=0 | ✓ Dn-direct + dynamic offset/width |
| **BFEXTS** | Dn or control + Dn dst | N=Field MSB, Z=Field==0, VC=0 | ✓ Dn-only |
| **BFFFO** | Dn or control + Dn dst | flags from source | ✓ Dn-only |
| **BFINS** | Dn src + Dn or data-alterable | N=Dn src MSB, Z=Dn src==0, VC=0 | ✓ Dn + memory |
| **BFCHG** | Dn or data-alterable | N=Field MSB, Z=Field==0, VC=0 | ✓ Dn-only |
| **BFCLR** | Dn or data-alterable | flags pre-clear | ✓ Dn-only |
| **BFSET** | Dn or data-alterable | flags pre-set | ✓ Dn-only |

**All 68020+ instructions** (don't exist on 68000/68010).
**Gap**: Memory-EA form (apart from `BFINS,(A6)`); other dynamic-offset variants.

---

## 7. Binary-Coded Decimal Instructions (PRM §3.1.7, Table 3-8)

| Mnemonic | Sizes | Forms | Flags | From | Status |
|---|---|---|---|---|---|
| **ABCD** | B | Dn,Dn / -(An),-(An) | X=*, C=*, NV=U, Z=* (cumulative) | 68000 | ✓ Dn,Dn |
| **NBCD** | B | <ea> | X=*, C=*, NV=U, Z=* (cumulative) | 68000 | ✓ Dn |
| **SBCD** | B | Dn,Dn / -(An),-(An) | X=*, C=*, NV=U, Z=* (cumulative) | 68000 | ✓ Dn,Dn |
| **PACK** | W→B | -(An),-(An),#data / Dn,Dn,#data | — | 68020 | ✓ Dn,Dn |
| **UNPK** | B→W | -(An),-(An),#data / Dn,Dn,#data | — | 68020 | ✓ Dn,Dn |

**Gap**: predec-predec memory form for ABCD/SBCD/PACK/UNPK.

---

## 8. Program Control Instructions (PRM §3.1.8, Table 3-9)

| Mnemonic | Sizes | Form | Flags | From | Status |
|---|---|---|---|---|---|
| **Bcc** | B/W/L | <label> displacement | — | 68000 / .L=68020 | ☐ Bcc family gap; partial Bcc.W + Bcc.B test exists but not in committed corpus yet |
| **BRA** | B/W/L | <label> | — | 68000 / .L=68020 | ☐ |
| **BSR** | B/W/L | <label> | — | 68000 / .L=68020 | ☐ |
| **DBcc** | W | Dn,<label> | — | 68000 | ☐ DBF (DBRA) partial test exists |
| **Scc** | B | <ea> data-alterable | — | 68000 | ☐ |
| **JMP** | — | control | — | 68000 | ☐ JMP (d16,PC) partial test exists |
| **JSR** | — | control | — | 68000 | ☐ JSR/RTS round-trip partial test exists |
| **NOP** | — | — | — | 68000 | ✓ |
| **RTD** | — | #disp16 | — | 68010 | ☐ |
| **RTR** | — | — | CCR from stack | 68000 | ☐ |
| **RTS** | — | — | — | 68000 | ☐ implicitly via JSR/RTS test |

**All control-flow currently needs the "marker byte" harness extension**
sketched in the WIP `mame_cpu_capture.lua` changes (Bcc/BRA/DBcc/Scc/JMP/JSR/LINK).
Those tests were drafted but not yet integrated cleanly with TG68K verification.

---

## 9. System Control Instructions (PRM §3.1.9, Table 3-10)

### Privileged

| Mnemonic | Status |
|---|---|
| ANDI/EORI/ORI to SR | ⚙ |
| FRESTORE / FSAVE | ⛔ FPU integration blocked |
| MOVE to SR / MOVE from SR | ⚙ |
| MOVE USP / MOVEC | ⚙ |
| MOVES | ✓ (skipped in user mode) |
| RESET / STOP | ⚙ |
| RTE | ⚙ exception harness needed |

### Trap-generating

| Mnemonic | Status |
|---|---|
| BKPT | ⚙ debug-specific |
| CHK | ☐ needs vector handler |
| CHK2 | ☐ needs vector handler (68020+) |
| ILLEGAL | ⚙ |
| TRAP #N | ⚙ needs vector handler |
| TRAPcc | ⚙ needs vector handler (68020+) |
| TRAPV | ⚙ |

### CCR-only (non-privileged)

| Mnemonic | Status |
|---|---|
| ANDI to CCR | ☐ |
| EORI to CCR | ☐ |
| ORI to CCR | ☐ |
| MOVE to CCR / from CCR | ✓ |

---

## 10. Multiprocessor Instructions (PRM §3.1.11, Table 3-12)

| Mnemonic | From | Status |
|---|---|---|
| **CAS** | 68020 | ☐ atomic — specialty; complex semantics; low priority |
| **CAS2** | 68020 | ☐ atomic; very rare in Mac code |
| **TAS** | 68000 | ☐ atomic test-and-set |

---

## 11. Coprocessor Instructions (F-line, PRM Table 3-12)

All require the CIR (Coprocessor Interface Register) protocol. **Currently blocked**
on the `mc68881_top` CIR_ADDR_RESPONSE read-path bug
(see `memory/project_fpu_cir_response_bug.md`).

| Mnemonic | Used by 68881 as | Status |
|---|---|---|
| **cpGEN** | FADD/FSUB/FMUL/FDIV/FMOVE/FCMP/...(general FP ops) | ⛔ |
| **cpBcc** | FBcc.W / FBcc.L | ⛔ |
| **cpDBcc** | FDBcc | ⛔ |
| **cpScc** | FScc | ⛔ |
| **cpTRAPcc** | FTRAPcc | ⛔ |
| **cpSAVE / cpRESTORE** | FSAVE / FRESTORE | ⛔ |

---

## 12. Floating-Point Instructions (68881/68882 via F-line) — separate corpus

Tracked separately in `SingleStepTests/results/fpu/`. Full 270-test FPU oracle
exists; hardware baseline 170/270 (63%) recorded in
`results/fpu/hw_vs_mame_2026-05-16.md`. Integration-with-TG68K blocked on CIR
Response read bug.

---

## Addressing Mode Coverage (PRM Table A-7)

| Mode | Syntax | Tested? |
|---|---|---|
| Dn direct | `Dn` | ✓ |
| An direct | `An` | ✓ (limited to MOVEA/CMPA/LEA dst) |
| (An) indirect | `(An)` | ✓ ((A6) only) |
| (An)+ postincrement | `(An)+` | ✓ |
| -(An) predecrement | `-(An)` | ✓ |
| (d16,An) | `(d16,An)` | ✓ via (d16,A6) |
| (d8,An,Xn) brief, scale=1 | `(d8,A6,D7.W)` | ✓ |
| (d8,An,Xn) scaled | scale=2/4/8 | ✓ |
| (bd,An,Xn) full extension | 68020+ | ☐ |
| ([bd,An],Xn,od) memory-indirect postindexed | 68020+ | ☐ |
| ([bd,An,Xn],od) memory-indirect preindexed | 68020+ | ☐ |
| (d16,PC) | `(d16,PC)` | ◐ JMP form only |
| (d8,PC,Xn) | brief PC-indexed | ☐ |
| (bd,PC,Xn) | full PC-indexed | ☐ |
| ([bd,PC],Xn,od) PC memory-indirect | 68020+ | ☐ |
| ([bd,PC,Xn],od) PC memory-indirect | 68020+ | ☐ |
| (xxx).W | abs short | ☐ |
| (xxx).L | abs long | ◐ via state-dump epilogue infra; no test instructions |
| #data | immediate | ✓ |

**Highest bug-surface gaps in TG68K**:
- **Full extension** `(bd,An,Xn)` and **memory-indirect** modes (020-specific
  decode logic, complex)
- **PC-indexed brief and full** (similar but PC-relative)
- **(xxx).W absolute short** sign-extension semantics

---

## Out-of-Scope (not on roadmap)

| Instruction(s) | Reason |
|---|---|
| MOVE16 | 68040-only |
| CALLM / RTM | 68020-only, never widely used, no toolchain support |
| MMU ops (PFLUSH, PMOVE, etc.) | not on MC68020 (no PMMU); 68030/851 specific |
| Cache ops (CINV, CPUSH) | 68040+ |
| PBcc / PDBcc / PScc / PTRAPcc | PMMU, not 68020 |
| MMU registers | n/a |

---

## Conditional codes — used by Bcc, DBcc, Scc, TRAPcc

From PRM Table 3-19. Encoding is 4-bit field in those instructions.

| cc | Encoding | Test |
|---|---|---|
| T (true) | 0000 | 1 (always; not valid for Bcc) |
| F (false) | 0001 | 0 (never; not valid for Bcc) |
| HI (higher unsigned) | 0010 | C∧Z |
| LS (lower-or-same unsigned) | 0011 | C∨Z |
| CC=HI=HI (carry clear) | 0100 | ¬C |
| CS=LO (carry set) | 0101 | C |
| NE (not equal) | 0110 | ¬Z |
| EQ (equal) | 0111 | Z |
| VC (overflow clear) | 1000 | ¬V |
| VS (overflow set) | 1001 | V |
| PL (plus) | 1010 | ¬N |
| MI (minus) | 1011 | N |
| GE (greater-or-equal signed) | 1100 | N∧V ∨ ¬N∧¬V |
| LT (less-than signed) | 1101 | N∧¬V ∨ ¬N∧V |
| GT (greater-than signed) | 1110 | (N∧V ∨ ¬N∧¬V) ∧ ¬Z |
| LE (less-or-equal signed) | 1111 | Z ∨ (N∧¬V) ∨ (¬N∧V) |

---

## Bench-roadmap summary

Recommended next batches, in priority order:

1. **Control flow as a class** — Bcc/BRA/BSR (all three sizes), DBcc, Scc, JMP, JSR/RTS,
   LINK/UNLK. Marker-byte harness extension. ~50 tests.
2. **TST + ADDQ/SUBQ + ADDX/SUBX predec form + NEGX** — quick wins in existing harness, ~12 tests.
3. **EOR/EORI/ORI/ANDI to CCR** — quick wins, ~4 tests.
4. **020 addressing modes** — full extension, memory-indirect (the highest-risk
   for TG68K decoder bugs). ~30 tests across a few representative ops.
5. **Shift/rotate broader coverage** — register-count form for the 5 ops missing it;
   memory single-bit form for 6 ops; .B/.W sizes. ~25 tests.
6. **Bit-manipulation memory form** — BTST/BCHG/BCLR/BSET .B against (An). ~8 tests.
7. **BCD predec memory form** — ABCD/SBCD/PACK/UNPK -(An),-(An). ~4 tests.
8. **MOVEA explicit, ADDQ/SUBQ explicit** — ~6 tests.
9. **Trap-generating** (TRAP/CHK/CHK2/TRAPV/TRAPcc) — needs vector-table harness. ~10 tests.
10. **CPU+FPU integration** — blocked on CIR Response bug; once unblocked, all
    270 FPU tests through the coprocessor protocol.

Items 1–8 are ~140 more tests on top of the current 215, taking us to ~355.
Item 9 needs a new harness shape (vector handler).
Item 10 lives in `cpu_fpu/` and depends on the FPU verilator core being fixed.
