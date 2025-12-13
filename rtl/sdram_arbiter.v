//
// sdram_arbiter.v
//
// SDRAM arbiter for Macintosh Plus MiSTer core
// Shares SDRAM between Mac system and NuBus video card
//
// Mac system has priority, NuBus video uses idle cycles
//

module sdram_arbiter (
    // System
    input         clk,           // System clock (same as clk_sys)
    input         reset,
    
    // Mac System Port (high priority)
    input  [24:0] mac_addr,
    input  [15:0] mac_din,
    output [15:0] mac_dout,
    input   [1:0] mac_ds,
    input         mac_we,
    input         mac_oe,
    
    // NuBus Video Port (low priority)
    input  [24:0] vram_addr,
    input  [15:0] vram_dout,
    output [15:0] vram_din,
    input         vram_rd,
    input         vram_wr,
    output        vram_ready,
    
    // SDRAM Controller Port
    output [24:0] sdram_addr,
    output [15:0] sdram_din,
    input  [15:0] sdram_dout,
    output  [1:0] sdram_ds,
    output        sdram_we,
    output        sdram_oe
);

    // Detect Mac system activity (registered for Quartus compatibility)
    wire mac_active;
    assign mac_active = mac_we | mac_oe;
    
    // Grant signals (Mac has priority over video)
    wire grant_video;
    assign grant_video = !mac_active & (vram_rd | vram_wr);
    
    // Multiplex SDRAM signals
    assign sdram_addr = grant_video ? vram_addr : mac_addr;
    assign sdram_din  = grant_video ? vram_dout : mac_din;
    assign sdram_ds   = grant_video ? 2'b11 : mac_ds;      // Video always accesses full word
    assign sdram_we   = grant_video ? vram_wr : mac_we;
    assign sdram_oe   = grant_video ? vram_rd : mac_oe;
    
    // Route readback data (direct connection, no muxing needed)
    assign mac_dout = sdram_dout;
    assign vram_din = sdram_dout;
    
    // Generate ready signal for video card
    // SDRAM operations complete in ~5-6 clk_sys cycles (one clk_8 cycle + margin)
    // The SDRAM controller cycles through 8 states at 64MHz (clk_mem)
    // synchronized to 8MHz (clk_8). One clk_8 cycle = 4 clk_sys cycles (125ns).
    // SDRAM data ready at STATE_READ (t=5), which is ~100ns into the cycle.
    // Add margin: wait 6 clk_sys cycles = 185ns to ensure data is stable.
    //
    // Handshake: Video asserts rd/wr -> arbiter grants -> after 6 cycles
    // arbiter asserts vram_ready -> video latches data and drops rd/wr
    reg [5:0] vram_op_d;
    always @(posedge clk) begin
        if (reset) begin
            vram_op_d <= 6'b000000;
        end else begin
            vram_op_d <= {vram_op_d[4:0], grant_video};
        end
    end
    
    // Ready pulses high on 6th cycle when operation completes
    // Use edge detection: ready when we've been granted for 6 cycles
    assign vram_ready = vram_op_d[5] & grant_video;

endmodule