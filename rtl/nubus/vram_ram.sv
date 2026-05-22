//
// vram_ram.sv
//
// Dedicated on-chip VRAM for the NuBus Hi-Res video card.
//
// Replaces the shared-SDRAM framebuffer path.  On real hardware the framebuffer
// previously lived in the same SDRAM as Mac system RAM, behind sdram_arbiter, so
// the video scanout competed with the CPU for SDRAM bandwidth: the Mac is
// bus-active ~98% of boot, so the scanout starved and the screen filled with
// stale/garbage words (the cyan/green/red noise we saw).  Giving video its own
// block RAM matches how a real Mac II works (VRAM lives on the card) and removes
// the contention entirely -- the Mac keeps SDRAM to itself and the scanout
// always reads coherent data.
//
// 5CSEBA6 has 553 M10K blocks; only ~81 were used, so a 256 KB VRAM
// (2^17 16-bit words = 256 M10K blocks) fits comfortably and covers 1/2/4 bpp at
// 640x480 (boot is 1 bpp).  Bump AW to 18 for the full 512 KB once a tighter fit
// is confirmed.
//
// Protocol matches the video card's simple request/ready handshake:
//   - drive addr (the card uses VRAM_BASE + word; VRAM_BASE is aligned so the
//     low AW bits are the word offset), then pulse rd or wr (with din for write);
//   - ready pulses one cycle later, with dout valid for reads.
//
module vram_ram #(
    parameter integer AW = 17                 // 2^17 words = 256 KB
) (
    input             clk,
    input      [24:0] addr,
    input      [15:0] din,
    output reg [15:0] dout,
    input             rd,
    input             wr,
    output reg        ready
);
    localparam integer WORDS = (1 << AW);

    (* ramstyle = "M10K" *) reg [15:0] mem [0:WORDS-1];

    // VRAM_BASE (0x300000) is aligned to the VRAM region, so the low AW address
    // bits are the word offset within VRAM.
    wire [AW-1:0] idx = addr[AW-1:0];

    always @(posedge clk) begin
        ready <= 1'b0;
        if (wr) begin
            mem[idx] <= din;
            ready    <= 1'b1;
        end else if (rd) begin
            dout  <= mem[idx];
            ready <= 1'b1;
        end
    end
endmodule
