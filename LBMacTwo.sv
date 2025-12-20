//  Macintosh II
//
//  Copyright (C) 2025 Dani Sarfati
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

// LED Debug Indicators:
// LED_USER (Orange) = Disk activity (original)
// LED_DISK[1] (Purple/Magenta) = Video card active
// LED_DISK[0] (Red) = unused
// LED_POWER[1] (Blue) = NuBus access
// LED_POWER[0] (Green) = RAM/ROM access
assign LED_USER  = dio_download || (disk_act ^ |diskMotor);
assign LED_DISK  = {|video_act_ctr, 1'b0};
assign LED_POWER = {|nubus_act_ctr, |mem_act_ctr};
assign BUTTONS   = 0;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire [1:0] ar = status[8:7];
video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),

	.ARX((!ar) ? 12'd256 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd171 : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[12:11])
);

`include "build_id.v"
localparam CONF_STR = {
	"LBMacTwo;;",
	"-;",
	"F1,DSK,Mount Pri Floppy;",
	"F2,DSK,Mount Sec Floppy;",
	"-;",
	"SC0,IMGVHD,Mount SCSI-6;",
	"SC1,IMGVHD,Mount SCSI-5;",
	"-;",
	"O78,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"OBC,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"O5,Speed,8MHz,16MHz;",
	"O4,Memory,1MB,4MB;",
	"-;",
	"O6,Debug Overlay,Off,On;",
	"-;",
	"R0,Reset & Apply CPU+Memory;",
	"-;",
	"v,0;", // [optional] config version 0-99.
	        // If CONF_STR options are changed in incompatible way, then change version number too,
			// so all options will get default values on first start.
	"V,v",`BUILD_DATE
};

wire status_turbo = status[5];
wire status_overlay_en = status[6];

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_mem, clk_mem_ps;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk_mem),      // 65MHz, 0° - SDRAM controller
	.outclk_1(clk_sys),      // 32.5MHz, 180° - System
	.outclk_2(clk_mem_ps),   // 65MHz, -90° - SDRAM chip clock
	.locked(pll_locked)
);

reg       status_mem;
reg [1:0] status_mod;
reg       n_reset = 0;
reg       osd_reset_req = 0;
reg [23:0] osd_reset_timer = 0;

// Capture OSD reset request (status[0] is edge-triggered)
always @(posedge clk_sys) begin
	reg old_status0;
	old_status0 <= status[0];
	
	// Detect rising edge of reset button
	if (status[0] && !old_status0) begin
		osd_reset_req <= 1'b1;
		osd_reset_timer <= 24'hFFFFFF;  // Hold reset for ~0.5 seconds
	end else if (osd_reset_timer != 0) begin
		osd_reset_timer <= osd_reset_timer - 1'd1;
	end else begin
		osd_reset_req <= 1'b0;
	end
end

always @(posedge clk_sys) begin
	reg [15:0] rst_cnt;

	if (clk8_en_p) begin
		// various sources can reset the mac
		if(~pll_locked || osd_reset_req || buttons[1] || RESET || ~_cpuReset_o) begin
			rst_cnt <= '1;
			n_reset <= 0;
		end
		else if(rst_cnt) begin
			rst_cnt    <= rst_cnt - 1'd1;
			status_mem <= status[4];
			status_mod <= status[10:9];
		end
		else begin
			n_reset <= 1;
		end
	end
end

///////////////////////////////////////////////////

localparam SCSI_DEVS = 2;

// the status register is controlled by the on screen display (OSD)
wire [31:0] status;
wire  [1:0] buttons;
wire [31:0] sd_lba[SCSI_DEVS];
wire  [SCSI_DEVS-1:0] sd_rd;
wire  [SCSI_DEVS-1:0] sd_wr;
wire  [SCSI_DEVS-1:0] sd_ack;
wire            [7:0] sd_buff_addr;
wire           [15:0] sd_buff_dout;
wire           [15:0] sd_buff_din[SCSI_DEVS];
wire                  sd_buff_wr;
wire  [SCSI_DEVS-1:0] img_mounted;
wire           [63:0] img_size;

wire        ioctl_write;
reg         ioctl_wait = 0;

