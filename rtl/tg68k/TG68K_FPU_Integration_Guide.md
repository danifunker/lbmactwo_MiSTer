# TG68K FPU Integration Guide

## Overview

This guide explains how to integrate and use the FPU-enabled TG68K CPU core in your FPGA project. The TG68K now includes a complete MC68881/68882 compatible Floating-Point Unit that provides IEEE 754 compliant floating-point operations.

## Quick Start

### 1. Basic Instantiation

```verilog
tg68k #(
    .FPU_Enable(1)  // Enable the FPU
) cpu (
    .clk(clk),
    .reset(reset),
    .phi1(phi1),
    .phi2(phi2),
    .cpu(2'b11),    // Must be 68020 for FPU support
    
    // Connect your bus signals...
    .addr(cpu_addr),
    .din(cpu_din),
    .dout(cpu_dout),
    .as_n(cpu_as_n),
    .uds_n(cpu_uds_n),
    .lds_n(cpu_lds_n),
    .rw_n(cpu_rw_n),
    .dtack_n(cpu_dtack_n),
    .fc(cpu_fc),
    
    // Interrupts
    .ipl(cpu_ipl),
    .berr(1'b0),
    
    // E clock for peripherals
    .E(E_clock),
    .E_div(1'b0),
    .vpa_n(1'b1),
    .vma_n(),
    
    // Bus arbitration (if unused)
    .br_n(1'b1),
    .bg_n(),
    .bgack_n(1'b1),
    
    // Reset output
    .reset_n(cpu_reset_n)
);
```

### 2. Disable FPU (Save Resources)

If you don't need floating-point operations:

```verilog
tg68k #(
    .FPU_Enable(0)  // Disable FPU, save ~15-20% logic
) cpu (
    // ... same connections
);
```

## Architecture Overview

```
┌─────────────────────────────────────────┐
│         tg68k.v (Verilog Wrapper)       │
│  - Bus state machine                    │
│  - Clock phase generation (phi1/phi2)   │
│  - Bus arbitration                      │
│  - E clock generation                   │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│        TG68K.vhd (VHDL Wrapper)         │
│  - Async to sync bus conversion         │
│  - VPA/VMA handling                     │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   TG68KdotC_Kernel.vhd (CPU Core)       │
│  - Instruction decode and execution     │
│  - Register file (D0-D7, A0-A7)         │
│  - ALU, multiplier, divider             │
│  - Exception handling                   │
│  - FPU integration (when enabled)       │
└──────────────┬──────────────────────────┘
               │ (if FPU_Enable = 1)
               ▼
┌─────────────────────────────────────────┐
│      TG68K_FPU.vhd (FPU Module)         │
│  - 8 × 80-bit FP registers (FP0-FP7)    │
│  - FPCR, FPSR, FPIAR control registers  │
│  - FPU ALU (add, sub, mul, div, sqrt)   │
│  - Transcendental unit (sin, cos, etc)  │
│  - Format converter (S/D/X/P formats)   │
│  - Exception logic                      │
│  - CIR protocol handler                 │
└─────────────────────────────────────────┘
```

## FPU Features

### Supported Instructions

#### Data Movement
- `FMOVE.{B,W,L,S,D,X,P}` - Move data to/from FP registers
- `FMOVEM` - Move multiple FP registers
- `FMOVECR #ccc,FPn` - Load constant from ROM

#### Arithmetic
- `FADD.X FPm,FPn` - Floating-point add
- `FSUB.X FPm,FPn` - Floating-point subtract
- `FMUL.X FPm,FPn` - Floating-point multiply
- `FDIV.X FPm,FPn` - Floating-point divide
- `FSQRT.X FPn` - Square root
- `FABS.X FPn` - Absolute value
- `FNEG.X FPn` - Negate

#### Comparison
- `FCMP.X FPm,FPn` - Compare
- `FTST.X FPn` - Test (compare with zero)

#### Transcendental Functions
- `FSIN.X FPn` - Sine
- `FCOS.X FPn` - Cosine
- `FTAN.X FPn` - Tangent
- `FATAN.X FPn` - Arc tangent
- `FLOGN.X FPn` - Natural logarithm
- `FETOX.X FPn` - e^x
- `FLOG10.X FPn` - Base-10 logarithm
- `FETOXM1.X FPn` - e^x - 1

