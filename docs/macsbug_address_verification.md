# Mac II Address Verification via MacsBug

Verify peripheral I/O addresses on a physical Macintosh II (no PMMU / HMU variant)
to confirm the correct memory map for the LBMacTwo MiSTer core.

**Reference**: MAME `maciihmu` in `src/mame/apple/macii.cpp`

## How to Enter MacsBug

Press the programmer's switch (interrupt button) on the side of the Mac II,
or press Cmd+Power if you have MacsBug installed.

You should see the MacsBug `>` prompt.

## Commands Reference

- `DM addr` — Display memory (hex dump) at address
- `DM addr L` — Display memory as longwords
- `DB addr` — Display memory as bytes
- `SM addr value` — Set memory (write byte/word/long to address)

## Tests to Run

For each peripheral, we read a register to confirm it responds (no bus error).
A bus error means the address is wrong. Record the result for each test.

---

### 1. VIA1 — Expected: `$50F0_0000` (MAME base: `$5000_0000`, mirror at `$50F0_0000`)

```
DM 50F00000
DM 50000000
```

- [ ] `$50F00000` responds (no bus error)? ____
- [ ] `$50000000` responds (no bus error)? ____
- [ ] Data looks the same at both addresses? ____

VIA1 Data Direction Register B is at offset $0400 (VIA register spacing is $200):
```
DM 50F00000 20
DM 50F00400 20
```

- [ ] Shows register data (not all $00 or $FF)? ____

---

### 2. VIA2 — Expected: `$50F0_2000` (MAME base: `$5000_2000`)

```
DM 50F02000
DM 50002000
```

- [ ] `$50F02000` responds? ____
- [ ] `$50002000` responds? ____

---

### 3. SCC (Zilog 8530) — Expected: `$50F0_4000` (MAME base: `$5000_4000`)

**Warning**: SCC is sensitive to reads — only read, don't write random values.

```
DM 50F04000
DM 50004000
```

- [ ] `$50F04000` responds? ____
- [ ] `$50004000` responds? ____

---

### 4. SCSI (NCR 5380) — Expected: `$50F1_0000` (MAME base: `$5001_0000`)

```
DM 50F10000
DM 50010000
```

- [ ] `$50F10000` responds? ____
- [ ] `$50010000` responds? ____

---

### 5. ASC (Apple Sound Chip) — Expected: `$50F1_4000` (MAME base: `$5001_4000`)

```
DM 50F14000
DM 50014000
```

- [ ] `$50F14000` responds? ____
- [ ] `$50014000` responds? ____

---

### 6. IWM/SWIM (Floppy) — Expected: `$50F1_6000` (MAME base: `$5001_6000`)

```
DM 50F16000
DM 50016000
```

- [ ] `$50F16000` responds? ____
- [ ] `$50016000` responds? ____

---

### 7. ROM — Expected: `$4080_0000` (256KB)

```
DM 40800000
DM 40800004
```

- [ ] Shows ROM reset vectors? ____
- [ ] First longword (SSP) = `$9779D2C4`? ____
- [ ] Second longword (PC) = `$4080002A`? ____

Also check 24-bit alias:
```
DM 00800000
```
- [ ] Same data as `$40800000`? ____

---

### 8. RAM — Expected: `$0000_0000` (with overlay off)

```
DM 00000000
```

- [ ] Shows RAM contents (not ROM vectors)? ____

Try writing and reading back:
```
SM 00000100 12345678
DM 00000100
```

- [ ] Read back `$12345678`? ____

---

### 9. NuBus Slot E (Super Slot Space) — Expected: `$FE00_0000`

This is where the Toby video card declaration ROM lives:
```
DM FE010000
```

- [ ] Responds with declaration ROM data? ____

---

### 10. Mirror Pattern Check

The MAME source says I/O mirrors at `$00F0_0000` intervals. Let's verify:

```
DM 50F00000
DM 51E00000
```

- [ ] `$51E00000` responds same as `$50F00000`? ____
- [ ] Or does `$51E00000` bus error? ____

This tells us whether the mirror is truly periodic or just the two known aliases.

---

## Summary Table

Fill in after testing:

| Peripheral | $50Fx addr | $500x addr | Both work? | Notes |
|-----------|-----------|-----------|-----------|-------|
| VIA1      | $50F00000 | $50000000 |           |       |
| VIA2      | $50F02000 | $50002000 |           |       |
| SCC       | $50F04000 | $50004000 |           |       |
| SCSI      | $50F10000 | $50010000 |           |       |
| ASC       | $50F14000 | $50014000 |           |       |
| IWM/SWIM  | $50F16000 | $50016000 |           |       |
| ROM       | $40800000 | $00800000 |           |       |
| NuBus E   | $FE010000 |           |           |       |

## Current Address Decoder Implementation

File: `rtl/addrDecoder.v`

Currently checks `address[31:24] == 8'h50` (matches both `$500x` and `$50Fx`)
and uses `address[19:13]` for sub-device selection, ignoring bits 23:20 (mirror).

If the physical Mac II shows that ONLY `$50Fx` works (not `$500x`), we should
change the decoder to `address[31:20] == 12'h50F` instead.

If both work, the current `address[31:24] == 8'h50` implementation is correct.
