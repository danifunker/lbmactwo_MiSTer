| boot_stub.s — HFS boot block (≤1024 bytes, lands at floppy offset 0)
|
| Layout per Inside Macintosh: Files, "Boot Blocks":
|   +0x00  bbID         'LK'
|   +0x02  bbEntry      6 bytes of 68k (BRA.W startup + pad)
|   +0x08  bbVersion    word
|   +0x0A  bbPageFlags  word
|   +0x0C  bbSysName    pstr[15]
|   +0x1B  bbShellName  pstr[15]
|   +0x2A  bbDbg1Name   pstr[15]
|   +0x39  bbDbg2Name   pstr[15]
|   +0x48  bbScreenName pstr[15]
|   +0x57  bbHelloName  pstr[15]
|   +0x66  bbScrapName  pstr[15]
|   +0x75  bbCntFCBs    word
|   +0x77  bbCntEvts    word
|   +0x79  bbHeapSize128K  long
|   +0x7D  bbHeapSize256K  long
|   +0x81  bbHeapSize     long
|   +0x85  bbReserved     long ($89)... actually filler to 0x8A
|   +0x8A  startup code

    .text
    .global _start
_start:
    .ascii  "LK"                  | bbID

bbEntry:
    bra.w   startup               | 4 bytes: BRA.W to startup
    nop                           | 2 bytes pad to fill 6-byte bbEntry slot

bbVersion:    .word 0x4418        | "magic" version flags
bbPageFlags:  .word 0

bbSysName:    .byte 6
              .ascii "System"
              .space 9            | pad to 15

bbShellName:  .byte 6
              .ascii "Finder"
              .space 9

bbDbg1Name:   .byte 7
              .ascii "MacsBug"
              .space 8

bbDbg2Name:   .byte 12
              .ascii "DisAssembler"
              .space 3

bbScreenName: .byte 7
              .ascii "Startup"
              .ascii "Screen"
              .space 2

bbHelloName:  .byte 12
              .ascii "Finder"
              .space 3

bbScrapName:  .byte 9
              .ascii "Clipboard"
              .space 6

bbCntFCBs:        .word 10
bbCntEvts:        .word 20
bbHeapSize128K:   .long 0x00000800
bbHeapSize256K:   .long 0x00001E00
bbHeapSize:       .long 0x00004300

    .space 0x8A - (. - _start)    | pad to startup offset

startup:
    | Step C will fill this in: disable irqs, open /Payload,
    | read it to $00040000, JMP $00040000.
    | For now: infinite loop so the build links.
    move.w  #0x2700, %sr
1:  bra.s   1b
