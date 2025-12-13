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
    
    // State machine for tracking video operations
    reg [2:0] vram_state;
    reg [2:0] vram_wait_cnt;
    reg vram_ready_latch;
    
    localparam VRAM_IDLE = 3'd0;
    localparam VRAM_WAIT = 3'd1;
    localparam VRAM_READY = 3'd2;
    
    always @(posedge clk) begin
        if (reset) begin
            vram_state <= VRAM_IDLE;
            vram_wait_cnt <= 3'd0;
            vram_ready_latch <= 1'b0;
        end else begin
            case (vram_state)
                VRAM_IDLE: begin
                    vram_ready_latch <= 1'b0;
                    if (grant_video) begin
                        // Video request granted, start counting
                        vram_state <= VRAM_WAIT;
                        vram_wait_cnt <= 3'd6;  // 6 cycles for SDRAM read/write
                    end
                end
                
                VRAM_WAIT: begin
                    if (vram_wait_cnt > 3'd0) begin
                        vram_wait_cnt <= vram_wait_cnt - 3'd1;
                    end else begin
                        // Data ready - latch the ready signal
                        vram_ready_latch <= 1'b1;
                        vram_state <= VRAM_READY;
                    end
                end
                
                VRAM_READY: begin
                    // Hold ready high until video drops its request
                    if (!vram_rd && !vram_wr) begin
                        vram_ready_latch <= 1'b0;
                        vram_state <= VRAM_IDLE;
                    end
                end
                
                default: vram_state <= VRAM_IDLE;
            endcase
        end
    end
    
    // Ready signal is latched, independent of grant_video
    assign vram_ready = vram_ready_latch;

endmodule