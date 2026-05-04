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

    // Pass through when CPU already issued a genuine 32-bit address
    // (upper byte non-zero). Only translate 24-bit-style addresses
    // ($00xxxxxx) while AMU is active.
    wire passthrough = (addr_in[31:24] != 8'h00);
    assign addr_out = (active && !passthrough) ? xlated : addr_in;
endmodule
