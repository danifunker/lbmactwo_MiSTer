| recovery.s — setjmp/longjmp-style test recovery via VBR.
|
| install_vbr():
|   1. Read the current VBR (set by ROM at boot).
|   2. Copy all 256 entries to our own vbr_table.
|   3. Overwrite CPU exception vectors (2..15), interrupt autovectors
|      (24..31), and TRAP vectors (32..47) with recovery_stub.
|   4. Leave Line A (vector 10) alone — _Write trap goes through it.
|   5. MOVEC our table to VBR.
|
| invoke_test_with_recovery(entry):
|   D0 returns 0 on normal RTS, non-zero (= exception vector) if a
|   handler fired and longjmp'd us back. Caller treats non-zero as
|   "test crashed, capture what we have".

    .text
    .global install_vbr
    .global invoke_test_with_recovery

| Module-private data symbols.
    .data
    .align 4
g_resume_sp:    .long 0
g_resume_pc:    .long 0
g_last_vector:  .long 0     | set by recovery_stub before jumping back

    .bss
    .align 4
vbr_table:      .space 1024     | 256 vectors * 4 bytes

    .text

| ---- install_vbr ----------------------------------------------------
install_vbr:
    movem.l %d0-%d2/%a0-%a2, -(%sp)

    | 0x4E7A 8801: movec VBR, A0 (bit 15 of operand word = An, bits 11..0 = $801 for VBR)
    .short  0x4E7A
    .short  0x8801
    lea     vbr_table, %a1
    move.w  #255, %d0
1:
    move.l  (%a0)+, (%a1)+
    dbra    %d0, 1b

    | Override CPU exception vectors 2..15 with recovery_stub, but
    | keep vector 10 (Line A) pointing to whatever ROM set up.
    lea     vbr_table, %a1
    move.l  #recovery_stub_v2,  8(%a1)      | bus error
    move.l  #recovery_stub_v3,  12(%a1)     | address error
    move.l  #recovery_stub_v4,  16(%a1)     | illegal instruction
    move.l  #recovery_stub_v5,  20(%a1)     | zero divide
    move.l  #recovery_stub_v6,  24(%a1)     | CHK
    move.l  #recovery_stub_v7,  28(%a1)     | TRAPV
    move.l  #recovery_stub_v8,  32(%a1)     | privilege violation
    move.l  #recovery_stub_v9,  36(%a1)     | trace
    | vector 10 (Line A, offset 40) intentionally left as ROM default
    move.l  #recovery_stub_v11, 44(%a1)     | Line F
    move.l  #recovery_stub_v12, 48(%a1)
    move.l  #recovery_stub_v13, 52(%a1)
    move.l  #recovery_stub_v14, 56(%a1)
    move.l  #recovery_stub_v15, 60(%a1)

    | Autovector interrupts 1..7 (vectors 25..31). 60Hz tick is
    | usually autovector 1. We just recover from any.
    move.l  #recovery_stub_v25, (25*4)(%a1)
    move.l  #recovery_stub_v26, (26*4)(%a1)
    move.l  #recovery_stub_v27, (27*4)(%a1)
    move.l  #recovery_stub_v28, (28*4)(%a1)
    move.l  #recovery_stub_v29, (29*4)(%a1)
    move.l  #recovery_stub_v30, (30*4)(%a1)
    move.l  #recovery_stub_v31, (31*4)(%a1)

    | Now switch VBR to our table.
    lea     vbr_table, %a0
    | 0x4E7B 8801: movec A0, VBR
    .short  0x4E7B
    .short  0x8801

    movem.l (%sp)+, %d0-%d2/%a0-%a2
    rts

| ---- recovery_stub_vN ----------------------------------------------
| One stub per vector so we can record which vector fired. Each
| stub loads its vector number into g_last_vector and jumps to the
| common recovery_core.
    .macro RSTUB n
recovery_stub_v\n:
    move.l  #\n, g_last_vector
    bra     recovery_core
    .endm

    RSTUB 2
    RSTUB 3
    RSTUB 4
    RSTUB 5
    RSTUB 6
    RSTUB 7
    RSTUB 8
    RSTUB 9
    RSTUB 11
    RSTUB 12
    RSTUB 13
    RSTUB 14
    RSTUB 15
    RSTUB 25
    RSTUB 26
    RSTUB 27
    RSTUB 28
    RSTUB 29
    RSTUB 30
    RSTUB 31

| Common recovery: restore SP to where the bench was waiting, mask
| interrupts, set D0 to the vector that fired (non-zero), and jump
| to g_resume_pc. The bench thinks invoke_test_with_recovery() just
| returned with that value.
recovery_core:
    move.l  g_resume_sp, %sp
    move.w  #0x2700, %sr
    move.l  g_last_vector, %d0
    move.l  g_resume_pc, %a0
    jmp     (%a0)

| ---- invoke_test_with_recovery -------------------------------------
| C call: int invoke_test_with_recovery(u8 *entry);
| Returns 0 on normal RTS, vector# (e.g. 5 for /0) on exception.
| Direct framebuffer markers — write one byte to a known offset of the
| framebuffer so we can see exactly how far we got, independent of C.
| ScrnBase at low-mem $0824, byte offset (row 52 * 80 + col 16) = 4176.
| Writing 0x00 = solid white pixel block, 0xFF = black; we write 0x00.
| Five distinct rows here so each phase paints a distinct dot column.
| DOT macro uses A1 so it doesn't disturb the A0 we're setting up for jsr.
    .macro DOT col
    move.l  0x0824, %a1
    add.l   #(52 * 80 + 16 + \col), %a1
    move.b  #0x00, (%a1)
    .endm

invoke_test_with_recovery:
    DOT 0
    movem.l %d2-%d7/%a2-%a6, -(%sp)
    DOT 1
    lea     .resume(%pc), %a0
    move.l  %a0, g_resume_pc
    move.l  %sp, g_resume_sp
    DOT 2
    move.l  4+(11*4)(%sp), %a0      | entry arg (past saved regs)
    DOT 3
    jsr     (%a0)
    DOT 4
    moveq   #0, %d0                  | normal return
.resume:
    DOT 5
    movem.l (%sp)+, %d2-%d7/%a2-%a6
    rts
