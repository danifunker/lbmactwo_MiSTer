//
// vram_ram.sv
//
// Dedicated on-chip VRAM for the NuBus Hi-Res video card, dual-port.
//
// Replaces the shared-SDRAM framebuffer path.  On real hardware the framebuffer
// previously lived in the same SDRAM as Mac system RAM, behind sdram_arbiter, so
// the video scanout competed with the CPU for SDRAM bandwidth and starved (the
// cyan/green/red noise).  Giving video its own block RAM matches how a real Mac
// II works (VRAM lives on the card) and removes the contention entirely.
//
// Dual-port:
//   * Port A (read/write) — CPU VRAM access via the card's FSM (rd/wr + ready).
//   * Port B (read-only)  — the video SCANOUT.  Reading scanout on its own port
//     means it NEVER misses: every pixel's word comes straight from BRAM,
//     independent of CPU writes.  This eliminates the old 2-word cache (which
//     fell back to a stale word on a miss -> garbled text/edges) and the FSM
//     time-sharing of a single port between scanout and CPU.
//
// 256 KB (2^17 16-bit words = ~256 of 472 free M10K blocks); covers 1/2/4 bpp at
// 640x480 (boot is 1 bpp).
//
module vram_ram #(
    parameter integer AW = 17                 // 2^17 words = 256 KB
) (
    input             clk,

    // Port A — CPU read/write (card FSM)
    input      [24:0] addr,
    input      [15:0] din,
    output reg [15:0] dout,
    input             rd,
    input             wr,
    output reg        ready,

    // Port B — video scanout (read-only)
    input      [24:0] addr_b,
    input             rd_b,
    output reg [15:0] dout_b
);
    localparam integer WORDS = (1 << AW);

    (* ramstyle = "M10K" *) reg [15:0] mem [0:WORDS-1];

    // VRAM_BASE (0x300000) is aligned to the VRAM region, so the low AW address
    // bits are the word offset within VRAM (same for both ports).
    wire [AW-1:0] idx_a = addr[AW-1:0];
    wire [AW-1:0] idx_b = addr_b[AW-1:0];

    // Port A: CPU read/write
    always @(posedge clk) begin
        ready <= 1'b0;
        if (wr) begin
            mem[idx_a] <= din;
            ready      <= 1'b1;
        end else if (rd) begin
            dout  <= mem[idx_a];
            ready <= 1'b1;
        end
    end

    // Port B: scanout read (enabled per displayed pixel-word)
    always @(posedge clk) begin
        if (rd_b)
            dout_b <= mem[idx_b];
    end
endmodule
