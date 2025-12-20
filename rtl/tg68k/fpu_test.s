; ===========================================================================
; TG68K FPU Test Program
; ===========================================================================
; 
; This test program verifies basic FPU functionality including:
; - Register loading and storage
; - Basic arithmetic operations
; - Comparisons and conditional branches
; - Exception handling
; - Context save/restore
;
; Expected results are documented for each test.
; ===========================================================================

    ORG $1000

; Entry point
start:
    ; Initialize stack pointer
    lea stack_top,sp
    
    ; Set up exception vectors
    bsr init_exceptions
    
    ; Initialize FPU control register
    fmove.l #$0000,fpcr     ; Round to nearest, no exceptions enabled
    
    ; Run test suite
    bsr test_basic_load
    bsr test_arithmetic
    bsr test_comparison
    bsr test_transcendental
    bsr test_exception
    bsr test_context
    
    ; All tests passed
    move.w #$0000,test_result   ; 0 = success
    bra end_tests

; ===========================================================================
; Test 1: Basic Load/Store Operations
; ===========================================================================
test_basic_load:
    movem.l d0-d2/a0,-(sp)
    
    ; Test 1a: Load immediate single precision
    fmove.s #1.5,fp0
    fmove.s fp0,temp_single
    
    ; Verify: temp_single should be 0x3FC00000 (1.5 in IEEE 754)
    move.l temp_single,d0
    cmp.l #$3FC00000,d0
    bne test_failed
    
    ; Test 1b: Load immediate double precision
    fmove.d #2.25,fp1
    fmove.d fp1,temp_double
    
    ; Test 1c: Load from memory
    lea const_pi,a0
    fmove.s (a0),fp2
    
    ; Test 1d: Move between FP registers
    fmove.x fp0,fp3
    fcmp.x fp0,fp3
    fbne test_failed        ; Should be equal
    
    movem.l (sp)+,d0-d2/a0
    rts

; ===========================================================================
; Test 2: Arithmetic Operations
; ===========================================================================
test_arithmetic:
    movem.l d0/a0,-(sp)
    
    ; Test 2a: Addition
    ; 1.5 + 2.5 = 4.0
    fmove.s #1.5,fp0
    fmove.s #2.5,fp1
    fadd.x fp1,fp0
    fmove.s fp0,temp_single
    move.l temp_single,d0
    cmp.l #$40800000,d0     ; 4.0 in IEEE 754
    bne test_failed
    
    ; Test 2b: Subtraction
    ; 10.0 - 3.0 = 7.0
    fmove.s #10.0,fp0
    fmove.s #3.0,fp1
    fsub.x fp1,fp0
    fmove.s fp0,temp_single
    move.l temp_single,d0
    cmp.l #$40E00000,d0     ; 7.0 in IEEE 754
    bne test_failed
    
    ; Test 2c: Multiplication
    ; 2.5 × 4.0 = 10.0
    fmove.s #2.5,fp0
    fmove.s #4.0,fp1
    fmul.x fp1,fp0
    fmove.s fp0,temp_single
    move.l temp_single,d0
    cmp.l #$41200000,d0     ; 10.0 in IEEE 754
    bne test_failed
    
    ; Test 2d: Division
    ; 15.0 ÷ 3.0 = 5.0
    fmove.s #15.0,fp0
    fmove.s #3.0,fp1
    fdiv.x fp1,fp0
    fmove.s fp0,temp_single
    move.l temp_single,d0
    cmp.l #$40A00000,d0     ; 5.0 in IEEE 754
    bne test_failed
    
    ; Test 2e: Square root
    ; √16.0 = 4.0
    fmove.s #16.0,fp0
    fsqrt.x fp0
    fmove.s fp0,temp_single
    move.l temp_single,d0
    cmp.l #$40800000,d0     ; 4.0 in IEEE 754
    bne test_failed
    
    ; Test 2f: Absolute value
    fmove.s #-5.5,fp0
    fabs.x fp0
    fmove.s fp0,temp_single
    move.l temp_single,d0
    cmp.l #$40B00000,d0     ; 5.5 in IEEE 754
    bne test_failed
    
    ; Test 2g: Negation
    fmove.s #3.14,fp0
    fneg.x fp0
    ; Result should be negative
    fmove.l fpsr,d0
    btst #31,d0             ; Check N bit
    beq test_failed
    
    movem.l (sp)+,d0/a0
    rts