#### Branch Operations
- `FBcc.W <label>` - Branch on condition
- `FDBcc Dn,<label>` - Decrement and branch
- `FScc <ea>` - Set on condition
- `FTRAPcc` - Trap on condition

#### Context Switching
- `FSAVE -(An)` - Save FPU state
- `FRESTORE (An)+` - Restore FPU state

### Data Formats

| Format | Size | Type | Range | Precision |
|--------|------|------|-------|-----------|
| `.B` | 8-bit | Integer | -128 to 127 | Exact |
| `.W` | 16-bit | Integer | -32768 to 32767 | Exact |
| `.L` | 32-bit | Integer | -2³¹ to 2³¹-1 | Exact |
| `.S` | 32-bit | IEEE 754 Single | ±1.4×10⁻⁴⁵ to ±3.4×10³⁸ | ~7 digits |
| `.D` | 64-bit | IEEE 754 Double | ±4.9×10⁻³²⁴ to ±1.8×10³⁰⁸ | ~15 digits |
| `.X` | 80-bit | IEEE 754 Extended | ±3.4×10⁻⁴⁹³² to ±1.2×10⁴⁹³² | ~19 digits |
| `.P` | 96-bit | Packed BCD | Platform specific | ~17 digits |

### FPU Registers

```
┌──────────────────────────────────────────┐
│  FP0-FP7: Data Registers (80-bit each)   │
│  - Internal format: IEEE 754 Extended    │
│  - Accessed via FMOVE, FMOVEM            │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  FPCR: Floating-Point Control Register   │
│  - Rounding mode                         │
│  - Exception enables                     │
│  - Precision control                     │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  FPSR: Floating-Point Status Register    │
│  - Condition codes (N, Z, I, NAN)        │
│  - Exception flags                       │
│  - Quotient byte                         │
│  - Accrued exceptions                    │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  FPIAR: FP Instruction Address Register  │
│  - Address of last FPU instruction       │
│  - Used for exception handling           │
└──────────────────────────────────────────┘
```

## Programming Examples

### Basic Math Operations

```assembly
; Calculate: result = (a + b) * c / d

    ; Load operands
    fmove.s a,fp0       ; Load a into FP0
    fmove.s b,fp1       ; Load b into FP1
    fmove.s c,fp2       ; Load c into FP2
    fmove.s d,fp3       ; Load d into FP3
    
    ; Perform calculation
    fadd.x fp1,fp0      ; FP0 = a + b
    fmul.x fp2,fp0      ; FP0 = (a + b) * c
    fdiv.x fp3,fp0      ; FP0 = ((a + b) * c) / d
    
    ; Store result
    fmove.s fp0,result  ; Store to memory
```

### Vector Operations

```assembly
; Normalize a 3D vector: v = v / |v|
; where |v| = sqrt(x² + y² + z²)

normalize_vector:
    ; Load components
    fmove.s vector_x,fp0
    fmove.s vector_y,fp1
    fmove.s vector_z,fp2
    
    ; Calculate magnitude squared
    fmove.x fp0,fp3     ; Save x
    fmul.x fp0,fp0      ; x²
    fmove.x fp1,fp4     ; Save y
    fmul.x fp1,fp1      ; y²
    fadd.x fp1,fp0      ; x² + y²
    fmove.x fp2,fp5     ; Save z
    fmul.x fp2,fp2      ; z²
    fadd.x fp2,fp0      ; x² + y² + z²
    
    ; Calculate magnitude
    fsqrt.x fp0         ; |v|
    
    ; Normalize
    fdiv.x fp0,fp3      ; x / |v|
    fdiv.x fp0,fp4      ; y / |v|
    fdiv.x fp0,fp5      ; z / |v|
    
    ; Store results
    fmove.s fp3,vector_x
    fmove.s fp4,vector_y
    fmove.s fp5,vector_z
    rts
```

### Matrix Multiplication (4x4)

