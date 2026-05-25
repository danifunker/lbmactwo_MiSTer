| payload_entry.s — IOTest payload entry shim.
|
| Loads the boot handoff (driver refnum + drive number) from $00041000,
| clears the screen, paints a banner, then calls bench_main() in C.

.ifndef ROW_BYTES
    ROW_BYTES = 80
.endif

    .text
    .global _payload_start
_payload_start:
    move.w  #0x2700, %sr
    move.l  #0x00100000, %sp              | 1 MB high — generous stack

    | --- Load handoff slot ($00041000: refnum word, drive word) ---
    move.w  0x00041000.l, %d0
    move.w  %d0, g_handoff_refnum
    move.w  0x00041002.l, %d0
    move.w  %d0, g_handoff_drive

    | --- Wipe screen ---
    move.l  0x0824.l, %a4
    move.l  %a4, %d0
    beq     .hang
    cmp.l   #0x00100000, %d0
    blo     .hang
    move.l  %a4, %a0
    move.l  #(128*1024/4)-1, %d0
1:  move.l  #0xFFFFFFFF, (%a0)+
    dbra    %d0, 1b

    | --- Startup marker: "IOTEFT" placeholder banner at pixel row 56,
    | col 60. Painted right after the screen wipe so the operator sees
    | the payload has started executing C even before bench_main
    | finishes initializing JsonlWriter. Lives at the bottom-right so
    | it doesn't collide with bench_main's row-4 paint_string banner
    | ("IOTEST: DISK I/O BENCH") or the row-60 progress counter. ---
    move.l  %a4, %a0
    add.l   #(56 * ROW_BYTES + 60), %a0
    lea     banner(%pc), %a1
    moveq   #5, %d0
    bsr     draw_string_n_d0

    jsr     bench_main

    | --- Paint "DONE" at row 60 col 4 ---
    move.l  0x0824.l, %a4
    move.l  %a4, %a0
    add.l   #(60 * ROW_BYTES + 4), %a0
    lea     done_str(%pc), %a1
    moveq   #3, %d0
    bsr     draw_string_n_d0

.hang:
1:  bra.s   1b

| --------------------------------------------------------------------
| Globals exported to C (signed words to match Mac OS conventions).
| --------------------------------------------------------------------
    .data
    .align 2
    .global g_handoff_refnum
    .global g_handoff_drive
g_handoff_refnum:   .word 0
g_handoff_drive:    .word 0

    .text

| --------------------------------------------------------------------
| paint_progress(idx, total) — same calling convention as the CPU bench
| variant. Paints a 4-hex-digit running counter at row 60 col 32.
| --------------------------------------------------------------------
    | paint_progress / draw_glyph_d0 are callable from C, so they must
    | preserve the M68K SysV callee-save set (D2-D7, A2-A6). The early
    | version trashed D3/D4 (paint_progress loop counters) and A2/D2
    | (draw_glyph_d0 scratch). When gcc happened to keep `paint_string`
    | in A2 across a paint_progress() call from bench_main, A2 came back
    | holding the framebuffer position the glyph painter advanced to —
    | which then bus-errored the very next `jsr (%a2)` since VRAM is not
    | executable code. (MAME-only on the iotest size that exposed it;
    | hardware double-faulted into a reset.) Save the callee-saves with
    | movem on entry and restore before rts.
    .global paint_progress
paint_progress:
    movem.l %d3-%d4, -(%sp)              | callee-save
    move.l  0x0824.l, %a0
    add.l   #(60 * ROW_BYTES + 32), %a0
    move.l  12(%sp), %d3                 | +8 for the pushed regs
    moveq   #3, %d4
.pp_loop:
    move.l  %d3, %d0
    rol.w   #4, %d0
    move.w  %d0, %d3
    andi.l  #0xF, %d0
    bsr     draw_glyph_d0
    addq.l  #1, %a0
    dbra    %d4, .pp_loop
    movem.l (%sp)+, %d3-%d4
    rts

