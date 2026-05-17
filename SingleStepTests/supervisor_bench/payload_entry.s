| payload_entry.s — entry shim for the flat payload binary.
| Loaded at $00040000 by boot_stub. Sets up supervisor stack, VBR,
| then calls bench_main(). See Step D.

    .text
    .global _payload_start
_payload_start:
    | Step D: confirm S=1, install vector table at vbr_table,
    | switch SP to sup_stack_top, MOVEC into VBR.
    | Stub: just call bench_main and halt.
    move.l  #sup_stack_top, %sp
    jsr     bench_main
1:  bra.s   1b

    .bss
    .align 4
sup_stack:
    .space  8192
sup_stack_top:

    .data
    .align 4
    .global vbr_table
vbr_table:
    .space  1024                  | 256 vectors × 4 bytes (filled at runtime)