```assembly
; Multiply two 4x4 matrices: C = A × B
matrix_multiply:
    movem.l d0-d7/a0-a6,-(sp)
    
    ; For each row of A
    moveq #0,d0         ; i = 0
.row_loop:
    ; For each column of B
    moveq #0,d1         ; j = 0
.col_loop:
    ; Initialize sum
    fmove.s #0.0,fp0
    
    ; For each element in row/column
    moveq #0,d2         ; k = 0
.inner_loop:
    ; Calculate indices
    move.l d0,d3
    lsl.l #4,d3         ; i * 16 (4 floats * 4 bytes)
    move.l d2,d4
    lsl.l #2,d4         ; k * 4
    add.l d4,d3         ; offset for A[i][k]
    
    move.l d2,d5
    lsl.l #4,d5         ; k * 16
    move.l d1,d6
    lsl.l #2,d6         ; j * 4
    add.l d6,d5         ; offset for B[k][j]
    
    ; Load and multiply
    fmove.s 0(a0,d3.l),fp1  ; A[i][k]
    fmul.s 0(a1,d5.l),fp1   ; * B[k][j]
    fadd.x fp1,fp0          ; sum += A[i][k] * B[k][j]
    
    ; Next k
    addq.l #1,d2
    cmp.l #4,d2
    blt.s .inner_loop
    
    ; Store result C[i][j]
    move.l d0,d3
    lsl.l #4,d3
    move.l d1,d4
    lsl.l #2,d4
    add.l d4,d3
    fmove.s fp0,0(a2,d3.l)
    
    ; Next j
    addq.l #1,d1
    cmp.l #4,d1
    blt.s .col_loop
    
    ; Next i
    addq.l #1,d0
    cmp.l #4,d0
    blt.s .row_loop
    
    movem.l (sp)+,d0-d7/a0-a6
    rts
```

### Context Switching

```assembly
; Save FPU state before task switch
save_fpu_context:
    ; Save all FPU registers
    fmovem.x fp0-fp7,-(sp)      ; Save all 8 FP registers (80 bytes)
    fmove.l fpcr,-(sp)          ; Save FPCR (4 bytes)
    fmove.l fpsr,-(sp)          ; Save FPSR (4 bytes)
    fmove.l fpiar,-(sp)         ; Save FPIAR (4 bytes)
    ; Total: 92 bytes
    rts

; Restore FPU state after task switch
restore_fpu_context:
    fmove.l (sp)+,fpiar         ; Restore FPIAR
    fmove.l (sp)+,fpsr          ; Restore FPSR
    fmove.l (sp)+,fpcr          ; Restore FPCR
    fmovem.x (sp)+,fp0-fp7      ; Restore all FP registers
    rts

; Alternative: Use FSAVE/FRESTORE (automatic)
save_with_fsave:
    fsave -(sp)                 ; Automatic context save
    rts

restore_with_frestore:
    frestore (sp)+              ; Automatic context restore
    rts
```

## Exception Handling

### FPU Exception Vectors

The FPU generates exceptions through the standard 68K exception mechanism:

| Vector | Address | Exception | Description |
|--------|---------|-----------|-------------|
| 48 | $C0 | BSUN | Branch/Set on Unordered |
| 49 | $C4 | INEX | Inexact Result |
| 50 | $C8 | DZ | Divide by Zero |
| 51 | $CC | UNFL | Underflow |
| 52 | $D0 | OPERR | Operand Error |
| 53 | $D4 | OVFL | Overflow |
| 54 | $D8 | SNAN | Signaling NaN |

### Exception Handler Example

