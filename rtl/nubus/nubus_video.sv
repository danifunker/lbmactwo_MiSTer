module nubus_video (
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

    // SDRAM Interface for VRAM
    output reg [24:0] vram_addr,
    output reg [15:0] vram_dout,
    input [15:0] vram_din,
    output reg vram_rd,
    output reg vram_wr,
    input vram_ready,

    // IOCTL Interface for ROM Download
    input        ioctl_wr,
    input [24:0] ioctl_addr,
    input [15:0] ioctl_data,
    input        ioctl_download,
    input [7:0]  ioctl_index
);

    // Video Parameters
    localparam H_RES = 640;
    localparam V_RES = 480;
    localparam H_TOTAL = 864;
    localparam H_SYNC_START = 640 + 64;
    localparam H_SYNC_END = 640 + 64 + 64;
    localparam V_TOTAL = 525;
    localparam V_SYNC_START = 480 + 3;
    localparam V_SYNC_END = 480 + 3 + 3;
    
    // VRAM base address in SDRAM (3MB offset to avoid Mac RAM/ROM/disk images)
    localparam VRAM_BASE = 25'h300000;
    
    // VRAM size - 512KB (262144 words) to match MAME
    localparam VRAM_SIZE = 262144;  // 0x80000 bytes / 2 bytes per word

    // CLUT - Keep on-chip (managed by Bt453 RAMDAC)
    reg [23:0] clut [0:255];
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            clut[i] = {i[7:0], i[7:0], i[7:0]};
        end
    end

    // ROM Buffer - Keep on-chip
    reg [7:0] rom [0:32767];

    // MAME Register indices (matching TFB 2.2 ASIC)
    localparam REG_BASE = 0;           // VRAM offset in 32-bit words
    localparam REG_LENGTH = 1;         // Scanline stride in 32-bit words
    localparam REG_MISC = 2;           // Mode bits [10:8], pixel depth
    localparam REG_SYNCINTERVAL = 3;
    localparam REG_VFRONTPORCH = 4;
    localparam REG_VBACKPORCH = 5;
    localparam REG_VLINES = 6;
    localparam REG_HFRONTPORCH = 7;
    localparam REG_HSYNCPULSE = 8;
    localparam REG_HBACKPORCH = 9;
    localparam REG_HFIRST = 10;
    localparam REG_HLAST = 11;
    localparam REG_SOFTRESET = 12;     // Bit 0 = 1 to enable video

    // Registers
    reg [31:0] registers [0:15];
    reg [7:0] ramdac_addr;
    reg [1:0] ramdac_color_index;
    reg irq_active;
    reg irq_clear;
    reg vbl_disable;
    
    // Decoded values from registers
    wire [2:0] mode_raw = registers[REG_MISC][10:8];
    wire [1:0] mode = (mode_raw >= 3'd4) ? mode_raw[1:0] : 2'd0;  // Bt453: mode 4-7 maps to 0-3 (take lower 2 bits)
    wire video_en = registers[REG_SOFTRESET][0];
    wire [16:0] vram_base_offset = registers[REG_BASE][16:0];  // In 32-bit words
    wire [9:0] vram_stride = registers[REG_LENGTH][9:0];       // In 32-bit words

    // Video Counters
    reg [10:0] h_cnt;
    reg [10:0] v_cnt;
    reg vga_hs_reg, vga_vs_reg, vga_blank_reg;

    always @(posedge clk) begin
        if (reset) begin
            vga_hs_reg <= 1;
            vga_vs_reg <= 1;
            vga_blank_reg <= 1;
        end else begin
            vga_hs_reg <= ~(h_cnt >= H_SYNC_START && h_cnt < H_SYNC_END);
            vga_vs_reg <= ~(v_cnt >= V_SYNC_START && v_cnt < V_SYNC_END);
            vga_blank_reg <= (h_cnt >= H_RES) || (v_cnt >= V_RES) || !video_en;
        end
    end

    assign vga_hs = vga_hs_reg;
    assign vga_vs = vga_vs_reg;
    assign vga_blank = vga_blank_reg;
    assign vga_clk = clk;

    // VBL Interrupt
    reg vbl_pulse;
    always @(posedge clk) begin
        if (reset) begin
            h_cnt <= 11'd0;
            v_cnt <= 11'd0;
            vbl_pulse <= 0;
        end else begin
            vbl_pulse <= 0;
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 11'd0;
                if (v_cnt == V_TOTAL - 1) begin
                    v_cnt <= 11'd0;
                end else begin
                    v_cnt <= v_cnt + 11'd1;
                    if (v_cnt == V_RES - 1)
                        vbl_pulse <= 1;
                end
            end else begin
                h_cnt <= h_cnt + 11'd1;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            irq_active <= 0;
            nmrq_n <= 1;
        end else begin
            if (vbl_pulse && !vbl_disable)
                irq_active <= 1;
            if (irq_clear)
                irq_active <= 0;
            nmrq_n <= ~irq_active;
        end
    end

    // VRAM Address Calculation using MAME's stride-based approach
    // Address = (base_offset * 4) + (v_cnt * stride * 4) + h_byte_offset
    // Where stride is in 32-bit words, so multiply by 4 to get byte offset
    
    wire [19:0] v_offset = v_cnt[9:0] * vram_stride[9:0];  // In 32-bit words (10bit * 10bit = 20bit)
    
    // Horizontal byte offset depends on mode
    wire [19:0] h_byte_offset;
    assign h_byte_offset = (mode == 2'b00) ? {13'd0, h_cnt[10:4]} :   // 1bpp: h/16 words
                           (mode == 2'b01) ? {12'd0, h_cnt[10:3]} :   // 2bpp: h/8 words
                           (mode == 2'b10) ? {11'd0, h_cnt[10:2]} :   // 4bpp: h/4 words
                                             {10'd0, h_cnt[10:1]};    // 8bpp: h/2 words
    
    wire [20:0] fetch_addr_full;
    wire [17:0] fetch_addr;
    assign fetch_addr_full = {3'd0, vram_base_offset[16:0]} + v_offset + h_byte_offset;
    assign fetch_addr = fetch_addr_full[17:0];  // Truncate to 18 bits for 512KB VRAM addressing

    // Unified state machine
    reg [15:0] vram_cache;
    reg vram_cache_valid;
    reg [3:0] state;
    reg [17:0] last_fetch_addr;
    wire [17:0] cpu_vram_addr = addr[18:1];
    
    localparam S_IDLE = 0;
    localparam S_VIDEO_FETCH = 1;
    localparam S_VIDEO_WAIT = 2;
    localparam S_CPU_WRITE = 3;
    localparam S_CPU_WRITE_WAIT = 4;
    localparam S_CPU_READ = 5;
    localparam S_CPU_READ_WAIT = 6;
    
    // ROM Download
    always @(posedge clk) begin
        if (ioctl_wr && ioctl_download && (ioctl_index == 8'd1)) begin
            rom[{ioctl_addr[13:0], 1'b0}] <= ioctl_data[7:0];
            rom[{ioctl_addr[13:0], 1'b1}] <= ioctl_data[15:8];
        end
    end
    
    // Main state machine - single driver for all outputs
    always @(posedge clk) begin
        irq_clear <= 0;
        
        if (reset) begin
            state <= S_IDLE;
            vram_rd <= 0;
            vram_wr <= 0;
            vram_addr <= 25'd0;
            vram_dout <= 16'd0;
            vram_cache_valid <= 0;
            last_fetch_addr <= 18'h3FFFF;
            ack_n <= 1;
            data_out <= 16'd0;
            ramdac_addr <= 0;
            ramdac_color_index <= 0;
            vbl_disable <= 1;
            // Initialize MAME-compatible registers
            for (i = 0; i < 16; i = i + 1)
                registers[i] <= 32'd0;
        end else begin
            case (state)
                S_VIDEO_FETCH: begin
                    state <= S_VIDEO_WAIT;
                end
                
                S_VIDEO_WAIT: begin
                    if (vram_ready) begin
                        vram_cache <= ~vram_din;  // Invert data from VRAM like MAME
                        vram_cache_valid <= 1;
                        vram_rd <= 0;
                        state <= S_IDLE;
                    end
                end
                
                S_IDLE: begin
                    vram_rd <= 0;
                    vram_wr <= 0;
                    
                    // Priority: CPU accesses, then video fetch
                    if (select && ack_n) begin
                        if (!rw_n && addr[23:19] == 5'b00000) begin
                            // CPU VRAM write (with data inversion like MAME)
                            if (cpu_vram_addr < VRAM_SIZE) begin
                                vram_addr <= VRAM_BASE + {6'd0, cpu_vram_addr};
                                vram_dout <= ~data_in;  // Invert data like MAME
                                state <= S_CPU_WRITE;
                            end else begin
                                ack_n <= 0;
                            end
                        end else if (rw_n && addr[23:19] == 5'b00000) begin
                            // CPU VRAM read (with data inversion like MAME)
                            if (cpu_vram_addr < VRAM_SIZE) begin
                                vram_addr <= VRAM_BASE + {6'd0, cpu_vram_addr};
                                state <= S_CPU_READ;
                            end else begin
                                data_out <= 16'hFFFF;  // Inverted 0
                                ack_n <= 0;
                            end
                        end else if (!rw_n && addr[23:19] == 5'b00001) begin
                            // Register write (0x080000 - 0x08FFFF) - MAME TFB registers
                            // MAME stores as 32-bit words, we use 16-bit bus so handle endianness
                            if (addr[18:6] == 0) begin  // Registers 0-15 at offsets 0x00-0x3C
                                // Data inverted like MAME, handle 16-bit writes to 32-bit registers
                                if (addr[1]) begin
                                    // Low word
                                    registers[addr[5:2]][15:0] <= ~data_in;
                                end else begin
                                    // High word
                                    registers[addr[5:2]][31:16] <= ~data_in;
                                end
                            end
                            ack_n <= 0;
                        end else if (rw_n && addr[23:19] == 5'b00001) begin
                            // Register read - rarely used, return inverted 0
                            data_out <= 16'hFFFF;
                            ack_n <= 0;
                        end else if (!rw_n && addr[23:16] == 8'h09) begin
                            // RAMDAC write (0x090000 - 0x09FFFF) - Bt453 RAMDAC
                            // MAME: offset & 1 == 0 -> address_w, offset & 1 == 1 -> palette_w
                            if (addr[1]) begin
                                // Odd address: palette data (R, G, B sequential)
                                case (ramdac_color_index)
                                    0: clut[ramdac_addr][23:16] <= ~data_in[15:8];
                                    1: clut[ramdac_addr][15:8] <= ~data_in[15:8];
                                    2: begin
                                        clut[ramdac_addr][7:0] <= ~data_in[15:8];
                                        ramdac_addr <= ramdac_addr + 8'd1;  // Auto-increment
                                    end
                                endcase
                                ramdac_color_index <= (ramdac_color_index == 2) ? 2'd0 : ramdac_color_index + 2'd1;
                            end else begin
                                // Even address: set palette index
                                ramdac_addr <= ~data_in[15:8];
                                ramdac_color_index <= 0;
                            end
                            ack_n <= 0;
                        end else if (rw_n && addr[23:16] == 8'h09) begin
                            // RAMDAC/VBlank read (0x090000 - 0x09FFFF)
                            if (addr[15:2] == 14'h0004) begin  // Offset 0x10/4 in MAME
                                // Return VBlank status and monitor ID
                                // Bit 16: VBlank, Bits 17-20: monitor ID (inverted)
                                // MAME: (m_screen->vblank() << 16) | (1<<17)
                                // On 16-bit bus, bit 16 of 32-bit becomes bit 0 of high word
                                data_out <= (v_cnt >= V_RES) ? 16'h0003 : 16'h0002;  // VBlank in bit 0, monitor ID 1 in bit 1
                            end else begin
                                data_out <= 16'hFFFF;
                            end
                            ack_n <= 0;
                        end else if (!rw_n && addr[23:16] == 8'h0A) begin
                            // VBL control (0x0A0000 - 0x0AFFFF)
                            if (addr[2]) begin
                                vbl_disable <= 1;  // Offset with bit 2 set disables VBL
                            end else begin
                                vbl_disable <= 0;  // Clear offset enables VBL
                                irq_clear <= 1;
                            end
                            ack_n <= 0;
                        end else if (rw_n && addr[23:20] == 4'hF) begin
                            // ROM read (0x0F0000 - 0x0FFFFF)
                            if (addr[14:0] < 15'd16384) begin
                                data_out[15:8] <= rom[{addr[14:1], 1'b0}];
                                data_out[7:0] <= rom[{addr[14:1], 1'b1}];
                            end else begin
                                data_out <= 16'd0;
                            end
                            ack_n <= 0;
                        end else begin
                            data_out <= 16'hFFFF;
                            ack_n <= 0;
                        end
                    end else if (!select) begin
                        ack_n <= 1;
                    end else if (video_en && fetch_addr != last_fetch_addr && fetch_addr < VRAM_SIZE) begin
                        // Video fetch when CPU not accessing and video enabled
                        vram_addr <= VRAM_BASE + {6'd0, fetch_addr};
                        last_fetch_addr <= fetch_addr;
                        vram_rd <= 1;
                        state <= S_VIDEO_FETCH;
                    end
                end
                
                S_CPU_WRITE: begin
                    vram_wr <= 1;
                    state <= S_CPU_WRITE_WAIT;
                end
                
                S_CPU_WRITE_WAIT: begin
                    if (vram_ready) begin
                        vram_wr <= 0;
                        ack_n <= 0;
                        state <= S_IDLE;
                    end
                end
                
                S_CPU_READ: begin
                    vram_rd <= 1;
                    state <= S_CPU_READ_WAIT;
                end
                
                S_CPU_READ_WAIT: begin
                    if (vram_ready) begin
                        data_out <= ~vram_din;  // Invert data from VRAM like MAME
                        vram_rd <= 0;
                        ack_n <= 0;
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // Pixel output
    reg [2:0] h_cnt_d;
    reg byte_sel_d;
    
    always @(posedge clk) begin
        h_cnt_d <= h_cnt[2:0];
        byte_sel_d <= (mode == 2'b00) ? h_cnt[3] : 
                      (mode == 2'b01) ? h_cnt[2] :
                      (mode == 2'b10) ? h_cnt[1] : h_cnt[0];
    end
    
    wire [7:0] vram_byte = byte_sel_d ? vram_cache[7:0] : vram_cache[15:8];
    
    reg [7:0] pixel_idx;
    always @(*) begin
        pixel_idx = 8'h00;  // Default to prevent latches
        case (mode)
            2'b00: begin
                case (h_cnt_d)
                    3'd0: pixel_idx = {7'b0, vram_byte[7]};
                    3'd1: pixel_idx = {7'b0, vram_byte[6]};
                    3'd2: pixel_idx = {7'b0, vram_byte[5]};
                    3'd3: pixel_idx = {7'b0, vram_byte[4]};
                    3'd4: pixel_idx = {7'b0, vram_byte[3]};
                    3'd5: pixel_idx = {7'b0, vram_byte[2]};
                    3'd6: pixel_idx = {7'b0, vram_byte[1]};
                    3'd7: pixel_idx = {7'b0, vram_byte[0]};
                endcase
            end
            2'b01: begin
                case (h_cnt_d[1:0])
                    2'b00: pixel_idx = {6'b0, vram_byte[7:6]};
                    2'b01: pixel_idx = {6'b0, vram_byte[5:4]};
                    2'b10: pixel_idx = {6'b0, vram_byte[3:2]};
                    2'b11: pixel_idx = {6'b0, vram_byte[1:0]};
                endcase
            end
            2'b10: pixel_idx = h_cnt_d[0] ? {4'b0, vram_byte[3:0]} : {4'b0, vram_byte[7:4]};
            2'b11: pixel_idx = vram_byte;
        endcase
    end

    // Output pixels (no mask for now, MAME doesn't use pixel mask on output)
    assign vga_r = (vga_blank || !vram_cache_valid || !video_en) ? 8'h00 : clut[pixel_idx][23:16];
    assign vga_g = (vga_blank || !vram_cache_valid || !video_en) ? 8'h00 : clut[pixel_idx][15:8];
    assign vga_b = (vga_blank || !vram_cache_valid || !video_en) ? 8'h00 : clut[pixel_idx][7:0];

endmodule