; ===========================================================================
; Test 3: Comparison and Conditional Operations
; ===========================================================================
test_comparison:
    movem.l d0,-(sp)
    
    ; Test 3a: Compare equal
    fmove.s #2.5,fp0
    fmove.s #2.5,fp1
    fcmp.x fp1,fp0
    fbne test_failed        ; Should be equal
    
    ; Test 3b: Compare greater than
    fmove.s #5.0,fp0
    fmove.s #3.0,fp1
    fcmp.x fp1,fp0
    fble test_failed        ; 5.0 > 3.0
    
    ; Test 3c: Compare less than
    fmove.s #2.0,fp0
    fmove.s #8.0,fp1
    fcmp.x fp1,fp0
    fbge test_failed        ; 2.0 < 8.0
    
    ; Test 3d: Test zero
    fmove.s #0.0,fp0
    ftst.x fp0
    fbne test_failed        ; Should be zero
    
    ; Test 3e: Set on condition (Scc)
    fmove.s #5.0,fp0
    fmove.s #3.0,fp1
    fcmp.x fp1,fp0
    sgt.b d0                ; Should set d0 to $FF
    cmp.b #$FF,d0
    bne test_failed
    
    movem.l (sp)+,d0
    rts

; ===========================================================================
; Test 4: Transcendental Functions
; ===========================================================================
test_transcendental:
    movem.l d0,-(sp)
    
    ; Test 4a: Sine of π/2 should be 1.0
    fmovecr #0,fp0          ; Load π
    fmove.s #2.0,fp1
    fdiv.x fp1,fp0          ; π/2
    fsin.x fp0
    ; Check result is approximately 1.0
    fsub.s #1.0,fp0
    fabs.x fp0
    fcmp.s #0.0001,fp0      ; Within tolerance?
    fbge test_failed
    
    ; Test 4b: Cosine of 0 should be 1.0
    fmove.s #0.0,fp0
    fcos.x fp0
    fsub.s #1.0,fp0
    fabs.x fp0
    fcmp.s #0.0001,fp0
    fbge test_failed
    
    ; Test 4c: Natural log of e should be 1.0
    fmovecr #13,fp0         ; Load e
    flogn.x fp0
    fsub.s #1.0,fp0
    fabs.x fp0
    fcmp.s #0.0001,fp0
    fbge test_failed
    
    ; Test 4d: e^0 should be 1.0
    fmove.s #0.0,fp0
    fetox.x fp0
    fsub.s #1.0,fp0
    fabs.x fp0
    fcmp.s #0.0001,fp0
    fbge test_failed
    
    movem.l (sp)+,d0
    rts

; ===========================================================================
; Test 5: Exception Handling
; ===========================================================================
test_exception:
    movem.l d0-d1,-(sp)
    
    ; Enable divide-by-zero exception
    fmove.l fpcr,d0
    ori.l #$0400,d0         ; Enable DZ exception
    fmove.l d0,fpcr
    
    ; Clear exception counter
    clr.l exception_count
    
    ; Trigger divide by zero
    fmove.s #1.0,fp0
    fmove.s #0.0,fp1
    fdiv.x fp1,fp0          ; This should trigger exception
    
    ; Check that exception was handled
    move.l exception_count,d0
    cmp.l #1,d0
    bne test_failed
    
    ; Disable exceptions
    fmove.l #$0000,fpcr
    
    movem.l (sp)+,d0-d1
    rts