```assembly
; Exception vector table
    org $400
    dc.l fpu_unimplemented  ; Vector 11: F-line (unimplemented FPU)
    
    org $C0
    dc.l fpu_bsun          ; Vector 48: Branch on unordered
    dc.l fpu_inexact       ; Vector 49: Inexact result
    dc.l fpu_divzero       ; Vector 50: Divide by zero
    dc.l fpu_underflow     ; Vector 51: Underflow
    dc.l fpu_operr         ; Vector 52: Operand error
    dc.l fpu_overflow      ; Vector 53: Overflow
    dc.l fpu_snan          ; Vector 54: Signaling NaN

; Divide by zero handler
fpu_divzero:
    movem.l d0-d7/a0-a6,-(sp)
    
    ; Log error
    lea divzero_msg,a0
    bsr print_error
    
    ; Get faulting instruction address
    fmove.l fpiar,d0
    bsr print_hex
    
    ; Clear exception
    fmove.l fpsr,d0
    andi.l #$FFFF0000,d0    ; Clear exception bits
    fmove.l d0,fpsr
    
    ; Return NaN as result (optional)
    ; fmove.s #$7FC00000,fp0  ; QNaN
    
    movem.l (sp)+,d0-d7/a0-a6
    rte

divzero_msg:
    dc.b "FPU Divide by Zero at $",0
```

## Performance Considerations

### Cycle Counts (Approximate)

| Operation | Cycles | Notes |
|-----------|--------|-------|
| FMOVE (reg-reg) | 2-4 | Format conversion adds cycles |
| FMOVE (mem-reg) | 4-8 | Plus memory access time |
| FADD/FSUB | 4-8 | Extended precision |
| FMUL | 6-12 | Depends on operand size |
| FDIV | 12-24 | Slowest basic operation |
| FSQRT | 16-32 | Iterative algorithm |
| FSIN/FCOS | 32-64 | CORDIC algorithm |
| FLOGN/FETOX | 32-64 | Series expansion |

### Optimization Tips

1. **Keep values in FP registers** - Avoid unnecessary memory transfers
2. **Use extended precision internally** - Convert only at I/O boundaries
3. **Pipeline operations** - Use multiple FP registers for parallel work
4. **Avoid denormalized numbers** - They can be significantly slower
5. **Use FMOVECR for constants** - Faster than memory loads

Example optimization:

```assembly
; ❌ Slow - repeated memory access
    fmul.s #3.14159,fp0
    fmul.s #3.14159,fp1
    fmul.s #3.14159,fp2

; ✅ Fast - load constant once
    fmovecr #0,fp7      ; Load π to FP7
    fmul.x fp7,fp0      ; Use from register
    fmul.x fp7,fp1
    fmul.x fp7,fp2
```

## Synthesis Considerations

### Resource Usage (Typical on Cyclone V)

| Component | Without FPU | With FPU | Increase |
|-----------|-------------|----------|----------|
| ALMs | ~3500 | ~4500 | +29% |
| Memory Bits | ~8000 | ~12000 | +50% |
| DSP Blocks | 4 | 8 | +100% |
| fMAX | 50 MHz | 48 MHz | -4% |

### Timing Considerations

The FPU is fully pipelined and should meet timing at 50+ MHz on modern FPGAs. Critical paths:

1. FPU ALU datapath (especially multiplier)
2. Register file access
3. CIR protocol state machine
4. Exception flag generation

If timing fails:
- Reduce clock speed slightly
- Enable more synthesis optimization
- Pipeline user logic interfacing with CPU
- Consider Altera/Intel DSP block inference settings

## Debugging

### Common Issues

#### 1. FPU Instructions Cause F-Line Exception

**Symptom**: F-line exception (vector $2C/$B0) when executing FPU instructions