| --------------------------------------------------------------------
| Local helpers: draw_string_n_d0 (length+1 in d0), draw_glyph_d0
| --------------------------------------------------------------------
draw_string_n_d0:
    move.l  %a0, %a3
.dsn_char:
    move.l  %a3, %a2
    moveq   #7, %d1
.dsn_row:
    move.b  (%a1)+, %d2
    not.b   %d2
    move.b  %d2, (%a2)
    lea     ROW_BYTES(%a2), %a2
    dbra    %d1, .dsn_row
    addq.l  #1, %a3
    dbra    %d0, .dsn_char
    rts

    | Also callable indirectly from C via paint_progress -> bsr here.
    | Uses A2 + D2 as scratch (both callee-save), so push/pop them.
draw_glyph_d0:
    movem.l %d2/%a2, -(%sp)
    lea     hex_font(%pc), %a1
    lsl.l   #3, %d0
    adda.l  %d0, %a1
    move.l  %a0, %a2
    moveq   #7, %d1
1:  move.b  (%a1)+, %d2
    not.b   %d2
    move.b  %d2, (%a2)
    lea     ROW_BYTES(%a2), %a2
    dbra    %d1, 1b
    movem.l (%sp)+, %d2/%a2
    rts

banner:
    .byte 0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x00   | I (use B-shape filled bar — placeholder)
    .byte 0x3C,0x42,0x40,0x40,0x40,0x42,0x3C,0x00   | O
    .byte 0x7E,0x10,0x10,0x10,0x10,0x10,0x10,0x00   | T
    .byte 0x7E,0x40,0x40,0x7C,0x40,0x40,0x7E,0x00   | E
    .byte 0x7E,0x40,0x40,0x40,0x40,0x40,0x40,0x00   | F (placeholder for 'S')
    .byte 0x7E,0x10,0x10,0x10,0x10,0x10,0x10,0x00   | T

done_str:
    .byte 0x78,0x44,0x42,0x42,0x42,0x44,0x78,0x00   | D
    .byte 0x3C,0x42,0x40,0x40,0x40,0x42,0x3C,0x00   | O
    .byte 0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x00   | N (placeholder)
    .byte 0x7E,0x40,0x40,0x7C,0x40,0x40,0x7E,0x00   | E

hex_font:
    .byte 0x3C,0x42,0x46,0x4A,0x52,0x62,0x3C,0x00   | 0
    .byte 0x18,0x28,0x08,0x08,0x08,0x08,0x3E,0x00   | 1
    .byte 0x3C,0x42,0x02,0x0C,0x30,0x40,0x7E,0x00   | 2
    .byte 0x3C,0x42,0x02,0x1C,0x02,0x42,0x3C,0x00   | 3
    .byte 0x04,0x0C,0x14,0x24,0x7E,0x04,0x04,0x00   | 4
    .byte 0x7E,0x40,0x7C,0x02,0x02,0x42,0x3C,0x00   | 5
    .byte 0x1C,0x20,0x40,0x7C,0x42,0x42,0x3C,0x00   | 6
    .byte 0x7E,0x02,0x04,0x08,0x10,0x20,0x20,0x00   | 7
    .byte 0x3C,0x42,0x42,0x3C,0x42,0x42,0x3C,0x00   | 8
    .byte 0x3C,0x42,0x42,0x3E,0x02,0x04,0x38,0x00   | 9
    .byte 0x3C,0x42,0x42,0x7E,0x42,0x42,0x42,0x00   | A
    .byte 0x7C,0x42,0x42,0x7C,0x42,0x42,0x7C,0x00   | B
    .byte 0x3C,0x42,0x40,0x40,0x40,0x42,0x3C,0x00   | C
    .byte 0x78,0x44,0x42,0x42,0x42,0x44,0x78,0x00   | D
    .byte 0x7E,0x40,0x40,0x7C,0x40,0x40,0x7E,0x00   | E
    .byte 0x7E,0x40,0x40,0x7C,0x40,0x40,0x40,0x00   | F