wire [10:0] ps2_key;
wire [24:0] ps2_mouse;
wire        capslock;

wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;

wire [32:0] TIMESTAMP;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(SCSI_DEVS), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_size(img_size),

	.ioctl_download(dio_download),
	.ioctl_index(dio_index),
	.ioctl_wr(ioctl_write),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait),

	.TIMESTAMP(TIMESTAMP),

	.ps2_key(ps2_key),
	.ps2_kbd_led_use(3'b001),
	.ps2_kbd_led_status({2'b00, capslock}),

	.ps2_mouse(ps2_mouse)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = 1;

wire [15:0] nubusDataOut;
wire nubusAck;
wire nubus_irq_n;
wire [7:0] nubus_r, nubus_g, nubus_b;
wire nubus_hs, nubus_vs, nubus_blank;

// Mac II has NO built-in video - only NuBus video cards
assign VGA_R  = nubus_r;
assign VGA_G  = nubus_g;
assign VGA_B  = nubus_b;
assign VGA_DE = !nubus_blank;
assign VGA_VS = nubus_vs;
assign VGA_HS = nubus_hs;
assign VGA_F1 = 0;
assign VGA_SL = 0;

wire [10:0] audio;
assign AUDIO_L = {audio[10:0], 5'b00000};
assign AUDIO_R = {audio[10:0], 5'b00000};
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;


// ------------------------------ Plus Too Bus Timing ---------------------------------
// for stability and maintainability reasons the whole timing has been simplyfied:
//                00           01             10           11
//    ______ _____________ _____________ _____________ _____________ ___
//    ______X_video_cycle_X__cpu_cycle__X__IO_cycle___X__cpu_cycle__X___
//                        ^      ^    ^                      ^    ^
//                        |      |    |                      |    |
//                      video    | CPU|                      | CPU|
//                       read   write read                  write read



// set the real-world inputs to sane defaults
localparam 	  configROMSize = 1'b1;  // 128K ROM

wire [1:0] configRAMSize = status_mem?2'b11:2'b10; // 1MB/4MB
wire selectNuBus;

//
// Mac II uses SCC for serial communication, not UARTs
// Tie off UART pins to avoid floating signals
assign UART_TXD = 1'b1;  // Idle high
assign UART_RTS = 1'b1;  // Not ready
assign UART_DTR = 1'b0;  // Not asserted
/*
	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,
*/


// interconnects
// CPU
wire clk8, _cpuReset, _cpuReset_o, _cpuUDS, _cpuLDS, _cpuRW, _cpuAS;
wire clk8_en_p, clk8_en_n;
wire clk16_en_p, clk16_en_n;
wire _cpuVMA, _cpuVPA, _cpuDTACK;
wire E_rising, E_falling;
wire [2:0] _cpuIPL;
wire [2:0] cpuFC;
wire [7:0] cpuAddrHi;
wire [31:0] cpuAddr;
wire [15:0] cpuDataOut;

// RAM/ROM
wire _romOE;
wire _ramOE, _ramWE;
wire _memoryUDS, _memoryLDS;
wire videoBusControl;
wire dioBusControl;
wire cpuBusControl;
wire [21:0] memoryAddr;
wire [15:0] memoryDataOut;
wire memoryLatch;

// peripherals
wire memoryOverlayOn, selectSCSI, selectSCC, selectIWM, selectVIA, selectRAM, selectROM, selectSEOverlay;
wire [15:0] dataControllerDataOut;

// audio
wire snd_alt;
wire loadSound;

// video timing signals (Mac Plus legacy - still needed by addrController_top)
wire hsync, vsync, _hblank, _vblank, loadPixels, vid_alt;

// floppy disk image interface
wire dskReadAckInt;
wire [21:0] dskReadAddrInt;
wire dskReadAckExt;
wire [21:0] dskReadAddrExt;

// dtack generation in turbo mode
reg  turbo_dtack_en, cpuBusControl_d;
always @(posedge clk_sys) begin
	if (!_cpuReset) begin
		turbo_dtack_en <= 0;
	end
	else begin
		cpuBusControl_d <= cpuBusControl;
		if (_cpuAS) turbo_dtack_en <= 0;
		if (!_cpuAS & ((!cpuBusControl_d & cpuBusControl) | (!selectROM & !selectRAM))) turbo_dtack_en <= 1;
	end
end

assign      _cpuVPA = (cpuFC == 3'b111) ? 1'b0 : ~(!_cpuAS && cpuAddr[23:21] == 3'b111);
assign      _cpuDTACK = selectNuBus ? nubusAck : (~(!_cpuAS && cpuAddr[23:21] != 3'b111) | (status_turbo & !turbo_dtack_en));

// Debug LED tracking - extended duration for visibility
reg [27:0] nubus_act_ctr, mem_act_ctr, video_act_ctr;
wire nubus_access = selectNuBus && !_cpuAS;
wire mem_access = (selectRAM || selectROM) && !_cpuAS;
wire video_active = !nubus_blank;

always @(posedge clk_sys) begin
	if (nubus_access) nubus_act_ctr <= 28'hFFFFFFF;  // ~8 seconds at 32.5MHz
	else if (nubus_act_ctr != 0) nubus_act_ctr <= nubus_act_ctr - 1'd1;
	
	if (mem_access) mem_act_ctr <= 28'hFFFFFFF;
	else if (mem_act_ctr != 0) mem_act_ctr <= mem_act_ctr - 1'd1;
	
	if (video_active) video_act_ctr <= 28'hFFFFFFF;
	else if (video_act_ctr != 0) video_act_ctr <= video_act_ctr - 1'd1;
end

wire        cpu_en_p      = status_turbo ? clk16_en_p : clk8_en_p;
wire        cpu_en_n      = status_turbo ? clk16_en_n : clk8_en_n;

// Mac II uses TG68K in 68020 mode only
assign      _cpuReset_o   = tg68_reset_n;
assign      _cpuRW        = tg68_rw;
assign      _cpuAS        = tg68_as_n;
assign      _cpuUDS       = tg68_uds_n;
assign      _cpuLDS       = tg68_lds_n;
assign      E_falling     = tg68_E_falling;
assign      E_rising      = tg68_E_rising;
assign      _cpuVMA       = tg68_vma_n;
assign      cpuFC[0]      = tg68_fc0;
assign      cpuFC[1]      = tg68_fc1;
assign      cpuFC[2]      = tg68_fc2;
assign      cpuAddr       = tg68_a;
assign      cpuDataOut    = tg68_dout;

wire        tg68_rw;
wire        tg68_as_n;
wire        tg68_uds_n;
wire        tg68_lds_n;
wire        tg68_E_rising;
wire        tg68_E_falling;
wire        tg68_vma_n;
wire        tg68_fc0;
wire        tg68_fc1;
wire        tg68_fc2;
wire [15:0] tg68_dout;
wire [31:0] tg68_a;
wire        tg68_reset_n;

// FPU signals
wire [4:0]  cir_address;
wire        cir_read;
wire        cir_write;
wire [31:0] cir_data_in;
wire [31:0] cir_data_out;
wire        cir_data_valid;
wire [15:0] fpu_opcode;
wire [15:0] fpu_extword;
wire        fpu_op_valid;
wire [2:0]  cpu_privilege;

tg68k tg68k_inst (
	.clk        ( clk_sys      ),
	.reset      ( !_cpuReset ),
	.phi1       ( cpu_en_p  ),
	.phi2       ( cpu_en_n  ),
	.cpu        ( 2'b11 ), // 68020 mode with FPU

	.dtack_n    ( _cpuDTACK  ),
	.rw_n       ( tg68_rw    ),
	.as_n       ( tg68_as_n  ),
	.uds_n      ( tg68_uds_n ),
	.lds_n      ( tg68_lds_n ),
	.fc         ( { tg68_fc2, tg68_fc1, tg68_fc0 } ),
	.reset_n    ( tg68_reset_n ),

	.E          (  ),
	.E_div      ( status_turbo ),
	.E_PosClkEn ( tg68_E_falling ),
	.E_NegClkEn ( tg68_E_rising  ),
	.vma_n      ( tg68_vma_n ),
	.vpa_n      ( _cpuVPA ),

	.br_n       ( 1'b1    ),
	.bg_n       (  ),
	.bgack_n    ( 1'b1 ),

	.ipl        ( _cpuIPL ),
	.berr       ( 1'b0 ),
	.din        ( dataControllerDataOut ),
	.dout       ( tg68_dout ),
	.addr       ( tg68_a ),

	// FPU Interface
	.cir_address    ( cir_address   ),
	.cir_read       ( cir_read      ),
	.cir_write      ( cir_write     ),
	.cir_data_in    ( cir_data_in   ),
	.cir_data_out   ( cir_data_out  ),
	.cir_data_valid ( cir_data_valid),
	.instruction_opcode   ( fpu_opcode    ),
    .instruction_ext_word ( fpu_extword   ),
    .instruction_valid    ( fpu_op_valid  ),
    .cpu_privilege_level  ( cpu_privilege )
);

// -----------------------------------------------------------------------
    // 2. FPU Instantiation (TG68K_FPU) fully connected
    // -----------------------------------------------------------------------
    TG68K_FPU fpu_inst (
        .clk                    ( clk_sys           ),
        .nReset                 ( _cpuReset         ), // Active low reset
        .clkena                 ( 1'b1              ), // Always run

        // CPU Interface (Snooping)
        .opcode                 ( fpu_opcode        ), // FROM tg68k
        .extension_word         ( fpu_extword       ), // FROM tg68k
        .fpu_enable             ( 1'b1              ),
        
        // Supervisor mode: Bit 2 of privilege level is usually supervisor bit (User=0, Super=1)
        // Check TG68K docs, but usually FC2 (bit 2 of fc) or similar indicates supervisor.
        // Assuming cpu_privilege[2] = 1 means Supervisor.
        .supervisor_mode        ( cpu_privilege[2]  ), 

        // Memory Interface (Data from CPU to FPU)
        // The FPU snoops data on the data bus during FMOVEM/FSAVE
        .cpu_data_in            ( {tg68_dout, tg68_dout} ), // Simplified: Mirror 16-bit data to 32-bit
        .cpu_address_in         ( tg68_a            ),
        
        // These outputs are unconnected as they are internal FPU state or debug
        .fpu_data_out           (                   ), 

        // FSAVE/FRESTORE/FMOVEM (Tied to 0 for now as simple snooping might not cover complex bus mastering)
        // For full support, the TG68K core needs to drive these request lines explicitly.
        .fsave_data_request     ( 1'b0              ),
        .fsave_data_index       ( 0                 ),
        .frestore_data_write    ( 1'b0              ),
        .frestore_data_in       ( 32'd0             ),
        .fmovem_data_request    ( 1'b0              ),
        .fmovem_reg_index       ( 0                 ),
        .fmovem_data_write      ( 1'b0              ),
        .fmovem_data_in         ( 80'd0             ),

        // Coprocessor Interface Registers (CIR)
        .cir_address            ( cir_address       ),
        .cir_write              ( cir_write         ),
        .cir_read               ( cir_read          ),
        .cir_data_in            ( {cir_data_out[7:0], cir_data_out[15:8]} ), // Swapped for endianness if needed
        .cir_data_out           ( cir_data_in       ),
        .cir_data_valid         ( cir_data_valid    )
    );


addrController_top ac0
(
	.clk(clk_sys),
	.clk8(clk8),
	.clk8_en_p(clk8_en_p),
	.clk8_en_n(clk8_en_n),
	.clk16_en_p(clk16_en_p),
	.clk16_en_n(clk16_en_n),
	.cpuAddr(cpuAddr),
	._cpuUDS(_cpuUDS),
	._cpuLDS(_cpuLDS),
	._cpuRW(_cpuRW),
	._cpuAS(_cpuAS),
	.turbo(status_turbo),
	.configROMSize(2'b10), // Mac II always uses 256K ROM
	.configRAMSize(configRAMSize),
	.memoryAddr(memoryAddr),
	.memoryLatch(memoryLatch),
	._memoryUDS(_memoryUDS),
	._memoryLDS(_memoryLDS),
	._romOE(_romOE),
	._ramOE(_ramOE),
	._ramWE(_ramWE),
	.videoBusControl(videoBusControl),
	.dioBusControl(dioBusControl),
	.cpuBusControl(cpuBusControl),
	.selectSCSI(selectSCSI),
	.selectSCC(selectSCC),
	.selectIWM(selectIWM),
	.selectVIA(selectVIA),
	.selectRAM(selectRAM),
	.selectROM(selectROM),
	.selectSEOverlay(selectSEOverlay),
	.selectNuBus(selectNuBus),
	.hsync(hsync),
	.vsync(vsync),
	._hblank(_hblank),
	._vblank(_vblank),
	.loadPixels(loadPixels),
	.vid_alt(vid_alt),
	.memoryOverlayOn(memoryOverlayOn),

	.snd_alt(snd_alt),
	.loadSound(loadSound),

	.dskReadAddrInt(dskReadAddrInt),
	.dskReadAckInt(dskReadAckInt),
	.dskReadAddrExt(dskReadAddrExt),
	.dskReadAckExt(dskReadAckExt)
);

wire [1:0] diskEject;
wire [1:0] diskMotor, diskAct;

nubus_video_toby nubus_card (
	.clk(clk_sys),
	.reset(!_cpuReset),
	.addr(cpuAddr),
	.data_in(cpuDataOut),
	.data_out(nubusDataOut),
	.uds_lds({!_cpuUDS, !_cpuLDS}),
	.rw_n(_cpuRW),
	.select(selectNuBus),
	.ack_n(nubusAck),
	.vga_r(nubus_r),
	.vga_g(nubus_g),
	.vga_b(nubus_b),
	.vga_hs(nubus_hs),
	.vga_vs(nubus_vs),
	.vga_blank(nubus_blank),
	.vga_clk(), // unused for now
	.nmrq_n(nubus_irq_n),
	
	// Toby card uses on-chip VRAM, no external interface needed
	// Overlay control
	.overlay_en(status_overlay_en),

	.ioctl_wr(ioctl_write),
	.ioctl_addr({4'd0, dio_a}),
	.ioctl_data(dio_data),
	.ioctl_download(dio_download),
	.ioctl_index(dio_index)
);

dataController_top #(SCSI_DEVS) dc0
(
	.clk32(clk_sys),
	.clk8_en_p(clk8_en_p),
	.clk8_en_n(clk8_en_n),
	.E_rising(E_rising),
	.E_falling(E_falling),
	.machineType(1'b1), // Mac II mode
	._systemReset(n_reset),
	._cpuReset(_cpuReset),
	._cpuIPL(_cpuIPL),
	._cpuUDS(_cpuUDS),
	._cpuLDS(_cpuLDS),
	._cpuRW(_cpuRW),
	._cpuVMA(_cpuVMA),
	.selectNuBus(selectNuBus),
	.nubusDataIn(nubusDataOut),
	.nubus_irq_n(nubus_irq_n),
	.cpuDataIn(cpuDataOut),
	.cpuDataOut(dataControllerDataOut),
	.cpuAddrRegHi(cpuAddr[12:9]),
	.cpuAddrRegMid(cpuAddr[6:4]),  // for SCSI
	.cpuAddrRegLo(cpuAddr[2:1]),
	.selectSCSI(selectSCSI),
	.selectSCC(selectSCC),
	.selectIWM(selectIWM),
	.selectVIA(selectVIA),
	.selectSEOverlay(selectSEOverlay),
	.cpuBusControl(cpuBusControl),
	.videoBusControl(videoBusControl),
	.memoryDataOut(memoryDataOut),
	.memoryDataIn(sdram_do),
	.memoryLatch(memoryLatch),

	// peripherals
	.ps2_key(ps2_key),
	.capslock(capslock),
	.ps2_mouse(ps2_mouse),
	// Mac II uses SCC, not UARTs - leave unconnected
	.serialIn(1'b1),
	.serialOut(),
	.serialCTS(1'b0),
	.serialRTS(),

	// rtc unix ticks
	.timestamp(TIMESTAMP),

	// Mac II has no built-in video (inputs still needed from addrController timing)
	._hblank(_hblank),
	._vblank(_vblank),
	.pixelOut(),
	.loadPixels(loadPixels),
	.vid_alt(vid_alt),

	.memoryOverlayOn(memoryOverlayOn),

	.audioOut(audio),
	.snd_alt(snd_alt),
	.loadSound(loadSound),

	// floppy disk interface
	.insertDisk({dsk_ext_ins, dsk_int_ins}),
	.diskSides({dsk_ext_ds, dsk_int_ds}),
	.diskEject(diskEject),
	.dskReadAddrInt(dskReadAddrInt),
	.dskReadAckInt(dskReadAckInt),
	.dskReadAddrExt(dskReadAddrExt),
	.dskReadAckExt(dskReadAckExt),
	.diskMotor(diskMotor),
	.diskAct(diskAct),

	// block device interface for scsi disk
	.img_mounted(img_mounted),
	.img_size(img_size[40:9]),
	.io_lba(sd_lba),
	.io_rd(sd_rd),
	.io_wr(sd_wr),
	.io_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr)
);

reg disk_act;
always @(posedge clk_sys) begin
	integer timeout = 0;

	if(timeout) begin
		timeout <= timeout - 1;
		disk_act <= 1;
	end else begin
		disk_act <= 0;
	end

	if(|diskAct) timeout <= 500000;
end

//////////////////////// DOWNLOADING ///////////////////////////

// include ROM download helper
wire dio_download;
wire [23:0] dio_addr = ioctl_addr[24:1];
wire  [7:0] dio_index;

// good floppy image sizes are 819200 bytes and 409600 bytes
reg dsk_int_ds, dsk_ext_ds;  // double sided image inserted
reg dsk_int_ss, dsk_ext_ss;  // single sided image inserted

// any known type of disk image inserted?
wire dsk_int_ins = dsk_int_ds || dsk_int_ss;
wire dsk_ext_ins = dsk_ext_ds || dsk_ext_ss;

// at the end of a download latch file size
// diskEject is set by macos on eject
always @(posedge clk_sys) begin
	reg old_down;

	old_down <= dio_download;
	if(old_down && ~dio_download && dio_index == 2) begin
		dsk_int_ds <= (dio_addr == 409600);   // double sides disk, addr counts words, not bytes
		dsk_int_ss <= (dio_addr == 204800);   // single sided disk
	end

	if(diskEject[0]) begin
		dsk_int_ds <= 0;
		dsk_int_ss <= 0;
	end
end

always @(posedge clk_sys) begin
	reg old_down;

	old_down <= dio_download;
	if(old_down && ~dio_download && dio_index == 3) begin
		dsk_ext_ds <= (dio_addr == 409600);   // double sided disk, addr counts words, not bytes
		dsk_ext_ss <= (dio_addr == 204800);   // single sided disk
	end

	if(diskEject[1]) begin
		dsk_ext_ds <= 0;
		dsk_ext_ss <= 0;
	end
end

// disk images are being stored right after os rom at word offset 0x80000 and 0x100000
reg [20:0] dio_a;
reg [15:0] dio_data;
reg        dio_write;

always @(posedge clk_sys) begin
	reg old_cyc = 0;

	if(ioctl_write) begin
		dio_data <= {ioctl_data[7:0], ioctl_data[15:8]};

		// ROM file mapping:
		// Index 0: boot0.rom (Mac II system ROM - 256K)
		// Index 1: boot1.rom (NuBus video card ROM - 32K)
		if (dio_index == 0) // boot0.rom - Mac II system ROM (256K)
			dio_a <= {3'b000, dio_addr[17:0]}; // Map to 0 (Slot 0 offset 0)
		else if (dio_index == 1) // boot1.rom - NuBus video ROM (passed directly to nubus_video)
			dio_a <= dio_addr[20:0]; // Pass through to ioctl interface
		else if (dio_index[1:0] == 2 || dio_index[1:0] == 3) // Floppy disk images at index 2,3
			dio_a <= {dio_index[1:0], dio_addr[18:0]};
		else
			dio_a <= {dio_index[6], dio_addr[17:0]};

		ioctl_wait <= 1;
	end

	old_cyc <= dioBusControl;
	if(~dioBusControl) dio_write <= ioctl_wait;
	if(old_cyc & ~dioBusControl & dio_write) ioctl_wait <= 0;
end


// sdram used for ram/rom maps directly into 68k address space
wire download_cycle = dio_download && dioBusControl;

////////////////////////// SDRAM /////////////////////////////////

// Route Mac system signals through arbiter
assign arb_mac_addr = download_cycle ? {4'b0001, dio_a[20:0] } :
                      ~_romOE        ? {4'b0001, 2'b00, 1'b0, memoryAddr[18:1]} : // Mac II ROM at SDRAM offset
                                       {3'b000, (dskReadAckInt || dskReadAckExt), memoryAddr[21:1]};

assign arb_mac_din  = download_cycle ? dio_data              : memoryDataOut;
assign arb_mac_ds   = download_cycle ? 2'b11                 : { !_memoryUDS, !_memoryLDS };
assign arb_mac_we   = download_cycle ? dio_write             : !_ramWE;
assign arb_mac_oe   = download_cycle ? 1'b0                  : (!_ramOE || !_romOE || dskReadAckInt || dskReadAckExt);

wire [15:0] sdram_do   = download_cycle ? 16'hffff : (dskReadAckInt || dskReadAckExt) ? extra_rom_data_demux : arb_mac_dout;

// during rom/disk download ffff is returned so the screen is black during download
// "extra rom" is used to hold the disk image. It's expected to be byte wide and
// we thus need to properly demultiplex the word returned from sdram in that case
wire [15:0] extra_rom_data_demux = memoryAddr[0]? {sdram_out[7:0],sdram_out[7:0]}:{sdram_out[15:8],sdram_out[15:8]};
wire [15:0] sdram_out;

assign SDRAM_CKE = 1;

// SDRAM Arbiter signals
wire [24:0] arb_mac_addr;
wire [15:0] arb_mac_din;
wire [15:0] arb_mac_dout;
wire  [1:0] arb_mac_ds;
wire        arb_mac_we;
wire        arb_mac_oe;

wire [24:0] arb_vram_addr;
wire [15:0] arb_vram_dout;
wire [15:0] arb_vram_din;
wire        arb_vram_rd;
wire        arb_vram_wr;
wire        arb_vram_ready;

wire [24:0] sdram_addr;
wire [15:0] sdram_din;
wire  [1:0] sdram_ds;
wire        sdram_we;
wire        sdram_oe;

sdram sdram
(
	// system interface
	.init           ( !pll_locked              ),
	.clk_64         ( clk_mem                  ),
	.clk_64_ps      ( clk_mem_ps               ),  // Phase-shifted clock for SDRAM chip
	.clk_8          ( clk8                     ),

	.sd_clk         ( SDRAM_CLK                ),
	.sd_data        ( SDRAM_DQ                 ),
	.sd_addr        ( SDRAM_A                  ),
	.sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs          ( SDRAM_nCS                ),
	.sd_ba          ( SDRAM_BA                 ),
	.sd_we          ( SDRAM_nWE                ),
	.sd_ras         ( SDRAM_nRAS               ),
	.sd_cas         ( SDRAM_nCAS               ),

	// cpu/chipset interface
	// map rom to sdram word address $200000 - $20ffff
	.din            ( sdram_din                ),
	.addr           ( sdram_addr               ),
	.ds             ( sdram_ds                 ),
	.we             ( sdram_we                 ),
	.oe             ( sdram_oe                 ),
	.dout           ( sdram_out                )
);

// SDRAM Arbiter - share SDRAM between Mac and NuBus video
sdram_arbiter arbiter (
	.clk(clk_sys),
	.reset(!pll_locked),  // Reset with SDRAM, not CPU
	
	// Mac system port
	.mac_addr(arb_mac_addr),
	.mac_din(arb_mac_din),
	.mac_dout(arb_mac_dout),
	.mac_ds(arb_mac_ds),
	.mac_we(arb_mac_we),
	.mac_oe(arb_mac_oe),
	
	// Video card port  
	.vram_addr(arb_vram_addr),
	.vram_dout(arb_vram_dout),
	.vram_din(arb_vram_din),
	.vram_rd(arb_vram_rd),
	.vram_wr(arb_vram_wr),
	.vram_ready(arb_vram_ready),
	
	// SDRAM controller
	.sdram_addr(sdram_addr),
	.sdram_din(sdram_din),
	.sdram_dout(sdram_out),
	.sdram_ds(sdram_ds),
	.sdram_we(sdram_we),
	.sdram_oe(sdram_oe)
);

endmodule