**Causes**:
- FPU_Enable = 0 (FPU disabled)
- CPU not in 68020 mode (cpu != 2'b11)
- Missing FPU VHDL files in project

**Solution**:
```verilog
tg68k #(
    .FPU_Enable(1)      // Must be 1
) cpu (
    .cpu(2'b11),        // Must be 68020
    // ...
);
```

#### 2. Incorrect Results

**Symptom**: FPU operations return wrong values

**Causes**:
- Wrong rounding mode in FPCR
- Using wrong data format suffix
- Not handling denormalized numbers

**Solution**:
```assembly
; Set rounding mode
fmove.l #$0000,fpcr     ; Round to nearest (default)

; Use correct format
fadd.x fp1,fp0          ; Extended precision (best accuracy)
; Not: fadd.s fp1,fp0   ; Single precision (less accurate)
```

#### 3. Exceptions Not Firing

**Symptom**: Expected exceptions don't occur

**Causes**:
- Exceptions disabled in FPCR
- Exception vectors not initialized
- Wrong exception enable bits

**Solution**:
```assembly
; Enable divide-by-zero exceptions
fmove.l fpcr,d0
ori.l #$0400,d0         ; Set DZ enable bit
fmove.l d0,fpcr

; Initialize exception vector
move.l #fpu_divzero,$C8 ; Vector 50
```

### Debug Techniques

#### 1. Examine FPU State

```assembly
debug_fpu:
    ; Dump all FPU registers
    fmovem.x fp0-fp7,fpu_dump
    fmove.l fpcr,fpcr_dump
    fmove.l fpsr,fpsr_dump
    fmove.l fpiar,fpiar_dump
    rts

fpu_dump:    ds.b 80    ; 8 × 80-bit registers
fpcr_dump:   ds.l 1
fpsr_dump:   ds.l 1
fpiar_dump:  ds.l 1
```

#### 2. Single-Step FPU Operations

```assembly
test_fpu:
    fmove.s #1.0,fp0
    nop                 ; Set breakpoint here
    fmove.s #2.0,fp1
    nop
    fadd.x fp1,fp0
    nop                 ; Check result here
    fmove.s fp0,result
    nop
```

#### 3. Verify Constants

```assembly
; Test known values
test_constants:
    fmovecr #0,fp0      ; π = 3.14159265...
    fcmp.s #3.14159,fp0
    fbne.w error        ; Should be equal (within tolerance)
    
    fmovecr #11,fp1     ; log₁₀(2) = 0.30103...
    fcmp.s #0.30103,fp1
    fbne.w error
    
    ; Success
    rts
    
error:
    ; FPU constant ROM may be corrupted
    bra halt
```

## Integration Checklist

- [ ] Add all TG68K VHDL files to project
- [ ] Set FPU_Enable = 1 in tg68k instantiation
- [ ] Set CPU mode to 68020 (cpu = 2'b11)
- [ ] Connect clock, reset, and bus signals
- [ ] Initialize FPU exception vectors ($C0-$D8)
- [ ] Set up FPCR for desired rounding mode
- [ ] Test with simple operations (FADD, FMUL)
- [ ] Verify exception handling
- [ ] Test FSAVE/FRESTORE for context switching
- [ ] Perform timing analysis
- [ ] Test in your target application

## FAQ

**Q: Can I use the FPU with 68000 or 68010 mode?**
A: No, the FPU requires 68020 mode for the coprocessor interface.

**Q: What's the resource overhead of the FPU?**
A: Approximately 15-20% more logic and 100% more DSP blocks.

**Q: Is the FPU IEEE 754 compliant?**
A: Yes, fully compliant for single, double, and extended precision.

**Q: Can I disable specific FPU instructions?**
A: Not selectively, but you can disable the entire FPU with FPU_Enable = 0.

**Q: Does the FPU support packed decimal (P) format?**
A: Yes, through the TG68K_FPU_PackedDecimal module.

**Q: Can multiple FPU operations run in parallel?**
A: No, the FPU is single-issue. However, the CPU can continue integer operations while waiting for long FPU ops.

**Q: How do I handle FPU in an interrupt handler?**
A: Use FSAVE/FRESTORE to preserve FPU state if the interrupt handler uses the FPU.

**Q: What happens on FPU exception if no handler is installed?**
A: The CPU will execute the bus error or illegal instruction handler, depending on the exception type.

## Additional Resources

- MC68881/68882 User's Manual (Motorola)
- MC68020 User's Manual (Motorola)
- IEEE 754 Floating-Point Standard
- TG68K_FPU_Documentation.md (detailed FPU internals)
- TG68K_FPU_Quick_Reference.md (instruction reference)

## Support

For issues or questions:
1. Check the VHDL source comments
2. Review the provided documentation
3. Test with minimal examples
4. Check FPGA synthesis warnings/errors
5. Verify clock timing constraints

---

**Version**: 1.0
**Last Updated**: 2025-01-20
**Authors**: TG68K Development Team