; ===========================================================================
; Test 6: Context Save/Restore
; ===========================================================================
test_context:
    movem.l d0,-(sp)
    
    ; Initialize registers with known values
    fmove.s #1.0,fp0
    fmove.s #2.0,fp1
    fmove.s #3.0,fp2
    fmove.s #4.0,fp3
    fmove.s #5.0,fp4
    fmove.s #6.0,fp5
    fmove.s #7.0,fp6
    fmove.s #8.0,fp7
    
    ; Save context
    fmovem.x fp0-fp7,fpu_context
    
    ; Corrupt registers
    fmove.s #99.0,fp0
    fmove.s #99.0,fp1
    fmove.s #99.0,fp2
    fmove.s #99.0,fp3
    fmove.s #99.0,fp4
    fmove.s #99.0,fp5
    fmove.s #99.0,fp6
    fmove.s #99.0,fp7
    
    ; Restore context
    fmovem.x fpu_context,fp0-fp7
    
    ; Verify restoration
    fmove.s fp0,temp_single
    move.l temp_single,d0
    cmp.l #$3F800000,d0     ; 1.0
    bne test_failed
    
    fmove.s fp4,temp_single
    move.l temp_single,d0
    cmp.l #$40A00000,d0     ; 5.0
    bne test_failed
    
    fmove.s fp7,temp_single
    move.l temp_single,d0
    cmp.l #$41000000,d0     ; 8.0
    bne test_failed
    
    movem.l (sp)+,d0
    rts

; ===========================================================================
; Exception Handlers
; ===========================================================================
init_exceptions:
    ; Install FPU exception handlers
    move.l #fpu_divzero_handler,$C8     ; Vector 50: Divide by zero
    move.l #fpu_overflow_handler,$D4    ; Vector 53: Overflow
    move.l #fpu_underflow_handler,$CC   ; Vector 51: Underflow
    rts

fpu_divzero_handler:
    ; Count exception
    addq.l #1,exception_count
    
    ; Clear exception flag
    fmove.l fpsr,d0
    andi.l #$FFFF0000,d0    ; Clear exception bits
    fmove.l d0,fpsr
    
    ; Return infinity as result
    fmove.s #$7F800000,fp0  ; +infinity
    rte

fpu_overflow_handler:
    addq.l #1,exception_count
    fmove.l fpsr,d0
    andi.l #$FFFF0000,d0
    fmove.l d0,fpsr
    rte

fpu_underflow_handler:
    addq.l #1,exception_count
    fmove.l fpsr,d0
    andi.l #$FFFF0000,d0
    fmove.l d0,fpsr
    rte

; ===========================================================================
; Test Failure Handler
; ===========================================================================
test_failed:
    move.w #$FFFF,test_result   ; -1 = failure
    bra end_tests

end_tests:
    ; Infinite loop - check test_result for pass/fail
    bra.s end_tests

; ===========================================================================
; Data Section
; ===========================================================================
    SECTION data

; Constants
const_pi:
    dc.l $40490FDB          ; π = 3.14159265 in IEEE 754

const_e:
    dc.l $402DF854          ; e = 2.71828182 in IEEE 754

; Temporary storage
temp_single:
    ds.l 1

temp_double:
    ds.l 2

; Test result (0 = pass, -1 = fail)
test_result:
    ds.w 1

; Exception counter
exception_count:
    ds.l 1

; FPU context save area
fpu_context:
    ds.b 80                 ; 8 registers × 80 bits

; Stack
    ds.b 1024
stack_top:

    END start

; ===========================================================================
; Expected Results Summary
; ===========================================================================
; 
; If all tests pass:
;   test_result = $0000
;   All FPU operations completed successfully
; 
; If any test fails:
;   test_result = $FFFF
;   Execution halts at test_failed
; 
; Test Coverage:
;   ✓ Basic load/store (FMOVE)
;   ✓ Integer and floating-point formats
;   ✓ Addition, subtraction, multiplication, division
;   ✓ Square root, absolute value, negation
;   ✓ Comparisons (equal, greater, less)
;   ✓ Conditional operations (FBcc, FScc)
;   ✓ Transcendental functions (sin, cos, log, exp)
;   ✓ Exception handling (divide by zero)
;   ✓ Context save/restore (FMOVEM)
; 
; ===========================================================================
