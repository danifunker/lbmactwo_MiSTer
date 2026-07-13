// Mac II HMMU / AMU address translation
//
// When VIA2 PB3 is driven low (DDRB[3]=1 and ORB[3]=0), the Mac II HMMU
// is active: the low 24 bits of every CPU bus cycle get remapped to the
// 32-bit physical address space using the same table used by MAME's
// hmmu_translate_addr() and Snow's amu_translate():
//
//   24-bit input          32-bit physical
//   0x00_0000..0x7F_FFFF  0x0000_0000 | addr24                    RAM
//   0x80_0000..0x8F_FFFF  0x4000_0000 | (addr24 & 0xFFFFF)        ROM
//   0x90..0xEF            0xF000_0000 | ((addr24 & 0xF00000)<<4)
//                                     | (addr24 & 0xFFFFF)        NuBus
//   0xF0_0000..0xFF_FFFF  0x50F0_0000 | (addr24 & 0xFFFFF)        I/O
//
// MAME models the Mac II I/O map at 0x5000_0000 with a 0x00f0_0000 mirror,
// so both 0x500x_xxxx and 0x50Fx_xxxx resolve there. This core's physical
// decoder intentionally only selects the verified 0x50Fx_xxxx window, so the
// translated HMMU output must land in that window.
//
// When PB3 is high (DDRB[3]=1, ORB[3]=1) or configured as input, the
// HMMU is inactive and the address passes through unchanged (full 32-bit
// mode). Purely combinational.

module hmmu (
    input  [31:0] addr_in,
    input         active,       // 1 = 24-bit HMMU mode, 0 = passthrough
    output [31:0] addr_out
);
    wire [23:0] lo = addr_in[23:0];
    reg  [31:0] xlated;

    always @* begin
        casez (lo[23:20])
            4'b0???: xlated = {8'h00, lo};                                  // 0..7 RAM
            4'b1000: xlated = {8'h40, 4'h0, lo[19:0]};                      // 8    ROM
            4'b1001,
            4'b1010,
            4'b1011,
            4'b1100,
            4'b1101,
            4'b1110: xlated = {4'hF, lo[23:20], 4'h0, lo[19:0]};            // 9..E NuBus
            4'b1111: xlated = {12'h50F, lo[19:0]};                          // F    I/O
            default: xlated = {8'h00, lo};
        endcase
    end

    // In 24-bit mode the Mac II HMMU/AMU masks off the CPU address high byte.
    // Resource handles and master-pointer flags commonly use high bits such as
    // $A0; those still must translate through the low 24-bit address.
    //
    // Fix A (2026-07-13): even in PASSTHROUGH mode, a Memory-Manager master
    // pointer flagged with the locked/purgeable/resource combos ($A0/$C0/$E0
    // etc. -> high byte $90..$EF) must still resolve through its low-24-bit
    // RAM address, exactly as a real Mac (and MacLC, which decodes RAM on the
    // low 24 bits unconditionally) does. Without this the driver's parse
    // dereferences such a handle while hmmu_active is low, the high byte leaks
    // into a NuBus-slot decode (no card -> bus error), and the DF/DIB fixup
    // engine turns the resulting garbage-pointer BlockMove into a ~2 s per-byte
    // bus-error STORM -> the disk op times out -> the Happy-Mac soft-reboot
    // (give-up PC 0x6DD8, inside the BlockMove; confirmed on ss1). The masked
    // range EXCLUDES $00 (RAM), $40 (32-bit ROM — the CPU executes at
    // $4080xxxx), $50 (32-bit I/O $50Fxxxxx), $80 (mirrored to $00 in the
    // decoder) and $F0..$FF (32-bit super-slots / PDS the ROM slot scan and the
    // MDC824 video card use), so no legitimate 32-bit ROM/I/O/NuBus access is
    // touched — only the flagged-handle leak is redirected to real RAM.
    wire flagged_handle = (addr_in[31:24] >= 8'h90) && (addr_in[31:24] <= 8'hEF);
    assign addr_out = (active || flagged_handle) ? xlated : addr_in;
endmodule
