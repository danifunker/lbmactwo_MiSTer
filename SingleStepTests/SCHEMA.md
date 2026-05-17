# Test JSON schema (state-only)

Each `.json` file in a corpus is an array of test entries. One entry per
single instruction.

## CPU entry (TG68K bench)

```json
{
  "name": "ADD.l 00001",
  "initial": {
    "d0": 305419896, "d1": 0, "d2": 0, "d3": 0,
    "d4": 0, "d5": 0, "d6": 0, "d7": 0,
    "a0": 1024, "a1": 0, "a2": 0, "a3": 0,
    "a4": 0, "a5": 0, "a6": 0, "a7": 16776192,
    "pc": 4096,
    "sr": 8192,
    "usp": 0,
    "ssp": 16776192,
    "vbr": 0,
    "ram": [[4096, 208], [4097, 129]]
  },
  "final": {
    "d0": 305419896, "d1": 305419896,
    ... all regs ...,
    "pc": 4098,
    "sr": 8192,
    "ram": []
  }
}
```

Rules:
- All integer fields are unsigned decimal (json doesn't allow hex literals).
- `ram` is a list of `[address, byte]` pairs. `initial.ram` is the
  pre-state; `final.ram` lists only bytes that DIFFER from `initial`
  (so empty array = unchanged).
- Reg names match Musashi: `d0..d7`, `a0..a7`, `pc`, `sr`, `usp`, `ssp`,
  `vbr`. `a7` and `ssp`/`usp` are redundant per supervisor state; bench
  uses `a7` and ignores the other two for now (kept for future
  privileged-mode tests).
- `pc` is the address of the next instruction (post-fetch).
- No cycle counts. The bench runs until the CPU returns to idle
  (busstate=01) after consuming the instruction.

## FPU entry (FPU bench)

TBD — see Task #12. Expected shape:

```json
{
  "name": "FADD.X 00001",
  "initial": {
    "fp0": "3FFF8000000000000000",  // 80-bit ext, hex string
    "fp1": "...",
    ...
    "fpcr": 0, "fpsr": 0, "fpiar": 0,
    "opword": 61984,    // F-line opword
    "ext":    34
  },
  "final": {
    "fp0": "...",
    "fpsr": 0,
    ...
  }
}
```

CIR write order, operand format, etc. all baked into the bench driver.
