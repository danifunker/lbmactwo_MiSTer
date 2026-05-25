//
// sdram_arbiter.v
//
// 3-Port TDM SDRAM Arbiter for Macintosh II MiSTer core
//
// Port 0: Mac System RAM
// Port 1: Video Scanout DMA (Highest Priority TDM)
// Port 2: NuBus CPU-VRAM (Lowest Priority)
//

module sdram_arbiter (
    input         clk,           // System clock (32.5 MHz)
    input         clk8_en_p,     // SDRAM cycle start pulse (8 MHz)
    input         reset,

    // Port 0: Mac System Port
    input  [24:0] mac_addr,
    input  [15:0] mac_din,
    output [15:0] mac_dout,
    input   [1:0] mac_ds,
    input         mac_we,
    input         mac_oe,
    output        mac_dout_valid,

    // Port 1: Video Scanout DMA Port
    input  [24:0] scan_addr,
    output [15:0] scan_dout,
    input         scan_rd,
    output        scan_ready,

    // Port 2: NuBus CPU-VRAM Port
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
    output        sdram_oe,

    // Legacy / Debug outputs
    output        mac_stall,
    output        dbg_grant_video,
    output        dbg_video_clean,
    output [3:0]  dbg_mac_idle_cnt,
    output [2:0]  dbg_vram_state
);

    // TDM Cycle (4 slots)
    // 0: Scanout (Port 1)
    // 1: Mac     (Port 0)
    // 2: Scanout (Port 1)
    // 3: NuBus   (Port 2)
    reg [1:0] tdm_slot;
    always @(posedge clk) begin
        if (reset) tdm_slot <= 2'd0;
        else if (clk8_en_p) tdm_slot <= tdm_slot + 2'd1;
    end

    wire mac_active  = mac_oe | mac_we;
    wire scan_active = scan_rd;
    wire vram_active = vram_rd | vram_wr;

    reg [1:0] owner;
    always @(*) begin
        case (tdm_slot)
            2'd0, 2'd2: begin // Scanout Primary Slots
                if (scan_active)      owner = 2'd1;
                else if (mac_active)  owner = 2'd0;
                else                  owner = 2'd2;
            end
            2'd1: begin // Mac Primary Slot
                if (mac_active)       owner = 2'd0;
                else if (scan_active) owner = 2'd1;
                else                  owner = 2'd2;
            end
            2'd3: begin // NuBus Primary Slot
                if (vram_active)      owner = 2'd2;
                else if (mac_active)  owner = 2'd0;
                else                  owner = 2'd1;
            end
            default: owner = 2'd0;
        endcase
    end

    reg [1:0] current_owner;
    always @(posedge clk) begin
        if (clk8_en_p) current_owner <= owner;
    end

    // Signal Muxing
    assign sdram_addr = (current_owner == 2'd1) ? scan_addr :
                        (current_owner == 2'd2) ? vram_addr : mac_addr;

    assign sdram_din  = (current_owner == 2'd2) ? vram_dout : mac_din;

    assign sdram_ds   = (current_owner == 2'd0) ? mac_ds : 2'b11;

    assign sdram_we   = (current_owner == 2'd0) ? mac_we :
                        (current_owner == 2'd2) ? vram_wr : 1'b0;

    assign sdram_oe   = (current_owner == 2'd0) ? mac_oe :
                        (current_owner == 2'd1) ? scan_rd :
                        (current_owner == 2'd2) ? vram_rd : 1'b0;

    assign mac_dout  = sdram_dout;
    assign scan_dout = sdram_dout;
    assign vram_din  = sdram_dout;

    // Handshakes
    reg [1:0] mac_state, scan_state, vram_state;
    localparam S_IDLE = 2'd0;
    localparam S_BUSY = 2'd1;
    localparam S_DONE = 2'd2;

    always @(posedge clk) begin
        if (reset) begin
            mac_state  <= S_IDLE;
            scan_state <= S_IDLE;
            vram_state <= S_IDLE;
        end else begin
            // Mac Handshake
            if (!mac_active)
                mac_state <= S_IDLE;
            else if (mac_state == S_IDLE && clk8_en_p && owner == 2'd0)
                mac_state <= S_BUSY;
            else if (mac_state == S_BUSY && clk8_en_p)
                mac_state <= S_DONE;

            // Scanout Handshake
            if (!scan_active)
                scan_state <= S_IDLE;
            else if (scan_state == S_IDLE && clk8_en_p && owner == 2'd1)
                scan_state <= S_BUSY;
            else if (scan_state == S_BUSY && clk8_en_p)
                scan_state <= S_DONE;

            // NuBus Handshake
            if (!vram_active)
                vram_state <= S_IDLE;
            else if (vram_state == S_IDLE && clk8_en_p && owner == 2'd2)
                vram_state <= S_BUSY;
            else if (vram_state == S_BUSY && clk8_en_p)
                vram_state <= S_DONE;
        end
    end

    assign mac_dout_valid = (mac_state == S_DONE);
    assign scan_ready     = (scan_state == S_DONE);
    assign vram_ready     = (vram_state == S_DONE);

    // Legacy / Debug ties
    assign mac_stall        = (mac_state != S_DONE && mac_active);
    assign dbg_grant_video  = (current_owner != 2'd0);
    assign dbg_video_clean  = (current_owner == 2'd1);
    assign dbg_mac_idle_cnt = 4'd0;
    assign dbg_vram_state   = {1'b0, current_owner};

endmodule
