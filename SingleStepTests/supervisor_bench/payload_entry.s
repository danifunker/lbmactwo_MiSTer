| payload_entry.s — entry shim for the flat payload binary.
| Loaded by boot_stub at $00040000 and called via JMP. We're still
| in supervisor mode with all interrupts masked. For now we just paint
| a visible "PAYLOAD OK" banner and hang. Step D will install a real
| VBR + supervisor stack and call bench_main(); we're not there yet.

ROW_BYTES = 80     | must match boot_stub_minimal.s (640px @ 1bpp)

    .text
    .global _payload_start
_payload_start:
    | --- Clear screen to black so the "BENCH OK" from boot is gone. ---
    move.l  0x0824.l, %a0
    move.l  %a0, %d0
    beq     .hang
    cmp.l   #0x00100000, %d0
    blo     .hang
    move.l  #(128*1024/4)-1, %d0
1:  move.l  #0xFFFFFFFF, (%a0)+
    dbra    %d0, 1b

    | --- Render "PAYLOAD OK" at row 16, byte column 4. ---
    move.l  0x0824.l, %a0
    add.l   #(16 * ROW_BYTES + 4), %a0
    lea     font_data(%pc), %a1
    moveq   #9, %d0                | 10 chars total
.char_loop:
    move.l  %a0, %a2
    moveq   #7, %d1                | 8 rows per glyph
.row_loop:
    move.b  (%a1)+, %d2
    not.b   %d2
    move.b  %d2, (%a2)
    lea     ROW_BYTES(%a2), %a2
    dbra    %d1, .row_loop
    addq.l  #1, %a0
    dbra    %d0, .char_loop

.hang:
    | Step D placeholder: real impl sets up VBR + sup-stack + calls bench_main.
    | move.l  #sup_stack_top, %sp
    | jsr     bench_main
1:  bra.s   1b

| 8x8 font (1 = letter pixel, NOT'd at render time → white on black).
font_data:
    | 'P'
    .byte 0x7C, 0x42, 0x42, 0x7C, 0x40, 0x40, 0x40, 0x00
    | 'A'
    .byte 0x3C, 0x42, 0x42, 0x7E, 0x42, 0x42, 0x42, 0x00
    | 'Y'
    .byte 0x42, 0x42, 0x42, 0x3C, 0x18, 0x18, 0x18, 0x00
    | 'L'
    .byte 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x7E, 0x00
    | 'O'
    .byte 0x3C, 0x42, 0x42, 0x42, 0x42, 0x42, 0x3C, 0x00
    | 'A'
    .byte 0x3C, 0x42, 0x42, 0x7E, 0x42, 0x42, 0x42, 0x00
    | 'D'
    .byte 0x78, 0x44, 0x42, 0x42, 0x42, 0x44, 0x78, 0x00
    | ' '
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    | 'O'
    .byte 0x3C, 0x42, 0x42, 0x42, 0x42, 0x42, 0x3C, 0x00
    | 'K'
    .byte 0x42, 0x44, 0x48, 0x70, 0x48, 0x44, 0x42, 0x00

    .bss
    .align 4
sup_stack:
    .space  8192
sup_stack_top:

    .data
    .align 4
    .global vbr_table
vbr_table:
    .space  1024
