// Simplified Toby Video Card (342-0008-a) for Mac II
// 1-bit monochrome, 640x480 @ 60Hz
// Uses on-chip Block RAM instead of SDRAM for debugging

module nubus_video_toby (
    input clk,
    input reset,

    // CPU Interface (NuBus Slot)
    input [31:0] addr,
    input [15:0] data_in,
    output reg [15:0] data_out,
    input [1:0] uds_lds,
    input rw_n,
    input select,
    output reg ack_n,
    output reg nmrq_n,

    // Video Output
    output [7:0] vga_r,
    output [7:0] vga_g,
    output [7:0] vga_b,
    output vga_hs,
    output vga_vs,
    output vga_blank,
    output vga_clk,

    // IOCTL Interface for ROM Download
    input        ioctl_wr,
    input [24:0] ioctl_addr,
    input [15:0] ioctl_data,
    input        ioctl_download,
    input [7:0]  ioctl_index
);

    // Video Parameters - 640x480 @ 60Hz
    localparam H_RES = 640;
    localparam V_RES = 480;
    localparam H_TOTAL = 800;
    localparam H_SYNC_START = 640 + 16;
    localparam H_SYNC_END = 640 + 16 + 96;
    localparam V_TOTAL = 525;
    localparam V_SYNC_START = 480 + 10;
    localparam V_SYNC_END = 480 + 10 + 2;
    
    // NuBus Slot Configuration
    // This card occupies Slot E (Super Slot Space: $FE00_0000 - $FEFF_FFFF)
    localparam SLOT_ID = 4'hE;
    
    // Slot address check - only respond to our assigned slot
    wire in_our_slot = (addr[31:28] == 4'hF) && (addr[27:24] == SLOT_ID);
    
    // VRAM size - 512KB (256K words) on-chip
    // For 640x480 monochrome: 640*480/8 = 38,400 bytes = 19,200 words
    // We'll allocate 32K words (64KB) which is plenty
    localparam VRAM_ADDR_BITS = 15;  // 32K words = 64KB
    localparam VRAM_SIZE = (1 << VRAM_ADDR_BITS);
    
    // ROM Buffer - 4KB (2K words)
    reg [7:0] rom [0:4095];
    
    // VRAM - On-chip Block RAM (dual-port for CPU write + video read)
    // Force synthesis to M10K blocks to avoid using logic registers
    (* ramstyle = "M10K" *) reg [15:0] vram [0:VRAM_SIZE-1];
    
    // Video enabled flag
    reg video_en;
    
    initial begin
        video_en = 1'b1;  // Always enabled for simple card
    end

    // Clock enable generation: 25.175MHz from 32.5MHz
    reg [15:0] clk_video_acc;
    reg clk_video_en;
    
    always @(posedge clk) begin
        if (reset) begin
            clk_video_acc <= 16'd0;
            clk_video_en <= 1'b0;
        end else begin
            if (clk_video_acc + 16'd25175 >= 16'd32500) begin
                clk_video_acc <= clk_video_acc + 16'd25175 - 16'd32500;
                clk_video_en <= 1'b1;
            end else begin
                clk_video_acc <= clk_video_acc + 16'd25175;
                clk_video_en <= 1'b0;
            end
        end
    end

    // Video Counters
    reg [10:0] h_cnt;
    reg [10:0] v_cnt;
    reg vga_hs_reg, vga_vs_reg, vga_blank_reg;

    always @(posedge clk) begin
        if (reset) begin
            h_cnt <= 11'd0;
            v_cnt <= 11'd0;
            vga_hs_reg <= 1'b1;
            vga_vs_reg <= 1'b1;
            vga_blank_reg <= 1'b1;
        end else if (clk_video_en) begin
            // Horizontal counter
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 11'd0;
                // Vertical counter
                if (v_cnt == V_TOTAL - 1) begin
                    v_cnt <= 11'd0;
                end else begin
                    v_cnt <= v_cnt + 11'd1;
                end
            end else begin
                h_cnt <= h_cnt + 11'd1;
            end
            
            // Sync signals
            vga_hs_reg <= ~(h_cnt >= H_SYNC_START && h_cnt < H_SYNC_END);
            vga_vs_reg <= ~(v_cnt >= V_SYNC_START && v_cnt < V_SYNC_END);
            vga_blank_reg <= (h_cnt >= H_RES) || (v_cnt >= V_RES);
        end
    end

    assign vga_hs = vga_hs_reg;
    assign vga_vs = vga_vs_reg;
    assign vga_blank = vga_blank_reg;
    assign vga_clk = clk;

    // VBL Interrupt signals
    reg vbl_disable;
    reg irq_active;
    wire vbl_trigger = clk_video_en && (v_cnt == V_RES) && (h_cnt == 0);
    
    assign nmrq_n = ~irq_active;

    // VRAM Address Calculation
    // Simple linear framebuffer: byte_offset = (y * 80) + (x / 8)
    // Where 80 = 640 / 8 bytes per line
    // Convert to word address: word_addr = byte_offset / 2
    
    wire [14:0] video_byte_addr = (v_cnt[9:0] * 10'd80) + {5'd0, h_cnt[9:3]};
    wire [13:0] video_word_addr = video_byte_addr[14:1];
    
    // Dual-port VRAM
    // Port A - Video read (read-only)
    // Port B - CPU read/write
    reg [13:0] vram_a_addr;
    reg [15:0] vram_a_dout;
    reg [13:0] vram_b_addr;
    reg [15:0] vram_b_din;
    reg [15:0] vram_b_dout;
    reg vram_b_we;
    
    always @(posedge clk) begin
        // Port A - Video read
        vram_a_addr <= video_word_addr;
        vram_a_dout <= vram[vram_a_addr];
        
        // Port B - CPU read/write
        if (vram_b_we) begin
            vram[vram_b_addr] <= vram_b_din;
        end
        vram_b_dout <= vram[vram_b_addr];
    end
    
    // Pixel shift register
    reg [15:0] pixel_shift;
    reg [3:0] pixel_count;
    reg [13:0] last_video_addr;
    
    // Video memory read control
    always @(posedge clk) begin
        if (reset) begin
            pixel_shift <= 16'h0000;
            pixel_count <= 4'd0;
            last_video_addr <= 14'h0000;
        end else if (clk_video_en) begin
            
            if (vga_blank_reg) begin
                pixel_shift <= 16'h0000;
                pixel_count <= 4'd0;
            end else begin
                // Load new data every 8 pixels (when we've shifted out a byte)
                if (pixel_count == 4'd0 || pixel_count == 4'd8) begin
                    if (vram_a_addr != last_video_addr || pixel_count == 4'd0) begin
                        pixel_shift <= vram_a_dout;
                        last_video_addr <= vram_a_addr;
                    end
                    pixel_count <= (pixel_count == 4'd0) ? 4'd1 : 4'd9;
                end else begin
                    pixel_shift <= {pixel_shift[14:0], 1'b0};
                    pixel_count <= pixel_count + 4'd1;
                end
            end
        end
    end
    
    // Output pixel - white (1) or black (0)
    wire pixel_out = pixel_shift[15];
    
    // Debug: capture CPU address and slot info on any access
    reg [31:0] last_cpu_addr;
    reg last_select;
    reg last_rw;
    reg last_in_slot;
    reg [7:0] access_count;
    
    always @(posedge clk) begin
        if (reset) begin
            last_cpu_addr <= 32'h0;
            last_select <= 1'b0;
            last_rw <= 1'b1;
            last_in_slot <= 1'b0;
            access_count <= 8'd0;
        end else if (select && ack_n) begin
            last_cpu_addr <= addr;
            last_select <= 1'b1;
            last_rw <= rw_n;
            last_in_slot <= in_our_slot;
            access_count <= access_count + 8'd1;
        end
    end
    
    // Debug display: Show CPU address bits as pixels (4 pixels per bit for visibility)
    // Line 2-5: Address bits 31-24 (4 rows x 8 bits)
    // Line 6-9: Address bits 23-16
    // Line 10: Access count, slot match, R/W status
    wire [4:0] debug_bit_x = h_cnt[6:2];  // Which bit (0-31)
    wire debug_area = (v_cnt >= 11'd2) && (v_cnt < 11'd11) && (h_cnt < 11'd128);
    reg debug_pixel;
    
    always @(*) begin
        if (v_cnt >= 11'd2 && v_cnt < 11'd6) begin
            // Address bits 31-24 (top nibble, scaled 4x)
            debug_pixel = last_cpu_addr[31 - debug_bit_x[2:0]];
        end else if (v_cnt >= 11'd6 && v_cnt < 11'd10) begin
            // Address bits 23-16 (second nibble, scaled 4x)
            debug_pixel = last_cpu_addr[23 - debug_bit_x[2:0]];
        end else if (v_cnt == 11'd10) begin
            // Status row
            if (h_cnt < 11'd32) debug_pixel = access_count[h_cnt[4:0]];  // Access counter
            else if (h_cnt < 11'd48) debug_pixel = last_in_slot;         // In our slot?
            else if (h_cnt < 11'd64) debug_pixel = last_rw;              // Read/Write
            else if (h_cnt < 11'd80) debug_pixel = last_select;          // Select active
            else debug_pixel = 1'b0;
        end else begin
            debug_pixel = 1'b0;
        end
    end
    
    // Test pattern: white border + debug display
    wire border = (v_cnt < 11'd2) || (v_cnt >= 11'd478) || 
                  (h_cnt < 11'd8) || (h_cnt >= 11'd632);
    
    wire video_pixel = border | (debug_area & debug_pixel) | pixel_out;
    
    // Color coding: border=white, debug=cyan (blue+green), content=white
    assign vga_r = (vga_blank_reg || !video_en) ? 8'h00 : 
                   (debug_area & debug_pixel) ? 8'h00 : 
                   (video_pixel ? 8'hFF : 8'h00);
    assign vga_g = (vga_blank_reg || !video_en) ? 8'h00 : (video_pixel ? 8'hFF : 8'h00);
    assign vga_b = (vga_blank_reg || !video_en) ? 8'h00 : (video_pixel ? 8'hFF : 8'h00);

    // ROM Download - boot1.rom is index 1
    always @(posedge clk) begin
        if (ioctl_wr && ioctl_download && ioctl_index == 8'd1) begin
            rom[{ioctl_addr[11:0], 1'b0}] <= ioctl_data[7:0];
            rom[{ioctl_addr[11:0], 1'b1}] <= ioctl_data[15:8];
        end
    end
    
    // CPU Access State Machine
    reg [2:0] ack_delay;
    wire [13:0] cpu_vram_addr = addr[14:1];
    
    always @(posedge clk) begin
        if (reset) begin
            ack_n <= 1'b1;
            ack_delay <= 3'd0;
            data_out <= 16'd0;
            vbl_disable <= 1'b1;
            irq_active <= 1'b0;
            vram_b_addr <= 14'd0;
            vram_b_din <= 16'd0;
            vram_b_we <= 1'b0;
        end else begin
            vram_b_we <= 1'b0;  // Default: no write
            
            // VBL interrupt generation
            if (vbl_trigger && !vbl_disable) begin
                irq_active <= 1'b1;
            end
            
            // Decrement delay counter
            if (ack_delay > 3'd0) begin
                ack_delay <= ack_delay - 3'd1;
                // For VRAM reads, latch data when delay is 2
                if (ack_delay == 3'd2 && addr[23:19] == 5'b00000 && rw_n) begin
                    data_out <= vram_b_dout;
                end
            end
            
            // Assert ack when counter reaches 0
            if (ack_delay == 3'd1) begin
                ack_n <= 1'b0;
            end
            
            // CPU access - only respond if accessed in our slot
            if (select && ack_n && ack_delay == 3'd0 && in_our_slot) begin
                if (addr[23:19] == 5'b00000) begin
                    // VRAM access (0x000000 - 0x07FFFF)
                    vram_b_addr <= cpu_vram_addr;
                    if (!rw_n) begin
                        // Write
                        vram_b_din <= data_in;
                        vram_b_we <= 1'b1;
                        ack_delay <= 3'd2;
                    end else begin
                        // Read - data will be ready after 1 cycle
                        ack_delay <= 3'd3;  // Extra cycle for synchronous read
                    end
                end else if (!rw_n && addr[23:16] == 8'h0A) begin
                    // VBL control (0x0A0000 - 0x0AFFFF)
                    if (addr[2]) begin
                        vbl_disable <= 1'b1;
                    end else begin
                        vbl_disable <= 1'b0;
                        irq_active <= 1'b0;
                    end
                    ack_delay <= 3'd2;
                end else if (rw_n && addr[23:16] == 8'h09) begin
                    // VBL status read (0x090000 - 0x09FFFF)
                    data_out <= (v_cnt >= V_RES) ? 16'h0001 : 16'h0000;
                    ack_delay <= 3'd2;
                end else if (rw_n && addr[23:20] == 4'hF) begin
                    // ROM read (0x0F0000 - 0x0FFFFF)
                    if (addr[11:0] < 12'd2048) begin
                        data_out[15:8] <= rom[{addr[11:1], 1'b0}];
                        data_out[7:0] <= rom[{addr[11:1], 1'b1}];
                    end else begin
                        data_out <= 16'd0;
                    end
                    ack_delay <= 3'd3;
                end else begin
                    data_out <= 16'h0000;
                    ack_delay <= 3'd2;
                end
            end else if (!select && !ack_n) begin
                // CPU deasserted select - end transaction
                ack_n <= 1'b1;
                ack_delay <= 3'd0;
            end
        end
    end

endmodule
