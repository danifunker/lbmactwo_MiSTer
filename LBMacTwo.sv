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
	"SC0,IMGVHDHDA,Mount SCSI-6;",
	"SC1,IMGVHDHDA,Mount SCSI-5;",
	"-;",
	"O78,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"OBC,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"O45,Memory,1MB,2MB,4MB,8MB;",
	"-;",
	"O6,Debug Overlay,Off,On;",
	"O13,NuBus Video,Color,B&W;",
	"-;",
	"R0,Reset & Apply CPU+Memory;",
	"-;",
	"v,0;", // [optional] config version 0-99.
	        // If CONF_STR options are changed in incompatible way, then change version number too,
			// so all options will get default values on first start.
	"V,v",`BUILD_DATE
};

wire status_turbo = 1'b1; // Mac II always runs at C15M = 15.6672 MHz (CPU rides clk16_en)
wire status_overlay_en = status[6];
wire status_video_mono = status[13];

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_mem;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk_mem),      // 62.6688 MHz, 0° - SDRAM controller
	.outclk_1(clk_sys),      // 31.3344 MHz, 180° - System (2 × C15M, divides to 15.6672/7.8336 MHz)
	.locked(pll_locked)
);

reg [1:0] status_mem;
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
		// Note: ~_cpuReset_o must NOT be here - that's the CPU's RESET instruction
		// output which resets peripherals only, not the CPU itself
		if(~pll_locked || osd_reset_req || buttons[1] || RESET || !clear_done) begin
			rst_cnt <= '1;
			n_reset <= 0;
		end
		else if(rst_cnt) begin
			rst_cnt    <= rst_cnt - 1'd1;
			status_mem <= status[5:4];
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
wire nubus_ce_pixel;
assign CE_PIXEL  = nubus_ce_pixel;

wire [15:0] nubusDataOut_card;
wire nubusAck_card;
wire nubus_irq_n;

// NuBus open-bus: empty slots return $FFFF with DTACK instead of bus error.
// The Slot Manager reads declaration ROM headers — $FF means "slot empty".
reg [3:0] nubus_timeout;
wire nubus_no_card = selectNuBus & nubusAck_card; // selected but card not responding
wire [15:0] nubusDataOut = nubus_no_card && nubus_timeout >= 4'd4 ? 16'hFFFF : nubusDataOut_card;
wire nubusAck = nubus_no_card && nubus_timeout >= 4'd4 ? 1'b0 : nubusAck_card;

always @(posedge clk_sys) begin
	if (_cpuAS)
		nubus_timeout <= 0;
	else if (nubus_no_card && nubus_timeout < 4'd15)
		nubus_timeout <= nubus_timeout + 1'd1;
end
wire [7:0] nubus_r, nubus_g, nubus_b;
wire nubus_hs, nubus_vs, nubus_blank;

// Mac II has NO built-in video - only NuBus video cards
assign VGA_R  = nubus_r;
assign VGA_G  = nubus_g;
assign VGA_B  = nubus_b;
assign VGA_DE = nubus_blank;
assign VGA_VS = nubus_vs;
assign VGA_HS = nubus_hs;
assign VGA_F1 = 0;
assign VGA_SL = 0;

wire [15:0] asc_audio_l, asc_audio_r;
assign AUDIO_L = asc_audio_l;
assign AUDIO_R = asc_audio_r;
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
localparam 	  configROMSize = 2'b10;  // 128K ROM

wire [1:0] configRAMSize = status_mem; // 00=1MB, 01=2MB, 10=4MB, 11=8MB
wire selectNuBus;

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
wire [22:0] memoryAddr;			// 23-bit byte address (8MB max RAM)
wire [15:0] memoryDataOut;
wire memoryLatch;

// peripherals
wire memoryOverlayOn, selectSCSI, selectSCSIDMA, scsiDREQ, selectSCC, selectIWM, selectVIA, selectVIA2, selectRAM, selectROM, selectSEOverlay, selectASC;
wire [1:0] glueRAMSize;
wire [15:0] dataControllerDataOut;

// MC68881 FPU
// Address decode: FC=7 (CPU space) + addr[31:16]=0x0002 + addr[15:13]=001 (cpID=1 for FPU)
wire fpuAddrMatch = (cpuFC == 3'b111) && (cpuAddr[31:16] == 16'h0002) && (cpuAddr[15:13] == 3'b001);
wire selectFPU = fpuAddrMatch && !_cpuAS;
wire [31:0] fpu_data_out;
wire fpu_dsack0_n, fpu_dsack1_n;
wire fpu_sense_n;

// CIR register address remapping: TG68K uses standard MC68881 register addresses,
// but mc68881_top uses non-standard addresses for registers that overlap with
// peripheral-mode registers (0-9). Remap the conflicting ones:
//   Standard reg 0 (Response CIR)  -> mc68881_top reg 13
//   Standard reg 2 (Save CIR)     -> mc68881_top reg 12
//   Standard reg 3 (Restore CIR)  -> mc68881_top reg 28
wire [4:0] fpu_addr_remapped = (cpuAddr[5:1] == 5'd0) ? 5'd13 :
                               (cpuAddr[5:1] == 5'd2) ? 5'd12 :
                               (cpuAddr[5:1] == 5'd3) ? 5'd28 :
                               cpuAddr[5:1];


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

// VPA: FC=7 cycles get autovector EXCEPT FPU coprocessor accesses (which use DTACK/DSACK)
// Also assert VPA for 32-bit VIA/VIA2 accesses ($50F0xxxx) so VMA handshake occurs
wire viaAccess = selectVIA | selectVIA2;
assign      _cpuVPA = (cpuFC == 3'b111 && !selectFPU) ? 1'b0 :
                      viaAccess ? ~(!_cpuAS) :
                      ~(!_cpuAS && cpuAddr[23:21] == 3'b111);
// DTACK: FPU uses DSACK protocol (assert DTACK when either DSACK line goes low)
// Do not assert DTACK for VIA accesses — they use VPA/VMA synchronous handshake
// COHERENCY FIX: the SDRAM is shared with the NuBus video card through
// sdram_arbiter, and ~50% of Mac reads begin while video holds the SDRAM
// (sdram_dout = the video word, not Mac's data). With the old immediate
// "turbo" DTACK the CPU latched that video word and executed/used corrupted
// data. For a RAM/ROM READ, defer DTACK until the arbiter asserts
// mac_dout_valid (a clean SDRAM slot completed with the Mac's address).
// grant_video = !mac_active means the Mac wins the next slot the instant it
// asserts, so this always releases within ~1-2 SDRAM cycles. Writes and the
// turbo fast path are unchanged.
wire ram_or_rom_dtack_raw = (~(!_cpuAS && cpuAddr[23:21] != 3'b111) | (status_turbo & !turbo_dtack_en));
wire mac_is_sdram_read    = (!_ramOE || !_romOE);
wire ram_or_rom_dtack     = (mac_is_sdram_read && !arb_mac_dout_valid) ? 1'b1
                                                                       : ram_or_rom_dtack_raw;
assign      _cpuDTACK = selectFPU ? (fpu_dsack0_n & fpu_dsack1_n) :
                        selectNuBus ? nubusAck :
                        selectSCSIDMA ? ~scsiDREQ :
                        viaAccess ? 1'b1 :
                        ram_or_rom_dtack;

// Debug LED tracking - extended duration for visibility
reg [27:0] nubus_act_ctr, mem_act_ctr, video_act_ctr;
wire nubus_access = selectNuBus && !_cpuAS;
wire mem_access = (selectRAM || selectROM) && !_cpuAS;
wire video_active = !nubus_blank;

always @(posedge clk_sys) begin
	if (nubus_access) nubus_act_ctr <= 28'hFFFFFFF;  // ~8.6 seconds at 31.3344 MHz
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
// Mac II HMMU address translation: VIA2 PB3 low enables 24-bit mapping
// onto the 32-bit bus. Bypassed for FC=7 CPU-space cycles (coprocessor
// CIR dialog must see the raw address).
wire        hmmu_active;
wire [31:0] cpuAddr_xlated;
hmmu u_hmmu(.addr_in(tg68_a), .active(hmmu_active), .addr_out(cpuAddr_xlated));
assign      cpuAddr       = (cpuFC == 3'b111) ? tg68_a : cpuAddr_xlated;
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
wire        tg68_longword;

// Bus error timeout — undecoded addresses trigger bus error after ~8us
reg [8:0] berr_counter;
reg berr_out;
wire nubus_acked = selectNuBus & ~nubusAck;  // NuBus card actually responding
wire scsi_dma_wait = selectSCSIDMA && !scsiDREQ;
wire any_select = selectRAM | selectROM | selectVIA | selectVIA2 | selectSCC
                | (selectSCSI && !scsi_dma_wait) | selectIWM | selectASC | nubus_acked | selectSEOverlay | selectFPU;
wire is_cpu_space = (cpuFC == 3'b111);

always @(posedge clk_sys) begin
	if (!_cpuReset) begin
		berr_counter <= 0;
		berr_out <= 0;
	end else begin
		if (_cpuAS) begin
			berr_counter <= 0;
			berr_out <= 0;
		end else if (berr_out) begin
			// Hold BERR until AS deasserts (CPU ends bus cycle)
		end else if (is_cpu_space || any_select)
			berr_counter <= 0;
		else if (berr_counter == 9'd251)  // ~8us at 31.3344 MHz
			begin berr_out <= 1; berr_counter <= 0; end
		else
			berr_counter <= berr_counter + 1'd1;
	end
end

// TG68K samples read data at the end of the bus cycle.  Hold FPU read data
// after AS releases so the CPU does not see the normal data-controller mux.
reg [15:0] fpu_data_hold;
reg fpu_data_hold_valid;
always @(posedge clk_sys) begin
	if (!_cpuReset) begin
		fpu_data_hold <= 16'h0000;
		fpu_data_hold_valid <= 1'b0;
	end else if (!_cpuAS && selectFPU && _cpuRW) begin
		fpu_data_hold <= fpu_data_out[15:0];
		fpu_data_hold_valid <= 1'b1;
	end else if (!_cpuAS && !selectFPU) begin
		fpu_data_hold_valid <= 1'b0;
	end
end

wire [15:0] cpu_data_in = berr_inhibit_active ? berr_data_out[15:0] :
                          selectFPU ? fpu_data_out[15:0] :
                          fpu_data_hold_valid ? fpu_data_hold :
                          dataControllerDataOut;

tg68k tg68k_inst (
	.clk        ( clk_sys      ),
	.reset      ( !_cpuReset   ),
	.phi1       ( cpu_en_p     ),
	.phi2       ( cpu_en_n     ),
	.cpu        ( 2'b11        ), // 68020 mode (cpu(0) must be 1 for VBR support)

	.dtack_n    ( _cpuDTACK    ),
	.rw_n       ( tg68_rw      ),
	.as_n       ( tg68_as_n    ),
	.uds_n      ( tg68_uds_n   ),
	.lds_n      ( tg68_lds_n   ),
	.fc         ( { tg68_fc2, tg68_fc1, tg68_fc0 } ),
	.reset_n    ( tg68_reset_n ),

	.E          (              ),
	.E_div      ( status_turbo ),
	.E_PosClkEn ( tg68_E_falling ),
	.E_NegClkEn ( tg68_E_rising  ),
	.vma_n      ( tg68_vma_n   ),
	.vpa_n      ( _cpuVPA      ),

	.br_n       ( 1'b1         ),
	.bg_n       (              ),
	.bgack_n    ( 1'b1         ),

	.ipl        ( _cpuIPL      ),
	.berr       ( berr_inhibit_active ? 1'b0 : berr_out ),
		.din        ( cpu_data_in   ),
		.dout       ( tg68_dout    ),
		.longword   ( tg68_longword ),
		.addr       ( tg68_a       ),
	.berr_inhibit ( berr_inhibit_active ),
	.berr_data    ( berr_data_out      )
);

wire berr_inhibit_active;
wire [31:0] berr_data_out;

// MC68881 FPU - CIR dialog mode (coprocessor protocol via TG68K)
// Data bus: TG68K is 16-bit; CIR protocol uses d_in[15:0] for writes, d_out[15:0] for reads
// size_n=2'b01 indicates word-sized (16-bit) transfers (active-low encoding)
// sense_n is an inout driven by the FPU internally to indicate presence

mc68881_fpu_lite fpu_inst (
	.clk        ( clk_sys              ),
	.reset_n    ( _cpuReset            ),
	.a_in       ( fpu_addr_remapped    ),
	.d_in       ( {16'h0000, cpuDataOut} ),
	.d_out      ( fpu_data_out         ),
	.size_n     ( 2'b01                ),  // word-sized transfers
	.as_n       ( _cpuAS               ),
	.cs_n       ( ~fpuAddrMatch        ),
	.rw         ( _cpuRW               ),
	.ds_n       ( _cpuUDS & _cpuLDS    ),  // active when either byte lane selected
	.dsack0_n   ( fpu_dsack0_n         ),
	.dsack1_n   ( fpu_dsack1_n         ),
	.sense_n    ( fpu_sense_n          ),
	.status_valid (                    )
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
	.glueRAMSize(glueRAMSize),
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
	.selectSCSIDMA(selectSCSIDMA),
	.selectSCC(selectSCC),
	.selectIWM(selectIWM),
	.selectVIA(selectVIA),
	.selectVIA2(selectVIA2),
	.selectRAM(selectRAM),
	.selectROM(selectROM),
	.selectSEOverlay(selectSEOverlay),
	.selectNuBus(selectNuBus),
	.selectASC(selectASC),
	.hsync(hsync),
	.vsync(vsync),
	._hblank(_hblank),
	._vblank(_vblank),
	.loadPixels(loadPixels),
	.vid_alt(vid_alt),
	.memoryOverlayOn(memoryOverlayOn),

	.dskReadAddrInt(dskReadAddrInt),
	.dskReadAckInt(dskReadAckInt),
	.dskReadAddrExt(dskReadAddrExt),
	.dskReadAckExt(dskReadAckExt)
);

wire [1:0] diskEject;
wire [1:0] diskMotor, diskAct;

nubus_video_mdc824 nubus_card (
	.clk(clk_sys),
	.reset(!_cpuReset),
	.addr(cpuAddr),
	.data_in(cpuDataOut),
	.data_out(nubusDataOut_card),
	.uds_lds({!_cpuUDS, !_cpuLDS}),
	.cpu_longword(tg68_longword),
	.rw_n(_cpuRW),
	.cpu_as_n(_cpuAS),
	.select(selectNuBus),
	.ack_n(nubusAck_card),
	.vga_r(nubus_r),
	.vga_g(nubus_g),
	.vga_b(nubus_b),
	.vga_hs(nubus_hs),
	.vga_vs(nubus_vs),
	.vga_blank(nubus_blank),
	.vga_clk(),
	.ce_pixel(nubus_ce_pixel),
	.nmrq_n(nubus_irq_n),

	// Dedicated on-chip VRAM (vram_ram).  The framebuffer no longer lives in
	// shared SDRAM, so the scanout never competes with the Mac for SDRAM and
	// always reads coherent data (Mac keeps SDRAM to itself).  Card outputs
	// (addr/dout/rd/wr) drive the BRAM; read data/ready come back from it.
	.vram_addr(arb_vram_addr),
	.vram_dout(arb_vram_dout),
	.vram_din(vram_bram_din),
	.vram_rd(arb_vram_rd),
	.vram_wr(arb_vram_wr),
	.vram_ready(vram_bram_ready),

	// VRAM port B — dedicated scanout read (no cache, never misses)
	.vram_scan_addr(vram_scan_addr),
	.vram_scan_rd(vram_scan_rd),
	.vram_scan_data(vram_scan_data),

	.overlay_en(status_overlay_en),
	.monochrome(status_video_mono),

	.ioctl_wr(ioctl_write),
	.ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_data),
	.ioctl_download(dio_download),
	.ioctl_index(dio_index),

	// JTAG debug exposures
	.dbg_video_en(dbg_video_en),
	.dbg_vram_wr_cnt(dbg_vram_wr_cnt),
	.dbg_vram_fetch_cnt(dbg_vram_fetch_cnt),
	.dbg_irq_cnt(dbg_card_irq_cnt),
	.dbg_ack_cnt(dbg_card_ack_cnt),
	.dbg_vblank_enable(dbg_card_vbl_en)
);
wire        dbg_video_en;
wire [15:0] dbg_vram_wr_cnt;
wire [15:0] dbg_vram_fetch_cnt;
wire [15:0] dbg_card_irq_cnt;
wire [15:0] dbg_card_ack_cnt;
wire        dbg_card_vbl_en;
wire        dbg_asc_irq_n;

dataController_top #(SCSI_DEVS) dc0
(
	.clk32(clk_sys),
	.clk8_en_p(clk8_en_p),
	.clk8_en_n(clk8_en_n),
	.clk16_en_p(clk16_en_p),
	.clk16_en_n(clk16_en_n),
	.E_rising(E_rising),
	.E_falling(E_falling),
	.machineType(1'b1), // Mac II mode
	.macModel(3'd2),    // Mac II (non-FDHD)
	.configRAMSize(configRAMSize),
	._systemReset(n_reset),
	._cpuReset(_cpuReset),
	._cpuIPL(_cpuIPL),
	._cpuUDS(_cpuUDS),
	._cpuLDS(_cpuLDS),
	._cpuRW(_cpuRW),
	.cpuLongword(tg68_longword),
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
	.selectSCSIDMA(selectSCSIDMA),
	.scsiDREQ(scsiDREQ),
	.selectSCC(selectSCC),
	.selectIWM(selectIWM),
	.selectVIA(selectVIA),
	.selectVIA2(selectVIA2),
	.selectSEOverlay(selectSEOverlay),
	.selectASC(selectASC),
	.cpuAddrASC(cpuAddr[12:0]),
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
	.glueRAMSize(glueRAMSize),
	.hmmu_active(hmmu_active),

	.ascAudioLeft(asc_audio_l),
	.ascAudioRight(asc_audio_r),
	.dbg_asc_irq_n(dbg_asc_irq_n),

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
	.sd_buff_wr(sd_buff_wr),
	.dbg_scsi(dbg_scsi),
	.dbg_scsi2(dbg_scsi2),
	.dbg_scsi3(dbg_scsi3),
	.dbg_scsi4(dbg_scsi4),
	.dbg_scsi5(dbg_scsi5),
	.dbg_adb(dbg_adb),
	.dbg_adb2(dbg_adb2),
	.dbg_adb3(dbg_adb3),
	.dbg_adb4(dbg_adb4),
	.mouse_has_event_o(adb_mouse_has_event)
);
wire [15:0] dbg_scsi;
wire [15:0] dbg_scsi2;
wire [15:0] dbg_scsi3;
wire [15:0] dbg_scsi4;
wire [15:0] dbg_scsi5;
wire [31:0] dbg_adb;
wire [17:0] dbg_adb2;
wire [31:0] dbg_adb3;
wire [31:0] dbg_adb4;
wire        adb_mouse_has_event;

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

// Boot-ROM load gate. On a cold/menu load the HPS streams boot0.rom (idx 0)
// into memory AFTER the FPGA configures, concurrently with the CPU coming out
// of its blind ~134ms reset timer. If the CPU starts executing before the ROM
// download finishes it runs early POST against a partially-loaded ROM -> the
// startup chime plays garbled AND ROM low-memory state is clobbered, which
// later leaves the ADB mouse cursor frozen (ADB enumeration itself reads back
// clean because the download has finished by then). A soft restart re-runs POST
// with the ROM already resident, so it works -> the classic "mouse only works
// after a reboot" symptom. Hold CPU reset until boot0.rom has fully loaded.
// Latches once and stays set, so runtime disk mounts (idx 2/3) never reset.
reg rom_loaded = 0;
always @(posedge clk_sys) begin
	reg old_down;
	reg saw_rom0;
	old_down <= dio_download;
	if(dio_download && dio_index == 0) saw_rom0 <= 1'b1;   // boot0.rom streaming
	if(old_down && ~dio_download && saw_rom0) rom_loaded <= 1'b1; // finished
end

// === Cold-boot RAM pre-clear =============================================
// After boot0.rom finishes loading and before the CPU is released, zero all
// configured RAM. On a warm soft-restart the prior boot already left clean
// low-memory state in SDRAM, so the mouse/ADB globals are valid; a cold/menu
// boot starts with garbage RAM. Pre-clearing here gives every cold boot the
// same clean low memory a warm restart has — which (paired with a no-memtest
// ROM) fixes the cold-boot garbled chime + frozen mouse without relying on the
// ROM's own RAM test. Paced exactly like the ROM download (one SDRAM write per
// extra bus slot via dioBusControl), reusing the proven download write timing.
// Word-address limit by configured RAM size (RAM lives in the A22=0 region):
wire [21:0] clear_limit = (configRAMSize == 2'b00) ? 22'h07FFFF :  // 1MB
                          (configRAMSize == 2'b01) ? 22'h0FFFFF :  // 2MB
                          (configRAMSize == 2'b10) ? 22'h1FFFFF :  // 4MB
                                                     22'h3FFFFF;   // 8MB
reg [21:0] clear_addr   = 0;
reg        clear_active = 0;
reg        clear_done   = 0;
reg        clear_write  = 0;
reg        clear_old_cyc = 0;
always @(posedge clk_sys) begin
	if(!rom_loaded) begin
		clear_active  <= 1'b0;
		clear_done    <= 1'b0;
		clear_addr    <= 22'd0;
		clear_write   <= 1'b0;
		clear_old_cyc <= 1'b0;
	end else begin
		if(!clear_done && !clear_active) clear_active <= 1'b1;   // start once ROM is loaded
		clear_old_cyc <= dioBusControl;
		if(clear_active) begin
			if(~dioBusControl) clear_write <= 1'b1;                  // arm write before the slot
			if(clear_old_cyc & ~dioBusControl & clear_write) begin   // extra slot just completed
				clear_write <= 1'b0;
				if(clear_addr == clear_limit) begin
					clear_active <= 1'b0;
					clear_done   <= 1'b1;
				end else begin
					clear_addr <= clear_addr + 22'd1;
				end
			end
		end
	end
end
wire clear_cycle = clear_active && dioBusControl;

// disk images are being stored right after os rom at word offset 0x80000 and 0x100000
reg [20:0] dio_a;
reg [15:0] dio_data;
reg        dio_write;

always @(posedge clk_sys) begin
	reg old_cyc = 0;

	if(ioctl_write) begin
		dio_data <= {ioctl_data[7:0], ioctl_data[15:8]};

		// ROM/disk download address mapping:
		// Index 0: boot0.rom (Mac II system ROM - 256K). The NuBus video card
		// declaration ROM is baked into the bitstream via $readmemh (boot1.hex /
		// boot2.hex), so no index-1 download exists on hardware (the Verilator
		// sim has its own separate top in verilator/sim.v).
		if (dio_index == 0) // boot0.rom - Mac II system ROM (256K)
			dio_a <= {3'b000, dio_addr[17:0]}; // Map to 0 (Slot 0 offset 0)
		else if (dio_index[1:0] == 2 || dio_index[1:0] == 3) // Floppy disk images at indices 2,3
			dio_a <= {(dio_index[1:0] - 2'd1), dio_addr[18:0]};
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

// Route Mac system signals through arbiter.
//
// SDRAM word-address map (8MB-capable):
//   RAM        : 0x000000 - 0x3FFFFF (A22=0)  — up to 4M words = 8MB
//   ROM / disk : 0x400000 +          (A22=1)  — moved above RAM so it no longer
//                                               collides with the 8MB RAM window
//                                               (it used to sit at A21=0x200000,
//                                               inside the 8MB RAM span).
assign arb_mac_addr = clear_cycle    ? {3'b000, clear_addr} :                       // RAM pre-clear @ 0x000000+
                      download_cycle ? {2'b00, 1'b1, 1'b0, dio_a[20:0] } :          // ROM/disk download @ 0x400000+
                      ~_romOE        ? {2'b00, 1'b1, 4'b0000, memoryAddr[18:1]} :    // Mac II ROM @ 0x400000+
                      (dskReadAckInt || dskReadAckExt) ? {2'b00, 1'b1, 1'b0, memoryAddr[21:1]} : // disk image @ 0x400000+
                                       {3'b000, memoryAddr[22:1]};                   // RAM 0x000000-0x3FFFFF (8MB)

assign arb_mac_din  = clear_cycle ? 16'h0000 : download_cycle ? dio_data  : memoryDataOut;
assign arb_mac_ds   = clear_cycle ? 2'b11    : download_cycle ? 2'b11     : { !_memoryUDS, !_memoryLDS };
assign arb_mac_we   = clear_cycle ? clear_write : download_cycle ? dio_write : !_ramWE;
assign arb_mac_oe   = clear_cycle ? 1'b0     : download_cycle ? 1'b0      : (!_ramOE || !_romOE || dskReadAckInt || dskReadAckExt);

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
wire        arb_mac_dout_valid;  // Mac read data-valid (coherency fix)

wire [24:0] arb_vram_addr;
wire [15:0] arb_vram_dout;
wire [15:0] arb_vram_din;   // (legacy SDRAM-VRAM read path; now unused)
wire        arb_vram_rd;
wire        arb_vram_wr;
wire        arb_vram_ready;  // (legacy; now unused)

// Dedicated on-chip VRAM for the NuBus video card (replaces shared-SDRAM
// framebuffer).  The card's VRAM port drives this BRAM directly; the SDRAM
// arbiter's video port is tied off below so the Mac owns SDRAM exclusively.
wire [15:0] vram_bram_din;
wire        vram_bram_ready;
wire [24:0] vram_scan_addr;
wire        vram_scan_rd;
wire [15:0] vram_scan_data;
vram_ram #(.AW(16)) vram_inst (   // 2^16 words = 128 KB (1/2 bpp @ 640x480; dual-port)
	.clk    (clk_sys),
	// Port A — CPU read/write (card FSM)
	.addr   (arb_vram_addr),
	.din    (arb_vram_dout),
	.dout   (vram_bram_din),
	.rd     (arb_vram_rd),
	.wr     (arb_vram_wr),
	.ready  (vram_bram_ready),
	// Port B — dedicated scanout read
	.addr_b (vram_scan_addr),
	.rd_b   (vram_scan_rd),
	.dout_b (vram_scan_data)
);

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
	.clk8_en_p(clk8_en_p),  // SDRAM cycle T0 marker for the coherency handshake
	.reset(!pll_locked),  // Reset with SDRAM, not CPU

	// Mac system port
	.mac_addr(arb_mac_addr),
	.mac_din(arb_mac_din),
	.mac_dout(arb_mac_dout),
	.mac_ds(arb_mac_ds),
	.mac_we(arb_mac_we),
	.mac_oe(arb_mac_oe),

	// Video card port — TIED OFF.  VRAM now lives in dedicated on-chip BRAM
	// (vram_ram), not shared SDRAM, so the arbiter never grants video and the
	// Mac owns SDRAM exclusively (no contention, no coherency races).
	.vram_addr(25'd0),
	.vram_dout(16'd0),
	.vram_din(arb_vram_din),
	.vram_rd(1'b0),
	.vram_wr(1'b0),
	.vram_ready(arb_vram_ready),

	// SDRAM controller
	.sdram_addr(sdram_addr),
	.sdram_din(sdram_din),
	.sdram_dout(sdram_out),
	.sdram_ds(sdram_ds),
	.sdram_we(sdram_we),
	.sdram_oe(sdram_oe),

	// Debug exposures (unused on this branch)
	.dbg_grant_video(),
	.dbg_video_clean(),
	.dbg_mac_idle_cnt(),
	.dbg_vram_state(),
	.mac_stall(),

	// Mac READ data-valid handshake (coherency fix)
	.mac_dout_valid(arb_mac_dout_valid)
);

// Minimal JTAG CPU-state probes to diagnose the early-boot hang.
dbg_min dbg_min_inst (
	.clk            (clk_sys),
	.cpuAddr        (cpuAddr),
	.cpuFC          (cpuFC),
	.cpuAS_n        (_cpuAS),
	.cpuRW          (_cpuRW),
	.cpuDTACK_n     (_cpuDTACK),
	.cpuUDS_n       (_cpuUDS),
	.cpuLDS_n       (_cpuLDS),
	.selectFPU      (selectFPU),
	.selectRAM      (selectRAM),
	.selectROM      (selectROM),
	.selectNuBus    (selectNuBus),
	.fpu_dsack0_n   (fpu_dsack0_n),
	.fpu_dsack1_n   (fpu_dsack1_n),
	.mac_dout_valid (arb_mac_dout_valid),
	.video_en       (dbg_video_en),
	.vram_wr_cnt    (dbg_vram_wr_cnt),
	.vram_fetch_cnt (dbg_vram_fetch_cnt),
	.selectSCSI     (selectSCSI),
	.scsi_rd_data   (dataControllerDataOut),
	.img_mounted    (img_mounted),
	.sd_rd          (sd_rd),
	.sd_wr          (sd_wr),
	.sd_ack         (sd_ack),
	.scsi_dbg       (dbg_scsi),
	.scsi_dbg2      (dbg_scsi2),
	.scsi_dbg3      (dbg_scsi3),
	.scsi_dbg4      (dbg_scsi4),
	.scsi_dbg5      (dbg_scsi5),
	.sd_buff_dout   (sd_buff_dout),
	.sd_buff_addr   (sd_buff_addr),
	.sd_buff_wr     (sd_buff_wr),
	.cpuIPL_n       (_cpuIPL),
	.berr           (berr_out),
	.ioctl_wr       (ioctl_write),
	.ioctl_idx      (dio_index[7:0]),
	.dbg_adb        (dbg_adb),
	.dbg_adb2       (dbg_adb2),
	.dbg_adb3       (dbg_adb3),
	.dbg_adb4       (dbg_adb4),
	.ps2_mouse      (ps2_mouse),
	.mouse_has_event(adb_mouse_has_event),
	// Audio-regression diagnosis
	.selectASC      (selectASC),
	.asc_irq_n      (dbg_asc_irq_n),
	.asc_audio_l    (asc_audio_l),
	.card_irq_cnt   (dbg_card_irq_cnt),
	.card_ack_cnt   (dbg_card_ack_cnt),
	.card_vbl_en    (dbg_card_vbl_en)
);

endmodule
