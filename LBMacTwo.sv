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
	"F1,DSK,Mount Floppy;",
	"-;",
	"SC0,IMGVHDHDA,Mount SCSI-0;",
	"SC1,IMGVHDHDA,Mount SCSI-1;",
	"SC2,NVR,Mount PRAM (reboots);",
	"-;",
	"O78,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"OBC,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"O45,Memory,2MB,4MB,8MB;",
	"-;",
	"O6,Debug Overlay,Off,On;",
	"O13,NuBus Video,Color,B&W;",
	"OG,Monitor,640x480 13in,512x384 12in;",
	"-;",
	"RE,Interrupt (NMI / MacsBug);",
	"RF,Reset PRAM & Core;",
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
// OSD "Monitor" select (status bit 16 = OSD char 'G'): which monitor the
// MDC824 card advertises on its sense lines. Takes effect on the next Mac
// reboot (the Slot Manager / card declaration ROM probes sense at boot).
wire status_monitor_512 = status[16];

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

// ---- PLL-lock-stable reset synchronizer ------------------------------------
// pll_locked is a raw PLL output in an asynchronous domain.  Consuming it
// directly inside clk_sys logic (and as sdram.init / arbiter.reset) means the
// very clock that is unstable during a lock event also clocks the machine that
// is supposed to be holding everything in reset — and on relock there is no
// defined settle window.  Synchronize it into clk_sys and hold reset for a
// fixed number of STABLE clk_sys cycles after lock, so every configure (cold or
// warm) and every unlock-recovery presents the same clean, fully-settled
// release.  Drives the machine reset, the SDRAM controller init, the arbiter
// reset and the PRAM/clear sequencers — i.e. the whole init choreography keys
// off one debounced lock signal instead of the raw PLL output.
reg [1:0]  lock_sync = 2'b00;   // 2-FF synchronizer for pll_locked into clk_sys
reg [9:0]  lock_hold = 10'd0;   // settle counter after lock (~1024 clk_sys ≈ 33us)
reg        sys_locked = 1'b0;   // lock-stable: clk_sys has run a full settle since lock
always @(posedge clk_sys or negedge pll_locked) begin
	if (!pll_locked) begin
		lock_sync  <= 2'b00;
		lock_hold  <= 10'd0;
		sys_locked <= 1'b0;
	end else begin
		lock_sync <= {lock_sync[0], 1'b1};
		if (lock_sync[1]) begin
			if (lock_hold == 10'h3FF) sys_locked <= 1'b1;
			else                      lock_hold  <= lock_hold + 1'b1;
		end
	end
end

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
		// output which resets peripherals only, not the CPU itself.
		// !pram_ready holds the machine until the PRAM image mount status is
		// known (the ROM reads the clock chip early in boot) — released by the
		// PRAM FSM on load/no-image/backstop, see the PRAM persistence block.
		if(!sys_locked || osd_reset_req || buttons[1] || RESET || !clear_done || pram_force_reset || !pram_ready) begin
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

localparam SCSI_DEVS = 2;          // SCSI block devices -> hps_io slots 0,1
localparam VD_PRAM   = 2;          // PRAM NVRAM save image -> hps_io slot 2
localparam VDNUM     = 3;          // total hps_io block devices

// the status register is controlled by the on screen display (OSD)
wire [31:0] status;
wire  [1:0] buttons;

// hps_io block-device buses (all VDNUM devices)
wire [31:0] sd_lba[VDNUM];
wire  [VDNUM-1:0] sd_rd;
wire  [VDNUM-1:0] sd_wr;
wire  [VDNUM-1:0] sd_ack;
// Full WIDE-mode width from hps_io ([12:0]): [7:0] serves every 512-byte
// consumer; [12:8] reach the CD whole-frame burst path (2352 B/txn) once the
// CD slot is wired (MacLC transplant seam — dormant until then).
wire           [12:0] sd_buff_addr;
wire           [15:0] sd_buff_dout;
wire           [15:0] sd_buff_din[VDNUM];
wire                  sd_buff_wr;
wire  [VDNUM-1:0] img_mounted;
wire           [63:0] img_size;

// SCSI side (slots 0,1): separate buses driven by dataController, stitched
// into the shared hps_io buses so the PRAM save image (slot 2) can coexist.
wire [31:0] scsi_lba[SCSI_DEVS];
wire  [SCSI_DEVS-1:0] scsi_rd, scsi_wr;
wire           [15:0] scsi_buff_din[SCSI_DEVS];
assign sd_lba[0]      = scsi_lba[0];
assign sd_lba[1]      = scsi_lba[1];
assign sd_rd[1:0]     = scsi_rd;
assign sd_wr[1:0]     = scsi_wr;
assign sd_buff_din[0] = scsi_buff_din[0];
assign sd_buff_din[1] = scsi_buff_din[1];

wire        ioctl_write;
reg         ioctl_wait = 0;

wire [10:0] ps2_key;
wire [24:0] ps2_mouse;
wire        capslock;

wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;

wire [32:0] TIMESTAMP;

// =====================================================================
// PRAM persistence (NVRAM) — autosave to a mounted save image (slot 2).
//   load  : when the PRAM image mounts (img_mounted[VD_PRAM], size>0)
//   flush : when the OSD opens and PRAM changed since the last save
//   RF    : "Reset PRAM & Core" — zero PRAM, flush zeros, reboot the machine
// One 512-byte sector at LBA 0 holds the 256 PRAM bytes (rest padded).
// The 343-0042 clock chip (rtl/rtc.v, serial behind VIA1 port B) owns the
// canonical pram[]; we shuttle it through pram_buf via the pram_load_*/
// pram_save_* ports threaded through dataController_top. Mechanism ported
// from MacLC_MiSTer — there the PRAM owner is the Egret MCU; the Mac II
// has no Egret, its XPRAM lives in the discrete RTC chip (MAME macii.cpp
// RTC3430042 / Snow macii via1.rtc). SD handshake mirrors scsi.v: drop
// rd/wr on io_ack rising, sector done on io_ack falling.
// =====================================================================
reg        pram_load_wr;
reg  [7:0] pram_load_addr, pram_load_data, pram_save_addr;
wire [7:0] pram_save_data;
wire       pram_wr_stb;

reg        pram_rd, pram_wr_req;
wire       pram_ack = sd_ack[VD_PRAM];
assign sd_lba[VD_PRAM] = 32'd0;             // single 512B sector at LBA 0
assign sd_rd [VD_PRAM] = pram_rd;
assign sd_wr [VD_PRAM] = pram_wr_req;

localparam [3:0] P_IDLE=0, P_LD_RD=1, P_LD_DAT=2, P_LD_ADDR=3,
                 P_FILL=4, P_SV_WR=5, P_SV_DAT=6, P_CLR=7, P_RST=8,
                 P_LD_B0=9, P_LD_B1=10, P_FILL2=11, P_FILL3=12;
reg  [3:0] pst;
reg  [8:0] pcnt;
reg  [6:0] rst_hold;

// Staging buffer <-> SD sector: 128x16 BRAM words, word = {odd byte, even
// byte}. NOT a byte array — the old reg[7:0] buf[0:255] with async reads
// cost ~2K registers + wide muxes and helped blow the 2026-06-12 LAB
// budget. Single write port (SD capture / save pack / PRAM clear are
// mutually exclusive in time) + single registered read port shared by the
// HPS readback and the load FSM — the same 1-cycle readback latency
// scsi_dpram already proves against hps_io on the SCSI save path.
(* ramstyle = "no_rw_check" *) reg [15:0] pram_buf16[0:127];
reg [15:0] pbuf_q;
reg  [7:0] fill_lo;        // even-byte latch while packing save words

// read port (load FSM states steal the address; HPS only reads during save)
wire pram_loading = (pst == P_LD_ADDR) || (pst == P_LD_B0) || (pst == P_LD_B1);
wire [6:0] pbuf_raddr = pram_loading ? pcnt[7:1] : sd_buff_addr[6:0];
always @(posedge clk_sys)
	pbuf_q <= pram_buf16[pbuf_raddr];
assign sd_buff_din[VD_PRAM] = (sd_buff_addr < 8'd128) ? pbuf_q : 16'h0000;

// write port
always @(posedge clk_sys) begin
	if (pram_ack && sd_buff_wr && sd_buff_addr < 8'd128)
		pram_buf16[sd_buff_addr[6:0]] <= sd_buff_dout;             // SD capture
	else if (pst == P_FILL3 && pcnt[0])
		pram_buf16[pcnt[7:1]] <= {pram_save_data, fill_lo};        // save pack
	else if (pst == P_CLR)
		pram_buf16[pcnt[7:1]] <= 16'h0000;                         // PRAM reset
end

reg        pram_ena;                        // a save image is mounted (size>0)
reg        pram_dirty;                      // PRAM changed since last save
reg        pram_rst_after;                  // pulse reset after the current save
reg        pram_load_pending, pram_flush_pending, pram_clr_pending;
reg        pram_late_load;   // image loaded AFTER boot released -> reboot to apply
reg        old_pack, old_osd, old_mnt2, old_rstpram;
reg        pram_ready;        // releases n_reset: pram[] loaded (or no image / timed out)
reg [31:0] pram_rdy_cnt;      // ready backstop so a missing image never delays boot long
reg        pram_force_reset;  // "Reset PRAM & Core" / late PRAM load -> system reset pulse

always @(posedge clk_sys) begin
	if (!sys_locked) begin
		pst <= P_IDLE; pram_rd <= 0; pram_wr_req <= 0; pram_load_wr <= 0;
		pram_ena <= 0; pram_dirty <= 0; pram_force_reset <= 0; pram_rst_after <= 0;
		pram_load_pending <= 0; pram_flush_pending <= 0; pram_clr_pending <= 0;
		pram_late_load <= 0;
		old_pack <= 0; old_osd <= 0; old_mnt2 <= 0; old_rstpram <= 0; rst_hold <= 0;
		pram_ready <= 0; pram_rdy_cnt <= 0;
	end else begin
		old_pack    <= pram_ack;
		old_osd     <= OSD_STATUS;
		old_mnt2    <= img_mounted[VD_PRAM];
		old_rstpram <= status[15];
		pram_load_wr <= 1'b0;                  // default low; pulsed in copy/clear
		// (SD-sector capture into pram_buf16 lives in the dedicated BRAM
		// write-port block above, not here.)

		// Mac-side clock-chip PRAM writes mark the image dirty
		if (pram_wr_stb) pram_dirty <= 1'b1;

		// event latches
		if (img_mounted[VD_PRAM] && !old_mnt2) begin
			// Only accept a real PRAM image: a .NVR is exactly 512 bytes
			// (allow a little slack). Anything big is a DISK mounted into
			// the PRAM slot by accident (e.g. an old .mgl with type="s"
			// index="2" — iotest.mgl does this): loading it would feed
			// garbage PRAM, and the OSD-open flush would overwrite its
			// sector 0 (the Driver Descriptor Map) with PRAM bytes =
			// instant disk corruption. Refuse: no load, never flushed,
			// boot released immediately.
			if (img_size != 0 && img_size <= 64'd4096) begin
				pram_ena          <= 1'b1;
				pram_load_pending <= 1'b1;        // load runs -> P_LD_B1 sets pram_ready
				pram_late_load    <= pram_ready;  // boot already released? reboot after load
			end else begin
				pram_ena   <= 1'b0;               // unmount report / not a PRAM image
				pram_ready <= 1'b1;               // release the boot now
			end
		end
		if (OSD_STATUS && !old_osd && pram_dirty && pram_ena) pram_flush_pending <= 1'b1;
		if (status[15] && !old_rstpram) pram_clr_pending <= 1'b1;

		// PRAM-ready gate. n_reset holds the machine briefly so an
		// auto-remounted PRAM image can load before the ROM's first clock-chip
		// read. HW-MEASURED 2026-06-12: MiSTer sends NO img_mounted event at
		// core load for an empty S-slot (no config/<core>.s2), so the original
		// MacLC-style 60s "mount status will surely come" backstop turned
		// EVERY imageless core start into a ~60s black screen. The backstop is
		// now short (~3s @31.3344MHz, concurrent with ROM load + RAM clear);
		// a load that lands later (slow auto-remount, or a manual mount while
		// running) self-heals via pram_late_load -> P_RST: the Mac reboots
		// once and reads the freshly loaded PRAM.
		if (!pram_ready) begin
			if (pram_rdy_cnt >= 32'd94_000_000) pram_ready <= 1'b1;
			else pram_rdy_cnt <= pram_rdy_cnt + 1'b1;
		end

		// hold the reset pulse long enough for the clk8_en_p reset block to latch
		if (pram_force_reset) begin
			if (rst_hold == 0) pram_force_reset <= 1'b0;
			else rst_hold <= rst_hold - 1'b1;
		end

		case (pst)
		P_IDLE: begin
			if (pram_clr_pending) begin
				pram_clr_pending <= 0; pcnt <= 0; pst <= P_CLR;
			end else if (pram_load_pending) begin
				pram_load_pending <= 0; pram_rd <= 1'b1; pst <= P_LD_RD;
			end else if (pram_flush_pending) begin
				pram_flush_pending <= 0; pram_rst_after <= 0; pcnt <= 0; pst <= P_FILL;
			end
		end

		// ---- LOAD: SD sector -> pram_buf16 -> rtc pram[] (2 bytes/word) ----
		// pbuf_q is a registered BRAM read: P_LD_ADDR presents the word
		// address, the data is valid one state later, then the two bytes
		// stream into the rtc load port. pcnt stays byte-granular (+2/word).
		P_LD_RD:  if (pram_ack) begin pram_rd <= 1'b0; pst <= P_LD_DAT; end
		P_LD_DAT: if (old_pack && !pram_ack) begin pcnt <= 0; pst <= P_LD_ADDR; end
		P_LD_ADDR: pst <= P_LD_B0;                 // pbuf_q latches this edge
		P_LD_B0: begin                             // even byte = low half
			pram_load_wr   <= 1'b1;
			pram_load_addr <= {pcnt[7:1], 1'b0};
			pram_load_data <= pbuf_q[7:0];
			pst <= P_LD_B1;
		end
		P_LD_B1: begin                             // odd byte = high half
			pram_load_wr   <= 1'b1;
			pram_load_addr <= {pcnt[7:1], 1'b1};
			pram_load_data <= pbuf_q[15:8];
			if (pcnt[7:1] == 7'd127) begin
				pram_dirty <= 0; pram_ena <= 1; pram_ready <= 1'b1;
				// Image landed after the Mac already started booting (late
				// auto-remount or manual mount): reboot once so the ROM
				// reads the loaded PRAM instead of the defaults.
				pst <= pram_late_load ? P_RST : P_IDLE;
				pram_late_load <= 0;
			end else begin
				pcnt <= pcnt + 9'd2; pst <= P_LD_ADDR;
			end
		end

		// ---- SAVE: rtc pram[] -> pram_buf16 -> SD sector ----
		// rtc pram_save_data is registered (valid 2 clocks after the
		// address), so each byte is a 3-state issue/wait/capture loop; odd
		// bytes commit a 16-bit word via the BRAM write-port block above.
		P_FILL: begin
			pram_save_addr <= pcnt[7:0];
			pst <= P_FILL2;
		end
		P_FILL2: pst <= P_FILL3;                   // rtc port-B q latches this edge
		P_FILL3: begin
			if (!pcnt[0]) fill_lo <= pram_save_data;
			if (pcnt == 9'd255) pst <= P_SV_WR;
			else begin pcnt <= pcnt + 9'd1; pst <= P_FILL; end
		end
		P_SV_WR: begin
			pram_wr_req <= 1'b1;
			if (pram_ack) begin pram_wr_req <= 1'b0; pst <= P_SV_DAT; end
		end
		P_SV_DAT: if (old_pack && !pram_ack) begin
			pram_dirty <= 0;
			if (pram_rst_after) begin pram_rst_after <= 0; pst <= P_RST; end
			else pst <= P_IDLE;
		end

		// ---- Reset PRAM & Core ----
		P_CLR: begin                                   // zero rtc pram[] byte-wise
			pram_load_wr   <= 1'b1;                    // (pram_buf16 word-clears in
			pram_load_addr <= pcnt[7:0];               //  the write-port block above)
			pram_load_data <= 8'h00;
			if (pcnt == 9'd255) begin
				if (pram_ena) begin pram_rst_after <= 1; pst <= P_SV_WR; end
				else pst <= P_RST;
			end else pcnt <= pcnt + 1'b1;
		end
		P_RST: begin
			pram_force_reset <= 1'b1; rst_hold <= 7'd127; pst <= P_IDLE;
		end
		default: pst <= P_IDLE;
		endcase
	end
end

hps_io #(.CONF_STR(CONF_STR), .VDNUM(VDNUM), .WIDE(1)) hps_io
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

// 1MB removed from the OSD "Memory" menu (it never sized correctly). The O45
// list is now 2MB,4MB,8MB at indices 0/1/2, so remap: index 0 => 2MB. A pre-
// change saved 8MB config (status_mem==3) also maps to 8MB, not wrapping to 1MB.
wire [1:0] configRAMSize = (status_mem == 2'd0) ? 2'b01 :  // index 0 => 2MB
                           (status_mem == 2'd1) ? 2'b10 :  // index 1 => 4MB
                                                  2'b11;   // index 2 (or 3) => 8MB
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
wire [2:0] _cpuIPL;       // final IPL to CPU (programmer's-switch NMI applied below)
wire [2:0] _cpuIPL_dc;    // raw IPL from dataController (VIA1 / VIA2 / SCC)
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

// -------------------- 16-bit ↔ 32-bit FPU bus adapter -----------------
// Ported from SingleStepTests/cpu_fpu/cpu_fpu_tests.v. TG68K has a
// 16-bit data bus and splits .L into 2 word transfers; the FPU's
// Operand CIR is a 32-bit register and expects ONE transfer per
// long-word (per AN-947 / M68020 PRM §9):
//   - WRITES (CPU→FPU): latch the first 16-bit half into fpu_wr_hi.
//     Suppress cs_n on the first half (FPU sees nothing) and fake a
//     DSACK back to TG68K. On the second half, drive
//     d_in = {fpu_wr_hi, cpuDataOut} as a single 32-bit transfer and
//     let the FPU's DSACK pass through.
//   - READS (FPU→CPU): on the first half, let the FPU strobe normally
//     and latch the full 32-bit d_out into fpu_rd_latch. TG68K gets
//     the HIGH word. On the second half, suppress cs_n (FPU doesn't
//     advance), fake DSACK, return the LOW half from the latch.
// Non-Operand CIR accesses pass through unchanged (16-bit semantics).
wire fpu_is_operand_cycle = (fpu_addr_remapped == 5'd8);
reg        fpu_xfer_phase;   // 0 = first half (HIGH), 1 = second half (LOW)
reg [15:0] fpu_wr_hi;
reg [31:0] fpu_rd_latch;
reg        fpu_prev_as_for_phase;
// Flip phase on the END of each FPU operand bus cycle (AS-rising edge
// while addressed at operand) so phase is stable throughout each cycle.
wire fpu_bus_end_edge = fpuAddrMatch && fpu_is_operand_cycle
                        && _cpuAS && !fpu_prev_as_for_phase;
always @(posedge clk_sys) begin
	if (!_cpuReset) begin
		fpu_xfer_phase        <= 1'b0;
		fpu_wr_hi             <= 16'h0000;
		fpu_rd_latch          <= 32'h0000_0000;
		fpu_prev_as_for_phase <= 1'b1;
	end else begin
		fpu_prev_as_for_phase <= _cpuAS;
		// Capture at the END of each access (AS-rising edge), when the
		// FPU has just dsacked and data is valid. Latches simultaneously
		// with the phase flip.
		if (fpu_bus_end_edge && fpu_xfer_phase == 1'b0) begin
			if (!_cpuRW) fpu_wr_hi    <= cpuDataOut;
			else         fpu_rd_latch <= fpu_data_out;
		end
		if (fpu_bus_end_edge)
			fpu_xfer_phase <= ~fpu_xfer_phase;
	end
end

// WRITES: FPU active on phase=1 (second half); READS: active on phase=0.
wire fpu_active_phase = _cpuRW ? !fpu_xfer_phase : fpu_xfer_phase;
wire fpu_cs_n_eff = fpu_is_operand_cycle
                    ? ~(fpuAddrMatch && fpu_active_phase)
                    : ~fpuAddrMatch;
wire [31:0] fpu_d_in_eff = (fpu_is_operand_cycle && !_cpuRW)
                           ? {fpu_wr_hi, cpuDataOut}
                           : {16'h0000, cpuDataOut};
// TG68K-side DSACK: fake during the inactive phase, pass-through during
// the active phase.
wire fpu_inactive_phase_act = fpuAddrMatch && fpu_is_operand_cycle
                              && !_cpuAS && !fpu_active_phase;
wire eff_fpu_dsack0_n = fpu_inactive_phase_act ? 1'b0 : fpu_dsack0_n;
wire eff_fpu_dsack1_n = fpu_inactive_phase_act ? 1'b1 : fpu_dsack1_n;
// TG68K read mux:
//  - Non-Operand: FPU's d_out[15:0] (16-bit response/save/etc).
//  - Operand phase=0: HIGH word direct from FPU's d_out[31:16].
//  - Operand phase=1: LOW word from the latch.
wire [15:0] fpu_d_to_cpu = fpu_is_operand_cycle
                           ? (fpu_xfer_phase ? fpu_rd_latch[15:0]
                                             : fpu_data_out[31:16])
                           : fpu_data_out[15:0];
// Size encoding: derive from longword + UDS/LDS.
wire [1:0] fpu_size_n =
    _cpuAS                     ? 2'b11 :  // idle
    tg68_longword              ? 2'b00 :  // .L
    (!_cpuUDS && !_cpuLDS)     ? 2'b10 :  // .W
                                 2'b01;   // .B


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

// SLOT-OWNED READ HANDSHAKE (2026-06-10 — the vec-11 / journal-corruption fix).
//
// The old gate `(!_ramOE || !_romOE) && !arb_mac_dout_valid` had two holes,
// caught red-handed by the PIFD probe (CPU fetched 0x1ED8 where ROM holds
// 0x51CD ⇒ the DBF's $FFFA displacement decoded as an F-line opcode ⇒ the
// bench's vector-11 stray trap; same mechanism corrupted journal-buffer
// READS, so the CPU wrote 0x51C9/0x0000 neighbor words to disk):
//
//  1. `!_ramOE || !_romOE` BLINKS with the busCycle interleave (video 0 /
//     CPU 1 / floppy 2 / CPU 3): during off-slots the gate term vanishes
//     and raw turbo DTACK passes, so a CPU whose s4 DTACK-sample lands in
//     an off-slot bypasses the coherency hold entirely.
//  2. arb_mac_dout_valid counted SDRAM t=0 boundaries while arb_mac_oe was
//     high — but arb_mac_oe is a MUX of CPU + legacy-video + floppy slot
//     fetches with different addresses, so the count could be satisfied by
//     a neighbor master's slot while sdram_dout held that master's word.
//
// Misaligned cycles are rare in ordinary code (bus cycles phase-lock to
// the interleave) but the NCR pseudo-DMA loop completes each DACK cycle on
// DREQ timing, randomizing the phase of the following fetch — which is why
// the corruption clustered in the 16KB journal writes.
//
// Fix: DTACK for an SDRAM read is held until a slot that STARTED with the
// CPU's own read command at its t=0 (busPhase 0 of a cpuBusControl
// busCycle) has completed (its clk8_en_p tail, where the SDRAM word is in
// sdram_dout and dataController latches cpu_data). The decode is AS-scoped
// (selectRAM/ROM, non-blinking). Worst case adds ~2 busCycles of wait on a
// misaligned read; a CPU slot always arrives, so this cannot wedge.
reg  slot0_mark;          // busPhase==0 marker (the clk after clk8_en_p)
reg  sdram_slot_cpu_rd;   // this SDRAM slot started with the CPU's read cmd
reg  cpu_sdram_rd_done;   // an owned slot has completed for this bus cycle
// DBG (2026-07-12): SDRAM coherency TIMEOUT-ESCAPE counters. The residual
// boot corruption is deterministic at PC 0x447E (A-line); these test whether
// the read/write handshake's bounded timeout fallback is accepting wrong-read /
// forcing uncommitted-write under System-load contention. Cumulative, never
// reset (initial-only) so they accrue across the whole boot.
reg [15:0] rd_escape_cnt = 16'd0;   // read timeout-escapes (latched wrong word)
reg [15:0] wr_escape_cnt = 16'd0;   // write timeout-escapes (forced done, no owned slot)
wire cpu_sdram_rd_cycle = (selectRAM || selectROM) && _cpuRW && !_cpuAS;

// COHERENCY FIX (2026-06-13): only accept SDRAM read data whose source address
// (sdram_dout_addr, tagged in sdram.v) matches the address the CPU's read wanted
// (arb_mac_addr). This stops the cpu_data latch from taking a NEIGHBOR slot's
// word -- the captured leak was a RAM read of word 0x013660 latching the adjacent
// ROM-fetch word from 0x413660 (differ only in bit 22 = RAM vs ROM/disk region).
// cpu_rd_take also gates the cpu_data latch+mux in dataController_top. The bounded
// cpu_rd_wait timeout guarantees every read completes within ~5 owned slots (well
// under the 8us bus-error window), so a marginal case falls back to the prior
// behaviour instead of ever wedging. Common case (match at the first owned-slot
// tail) adds ZERO delay.
wire cpu_rd_addr_match = (sdram_dout_addr == arb_mac_addr[23:0]);
reg [2:0] cpu_rd_wait;
wire cpu_rd_take = cpu_rd_addr_match || cpu_rd_wait[2];   // match, or timeout fallback

always @(posedge clk_sys) begin
	slot0_mark <= clk8_en_p;
	if (slot0_mark)
		sdram_slot_cpu_rd <= cpuBusControl && cpu_sdram_rd_cycle;
	if (_cpuAS) begin
		cpu_sdram_rd_done <= 1'b0;
		cpu_rd_wait       <= 3'd0;
	end else if (sdram_slot_cpu_rd && clk8_en_p) begin
		if (cpu_rd_take)     cpu_sdram_rd_done <= 1'b1;   // complete only on address-match (or timeout)
		if (!cpu_rd_wait[2]) cpu_rd_wait       <= cpu_rd_wait + 3'd1;
		// DBG (2026-07-12): read TIMEOUT-ESCAPE counter. cpu_rd_take fired via
		// the wait[2] timeout while the returned slot's addr does NOT match =>
		// the CPU is about to latch a WRONG (neighbour) word. Cumulative, never
		// reset (initial-only) so it accrues across the whole boot.
		if (cpu_rd_wait[2] && !cpu_rd_addr_match && !cpu_sdram_rd_done &&
		    rd_escape_cnt != 16'hFFFF)
			rd_escape_cnt <= rd_escape_cnt + 16'd1;
	end
end

wire mac_is_sdram_read    = cpu_sdram_rd_cycle;

// SLOT-OWNED WRITE HANDSHAKE (2026-06-15 — the write-side twin of the read
// handshake above; residual "illegal instruction" / bad-F-line corruption fix).
//
// A CPU RAM/ROM write took the raw immediate (turbo) DTACK and retired its bus
// cycle before the SDRAM controller sampled mac_we/mac_addr/mac_din at the next
// slot t=0 (clk8_en_p). The arbiter grant is combinational with Mac priority and
// the controller latches the command only at t=0 (sdram_arbiter.v: "Writes ...
// keep the fast path"), so a fast write that BEGINS AND ENDS between two slots is
// never committed -> RAM keeps stale bytes, later fetched as a garbage opcode ->
// illegal-instruction / bad-F-line crashes (FPU-innocent; invisible to the
// open-bus read fix because it is write-side; the corruption detector is
// read-only so this was never caught red-handed).
//
// Fix (mirror of cpu_sdram_rd_done): hold write DTACK until an SDRAM slot that
// STARTED with the CPU's write command at its t=0 has completed, so the CPU
// holds addr/we/din stable across the whole write sequence and the write
// commits. mac_active(=mac_we) blocks video, so the Mac wins the next t=0 and an
// owned slot always arrives within ~1-2 SDRAM cycles. The bounded cpu_wr_wait
// forces completion after 4 SDRAM cycles (~0.5us, well under the 8us BERR
// window) so this can NEVER wedge boot — it falls back to the prior immediate
// behaviour instead.
reg  sdram_slot_cpu_wr;   // this SDRAM slot started with the CPU's write cmd
reg  cpu_sdram_wr_done;   // an owned write slot has completed for this bus cycle
reg  [2:0] cpu_wr_wait;
wire cpu_sdram_wr_cycle = (selectRAM || selectROM) && !_cpuRW && !_cpuAS;

always @(posedge clk_sys) begin
	if (slot0_mark)
		sdram_slot_cpu_wr <= cpuBusControl && cpu_sdram_wr_cycle;
	if (_cpuAS) begin
		cpu_sdram_wr_done <= 1'b0;
		cpu_wr_wait       <= 3'd0;
	end else begin
		if (clk8_en_p && !cpu_wr_wait[2]) cpu_wr_wait <= cpu_wr_wait + 3'd1;
		if ((sdram_slot_cpu_wr && clk8_en_p) || cpu_wr_wait[2])
			cpu_sdram_wr_done <= 1'b1;
		// DBG (2026-07-12 v2, FIXED): write TIMEOUT-ESCAPE counter. MUST gate on
		// cpu_sdram_wr_cycle — cpu_wr_wait increments during EVERY bus cycle
		// (read+write; wr_done is just unused on reads), so the v1 counter fired
		// on reads too and saturated (bogus 0xFFFF). Now: only during an actual
		// CPU WRITE cycle, when the wait[2] timeout forces done with no owned
		// write slot having arrived (!cpu_sdram_wr_done) => the write may not
		// have committed (stale RAM = boot-block/resource corruption candidate).
		if (cpu_sdram_wr_cycle && cpu_wr_wait[2] && !(sdram_slot_cpu_wr && clk8_en_p) &&
		    !cpu_sdram_wr_done && wr_escape_cnt != 16'hFFFF)
			wr_escape_cnt <= wr_escape_cnt + 16'd1;
	end
end

wire mac_is_sdram_write   = cpu_sdram_wr_cycle;
wire ram_or_rom_dtack     = (mac_is_sdram_read  && !cpu_sdram_rd_done) ? 1'b1 :
                            (mac_is_sdram_write && !cpu_sdram_wr_done) ? 1'b1 :
                                                                         ram_or_rom_dtack_raw;

// PHANTOM-WRITE PROBE (2026-07-17, deck v8): the write handshake above
// completes DTACK when an owned slot STARTED with the CPU's write command —
// but sdram.v only latches CMD_WRITE if `we` is high at the slot's
// STATE_CMD_START; a late-settling `we` turns the slot into AUTO_REFRESH and
// the write is silently lost (wr_escape_cnt never sees it — measured 0/0 on
// failing boots). Count, at each completing owned write slot, whether the
// controller really latched the write (committed) or not (phantom). The
// counters initialize at FPGA configuration and are NEVER reset by the Mac's
// reset line, so they accumulate across soft reboots, Sad Macs, and hangs —
// readable over JTAG whenever, like busrst_cnt/inits.
wire sdram_we_latch;
reg  sdram_we_latch_s   = 1'b0;
reg [15:0] phantom_wr_cnt   = 16'd0;
reg [31:0] committed_wr_cnt = 32'd0;
always @(posedge clk_sys) begin
	sdram_we_latch_s <= sdram_we_latch;
	if (sdram_slot_cpu_wr && clk8_en_p && !cpu_sdram_wr_done) begin
		if (sdram_we_latch_s)                committed_wr_cnt <= committed_wr_cnt + 32'd1;
		else if (phantom_wr_cnt != 16'hFFFF) phantom_wr_cnt   <= phantom_wr_cnt + 16'd1;
	end
end
assign      _cpuDTACK = selectFPU ? (eff_fpu_dsack0_n & eff_fpu_dsack1_n) :
                        selectNuBus ? nubusAck :
                        selectSCSIDMA ? ~scsiDREQ :
                        viaAccess ? 1'b1 :
                        fixup_take ? 1'b0 :   // DF/DIB fixup: complete the re-run cycle
                        ram_or_rom_dtack;

// ── Programmer's switch / Level-7 NMI (debug aid, ported from MacLC) ────────
// An OSD button (status[14], the "RE" momentary trigger) fires a non-maskable
// Level-7 interrupt so MacsBug can break into a HUNG system — the core has no
// other way in (it otherwise generates only IPL 1/2/4). The 68k takes the
// level-7 autovector through the same FC=7/VPA path that already serves the
// normal interrupts (selectFPU cycles are carved out and unaffected). The
// latch clears on the level-7 IACK (addr[19:16]=$F, addr[3:1]=7) so it fires
// exactly ONCE and never masks levels 1/2/4; a ~2 ms timeout backstop
// releases it if the CPU can't ack (e.g. it is already running at mask 7).
wire       nmi_iack  = (cpuFC == 3'b111) && !_cpuAS &&
                       (cpuAddr[19:16] == 4'hF) && (cpuAddr[3:1] == 3'b111);
reg        nmi_req   = 1'b0;
reg        nmi_btn_d = 1'b0;
reg [15:0] nmi_to    = 16'd0;
always @(posedge clk_sys) begin
	nmi_btn_d <= status[14];
	if (status[14] && !nmi_btn_d) begin
		nmi_req <= 1'b1;
		nmi_to  <= 16'hFFFF;
	end else if (nmi_req) begin
		if (nmi_iack || nmi_to == 16'd0)
			nmi_req <= 1'b0;
		else
			nmi_to <= nmi_to - 1'b1;
	end
end
assign _cpuIPL = nmi_req ? 3'b000 : _cpuIPL_dc;

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
// SCSI pseudo-DMA: do NOT bus-error a DACK cycle just because scsiDREQ is low.
// Real Mac II BBU glue holds the CPU on a SCSI DMA cycle indefinitely until the
// SCSI chip raises /DRQ -- there is no glue-level timeout. Our previous form
// `(selectSCSI && !scsi_dma_wait)` excluded selectSCSI from any_select whenever
// scsi_dma_wait=1, so any DMA cycle whose DREQ took more than 251 cycles (~8us
// at 31.3344 MHz) to assert was treated as an undecoded address and bus-errored
// -> Sad Mac during the first WRITE byte. iotest hit this 3/4 of the time
// because the previous read's HPS `io_ack` linger (Linux-side latency) kept
// target REQ gated via io_busy for >8us, intermittently exceeding the threshold.
// Diagnosis: PSCS probe showed CPU's last SCSI read was BSR=0x48 (DMARQ=1,
// PMATCH=1) immediately before the Sad Mac, i.e. the driver saw the green light
// and issued MOVE.W to DACK; only the cycle itself failed. PSEL probe showed the
// target in DATA_IN with REQ=1, ACK=0, confirming the bus side was healthy.
// Fix: count selectSCSI unconditionally. CPU stalls on a real SCSI hang until
// the user reloads the core -- same semantic as real hardware.
wire any_select = selectRAM | selectROM | selectVIA | selectVIA2 | selectSCC
                | selectSCSI | selectIWM | selectASC | nubus_acked | selectSEOverlay | selectFPU;
wire is_cpu_space = (cpuFC == 3'b111);

// ── 68020 format-$B DF/DIB software-fixup engine (2026-07-12) ────────────────
// The Mac II ROM's bus-error catchers at $4080E590/$4080E59C clear SSW.DF in
// the stacked frame, write a substitute value into the Data Input Buffer at
// +$2C ($00000000 / $FFFFFFFF), and RTE — the real 68020 then resumes the
// faulted instruction mid-pipe consuming the DIB in place of the pending data
// fetch. TG68K restarts the instruction instead (kernel now pushes exe_pc for
// trap_berr so the restart is well-defined). The OLD top-level implementation
// fed berr_data into EVERY read while berr_inhibit was active and cleared at
// the first setopcode — i.e. the post-RTE re-FETCH consumed the DIB and the
// handler's substitute value EXECUTED AS AN OPCODE ($FFFF ⇒ F-line ⇒ Sad Mac
// 0F/000A; $0000 ⇒ ori.b swallows the real opcode ⇒ desync ⇒ illegal/priv
// bombs) — the Happy-Mac soft-reboot class.
// New scheme — LAZY SUBSTITUTION: on the kernel's berr_inhibit rising edge
// (a $B RTE whose handler cleared DF) latch {DIB, pending}; all bus cycles
// run NORMALLY (real re-fetch, real EA reads); when the restarted read to the
// RECORDED fault address times out where the 8 µs BERR would fire, complete
// the cycle instead — synthetic DTACK + the DIB word (hi/lo by A1). Writes to
// the fault address complete silently (WB-clear semantics). The window
// retires when the low word is consumed, at the first completed fetch after
// a substitution, or after ~1.6 ms. A DF=1 rerun (handler wants a true
// retry) never arms this, and a re-run to a now-valid address completes
// normally — the pending window just expires.
reg [31:0] berr_fault_addr_top = 32'd0; // address of the ORIGINAL faulting cycle
reg        fixup_pending = 1'b0;        // a DF-cleared RTE armed a DIB substitution
reg [31:0] fixup_data = 32'd0;          // the handler's DIB value (kernel berr_data)
reg        fixup_take = 1'b0;           // substituting THIS bus cycle (holds till AS rise)
reg        fixup_took = 1'b0;           // >=1 beat substituted in this window
reg        berr_inhibit_a_d = 1'b0;
reg [15:0] fixup_expire = 16'd0;
wire fixup_match = fixup_pending && (cpuAddr[31:2] == berr_fault_addr_top[31:2]);

always @(posedge clk_sys) begin
	if (!_cpuReset) begin
		berr_counter <= 0;
		berr_out <= 0;
		fixup_pending <= 0; fixup_take <= 0; fixup_took <= 0;
		berr_inhibit_a_d <= 0;
	end else begin
		berr_inhibit_a_d <= berr_inhibit_active;
		// arm at the RTE that cleared DF (kernel latched the DIB from the frame)
		if (berr_inhibit_active && !berr_inhibit_a_d) begin
			fixup_pending <= 1'b1;
			fixup_took    <= 1'b0;
			fixup_data    <= berr_data_out;
			fixup_expire  <= 16'd50000;   // ~1.6 ms backstop
		end else if (fixup_pending) begin
			if (fixup_expire == 16'd0) fixup_pending <= 1'b0;
			else fixup_expire <= fixup_expire - 1'd1;
		end
		if (_cpuAS) begin
			berr_counter <= 0;
			berr_out <= 0;
			if (fixup_take) begin
				fixup_take <= 0;
				// low/odd word consumed => the DIB long is complete; retire
				if (cpuAddr[1]) fixup_pending <= 0;
			end
			// bound a word/byte substitution to its own instruction: the first
			// completed FETCH after a substituted beat retires the window
			if (fixup_took && !fixup_take && cpuFC[1:0] == 2'b10 && _cpuRW)
				fixup_pending <= 0;
		end else if (berr_out || fixup_take) begin
			// Hold BERR / the substitution until AS deasserts (CPU ends cycle)
		end else if (is_cpu_space || any_select)
			berr_counter <= 0;
		else if (berr_counter == 9'd251) begin  // ~8us at 31.3344 MHz
			if (fixup_match) begin
				fixup_take <= 1'b1;   // complete with the DIB instead of BERR
				fixup_took <= 1'b1;
			end else begin
				berr_out <= 1;
				berr_fault_addr_top <= cpuAddr;   // remember the fault site
			end
			berr_counter <= 0;
		end else
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
		fpu_data_hold <= fpu_d_to_cpu;
		fpu_data_hold_valid <= 1'b1;
	end else if (!_cpuAS && !selectFPU) begin
		fpu_data_hold_valid <= 1'b0;
	end
end

// 2026-07-12: the old first term `berr_inhibit_active ? berr_data_out[15:0]`
// fed the DIB into EVERY read of the post-RTE window — including the
// instruction re-fetch, which executed the handler's DIB as an opcode (the
// Happy-Mac soft-reboot / Sad Mac 0F class). Replaced by the lazy-substitution
// engine above: only the timed-out re-run read of the recorded fault address
// receives the DIB (hi/lo word by A1).
wire [15:0] cpu_data_in = fixup_take ? (cpuAddr[1] ? fixup_data[15:0] : fixup_data[31:16]) :
                          selectFPU ? fpu_d_to_cpu :
                          fpu_data_hold_valid ? fpu_data_hold :
                          // Open-bus default for UNDECODED reads (port of MacLC f9fbf56).
                          // Return $FFFF, never the stale neighbour SDRAM word that the mux
                          // otherwise falls through to (dataController_top.sv cpu_data). This is
                          // exactly the undecoded set the ~8us BERR already targets, so it cannot
                          // affect any decoded RAM/ROM/peripheral/FPU read. (FC=7 excluded.)
                          (~any_select & ~is_cpu_space) ? 16'hFFFF :
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
	// 2026-07-12: unmasked — the old `berr_inhibit_active ? 1'b0 : berr_out`
	// blanket-suppressed real bus errors during the post-RTE window; the
	// fixup engine now completes the one matched cycle instead, so berr
	// keeps its normal meaning everywhere.
	.berr       ( berr_out     ),
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
// Data bus: TG68K is 16-bit; non-Operand CIR accesses use d_in/d_out[15:0].
// Operand CIR accesses are 32-bit and go through the bus adapter above
// (fpu_d_in_eff / fpu_d_to_cpu / fpu_cs_n_eff / eff_fpu_dsack*).
// sense_n is an inout driven by the FPU internally to indicate presence

wire [31:0] fpu_dbg_cir_state;
mc68881_fpu_lite fpu_inst (
	.clk        ( clk_sys              ),
	.reset_n    ( _cpuReset            ),
	.a_in       ( fpu_addr_remapped    ),
	.d_in       ( fpu_d_in_eff         ),
	.d_out      ( fpu_data_out         ),
	.size_n     ( fpu_size_n           ),
	.as_n       ( _cpuAS               ),
	.cs_n       ( fpu_cs_n_eff         ),
	.rw         ( _cpuRW               ),
	.ds_n       ( _cpuUDS & _cpuLDS    ),  // active when either byte lane selected
	.dsack0_n   ( fpu_dsack0_n         ),
	.dsack1_n   ( fpu_dsack1_n         ),
	.sense_n    ( fpu_sense_n          ),
	.status_valid (                    ),
	.dbg_cir_state ( fpu_dbg_cir_state )
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

// Card VRAM size: 384 KB of BRAM (196608 16-bit words) — covers 8 bpp at
// 640x480 (300 KB) with headroom. 512 KB does NOT fit: it alone needs 512 of
// the device's 553 M10K blocks (the rest of the core uses ~105). Single
// source of truth for both the card's bound check and the vram_ram instance.
localparam VRAM_WORDS = 196608;

nubus_video_mdc824 #(.VRAM_WORDS(VRAM_WORDS)) nubus_card (
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
	.monitor_512(status_monitor_512),

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
wire        dbg_via1_irq_n;
wire        dbg_via2_irq_n;
wire        dbg_scc_irq_n;

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
	._cpuIPL(_cpuIPL_dc),
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
	.cpuSlotOwned(sdram_slot_cpu_rd),
	.cpu_rd_take(cpu_rd_take),   // COHERENCY FIX: gate cpu_data latch/mux on address-match

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

	// PRAM persistence (HPS NVRAM image <-> rtc pram[])
	.pram_load_wr(pram_load_wr),
	.pram_load_addr(pram_load_addr),
	.pram_load_data(pram_load_data),
	.pram_save_addr(pram_save_addr),
	.pram_save_data(pram_save_data),
	.pram_wr_stb(pram_wr_stb),

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
	.dbg_via1_irq_n(dbg_via1_irq_n),
	.dbg_via2_irq_n(dbg_via2_irq_n),
	.dbg_scc_irq_n(dbg_scc_irq_n),

	// floppy disk interface
	// External (second) floppy bay removed 2026-08-07 (optimize-core, owner
	// call — fit headroom for BlueSCSI Toolbox/CD-ROM). Same recipe as
	// MacIIvi 8b5f594: swim.v/dataController stay byte-identical (family
	// law); the constants let synthesis fold the ext-drive cones (~300 ALMs).
	// diskEject[1]/diskMotor[1]/diskAct[1] intentionally land nowhere.
	.insertDisk({1'b0, dsk_int_ins}),
	.diskSides({1'b0, dsk_int_ds}),
	.diskMFM({1'b0, dsk_int_mfm}),
	.diskHD({1'b0, dsk_int_hd}),
	.diskEject(diskEject),
	.dskReadAddrInt(dskReadAddrInt),
	.dskReadAckInt(dskReadAckInt),
	.dskReadAddrExt(dskReadAddrExt),
	.dskReadAckExt(dskReadAckExt),
	.diskMotor(diskMotor),
	.diskAct(diskAct),

	// block device interface for scsi disk (hps_io slots 0,1 only — slot 2
	// is the PRAM save image, serviced by the PRAM FSM above)
	.img_mounted(img_mounted[SCSI_DEVS-1:0]),
	.img_size(img_size[40:9]),
	.io_lba(scsi_lba),
	.io_rd(scsi_rd),
	.io_wr(scsi_wr),
	.io_ack(sd_ack[SCSI_DEVS-1:0]),

	.sd_buff_addr(sd_buff_addr[7:0]),
	.sd_buff_addr_hi(sd_buff_addr[12:8]),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(scsi_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.dbg_scsi(dbg_scsi),
	.dbg_scsi2(dbg_scsi2),
	.dbg_scsi3(dbg_scsi3),
	.dbg_scsi4(dbg_scsi4),
	.dbg_scsi5(dbg_scsi5),
	.dbg_wr(dbg_wr),
	.dbg_wrfb(dbg_wrfb),
	.dbg_ncr(dbg_ncr),
	.dbg_ncr2(dbg_ncr2),
	.dbg_ring0(dbg_ring0),
	.dbg_ring1(dbg_ring1),
	.dbg_via2_irq(dbg_via2_irq),
	.dbg_adb(dbg_adb),
	.dbg_adb2(dbg_adb2),
	.dbg_adb3(dbg_adb3),
	.dbg_adb4(dbg_adb4),
	.mouse_has_event_o(adb_mouse_has_event),

	.dbg_flp_byte_cnt (dbg_flp_byte_cnt),
	.dbg_flp_miss_cnt (dbg_flp_miss_cnt),
	.dbg_flp_disk_data(dbg_flp_disk_data),
	.dbg_iwm_ack_cnt  (dbg_iwm_ack_cnt),
	.dbg_iwm_latch    (dbg_iwm_latch),
	.dbg_iwm_arm_high (dbg_iwm_arm_high),
	.dbg_flp_track    (dbg_flp_track),
	.dbg_flp_side     (dbg_flp_side),
	.dbg_flp_step_cnt (dbg_flp_step_cnt)
);
wire [15:0] dbg_scsi;
wire [15:0] dbg_scsi2;
wire [15:0] dbg_scsi3;
wire [15:0] dbg_scsi4;
wire [15:0] dbg_scsi5;
// MacLC-transplant dbg export set (2026-08-08): the pre-transplant v3.x tap
// wires (scsi_wr/wr0/regs/selt0/wring*/selid/winh*/iwh/cmdr0/star0/lbar0*/
// xorr0*/selfail0) died with the old scsi.v; MacLC's anchor-law equivalents:
wire [31:0] dbg_wr;        // write-stall snapshot, data-phase-routed
wire [31:0] dbg_wrfb;      // write first-beat forensics (anchor feed)
wire [31:0] dbg_ncr;       // NCR5380 host-side pseudo-DMA stall
wire [31:0] dbg_ncr2;
wire [31:0] dbg_ring0;     // read-ring serve/refill, target 0 (anchor-only feed)
wire [31:0] dbg_ring1;     // read-ring serve/refill, target 1 (anchor-only feed)
wire [31:0] dbg_via2_irq;      // NCR5380 write loss-mechanism counters
wire [31:0] dbg_adb;
wire [17:0] dbg_adb2;
wire [31:0] dbg_adb3;
wire [31:0] dbg_adb4;
wire        adb_mouse_has_event;
wire [15:0] dbg_flp_byte_cnt;
wire [15:0] dbg_flp_miss_cnt;
wire [7:0]  dbg_flp_disk_data;
wire [15:0] dbg_iwm_ack_cnt;
wire [7:0]  dbg_iwm_latch;
wire [6:0]  dbg_iwm_arm_high;
wire [6:0]  dbg_flp_track;
wire        dbg_flp_side;
wire [15:0] dbg_flp_step_cnt;

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
reg dsk_int_ds;  // double sided image inserted
reg dsk_int_ss;  // single sided image inserted
// SWIM/ISM geometry (2026-08-07): an MFM image routes the SWIM's ISM path
// instead of the IWM GCR path; HD distinguishes 1.44MB from 720K. Raw sizes
// in WORDS (dio_addr counts words): 720K = 368640, 1.44M = 737280.
reg dsk_int_mfm;
reg dsk_int_hd;

// any known type of disk image inserted?
wire dsk_int_ins = dsk_int_ds || dsk_int_ss || dsk_int_mfm;

// at the end of a download latch file size
// diskEject is set by macos on eject
always @(posedge clk_sys) begin
	reg old_down;

	old_down <= dio_download;
	// F1 in conf_str maps to ioctl_index=1 (MiSTer hps_io convention) for the
	// primary floppy, matching MacPlus_MiSTer and macplus-og. Earlier this checked
	// index 2/3, which is wrong: index 1 fell through to the catch-all dio_a else
	// branch and the download silently overwrote the boot ROM region in SDRAM.
	if(old_down && ~dio_download && dio_index == 1) begin
		dsk_int_ds <= (dio_addr == 409600);   // double sides disk, addr counts words, not bytes
		dsk_int_ss <= (dio_addr == 204800);   // single sided disk
		dsk_int_mfm <= (dio_addr == 368640) || (dio_addr == 737280);  // 720K / 1.44M MFM
		dsk_int_hd  <= (dio_addr == 737280);                          // 1.44M only
	end

	if(diskEject[0]) begin
		dsk_int_ds <= 0;
		dsk_int_ss <= 0;
		dsk_int_mfm <= 0;
		dsk_int_hd  <= 0;
	end
end

// (External-floppy F2 latch block removed 2026-08-07 with the second bay —
// see the dc0 tie-off note. No F2 entry exists in CONF_STR, so ioctl_index=2
// downloads no longer occur; the dio_a decode still sinks a stray index-2
// stream into the retired 0x600000 window rather than the ROM catch-all.)

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
// Clear the FULL 8 MB RAM window unconditionally.  The extent used to be sized
// from configRAMSize (= status_mem), but status_mem is not latched until AFTER
// the clear has already run — it is captured during the n_reset release
// countdown, which is itself gated on clear_done.  So the clear ran against an
// un-latched, power-up-don't-care size and could zero as little as the low
// 1 MB, leaving upper RAM as garbage on a cold configure (the "garbled chime /
// clean after a reload" lottery).  The SDRAM chip backs all 8 MB regardless of
// the configured size, so zeroing addresses above the installed RAM is harmless
// and removes the ordering dependency entirely.  (status_mem still latches at
// reset release for addrController's runtime size limiting / OSD re-apply.)
localparam [21:0] clear_limit = 22'h3FFFFF;   // full 8 MB, config-independent
reg [21:0] clear_addr   = 0;
reg        clear_active = 0;
reg        clear_done   = 0;
reg        clear_write  = 0;
reg        clear_old_cyc = 0;
always @(posedge clk_sys) begin
	// Reset the clear on every lock-stable epoch — a cold configure OR a
	// PLL-unlock recovery (a lock loss can corrupt RAM).  Keyed off sys_locked
	// rather than rom_loaded (which never de-asserts) so RAM is re-zeroed after
	// any unlock event before the machine is let go again.
	if(!sys_locked) begin
		clear_active  <= 1'b0;
		clear_done    <= 1'b0;
		clear_addr    <= 22'd0;
		clear_write   <= 1'b0;
		clear_old_cyc <= 1'b0;
	end else begin
		if(!clear_done && !clear_active && rom_loaded) clear_active <= 1'b1;  // start once boot0.rom is in
		clear_old_cyc <= dioBusControl;
		// Yield every dio slot to an in-flight download: the arbiter address
		// mux gives download_cycle priority, so a clear write that shared a slot
		// with a ROM/disk download word would be silently dropped (and the
		// ioctl_wait handshake desynced).  Pausing while dio_download is high
		// makes the clear consume only idle slots — it can begin right after the
		// ROM and politely interleave with any trailing disk-image stream.
		if(clear_active && !dio_download) begin
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
wire clear_cycle = clear_active && dioBusControl && !dio_download;

// disk images are being stored right after os rom at word offset 0x80000 and 0x100000
// dio_a widened 21 -> 22 bits (2026-08-07): a 1.44MB floppy image is 737,280
// words and did NOT fit the old 19-bit (512K-word) per-slot windows — the
// download address WRAPPED and overwrote the image's own start, so the ROM
// read garbage boot blocks and ejected the disk with an X. Each floppy slot
// now gets a full 1M-word (2MB) window, like MacLC's layout.
reg [21:0] dio_a;
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
			dio_a <= {4'b0000, dio_addr[17:0]}; // boot0.rom @word 0x400000
		// F1 in conf_str maps to ioctl_index 1 (MiSTer hps_io convention;
		// matches MacPlus_MiSTer and macplus-og), staged in a 1M-word (2MB)
		// window @word 0x500000. Index 2 (the retired F2 secondary) no longer
		// has a CONF_STR entry so it cannot arrive from a well-behaved Main —
		// but keep decoding it into the dead 0x600000 window as a defensive
		// sink: falling through to the ROM catch-all is the exact class that
		// once silently overwrote boot0.rom (see the F1 note above).
		else if (dio_index[1:0] == 1 || dio_index[1:0] == 2) // Floppy disk image (F1)
			dio_a <= {dio_index[1:0], dio_addr[19:0]};  // F1 @word 0x500000 (idx2 sink @0x600000)
		else
			dio_a <= {1'b0, dio_index[6], dio_addr[17:0]};

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
// Download has mux priority over the clear (downloads are externally paced and
// must never be dropped); clear_cycle already excludes dio_download, so the two
// are mutually exclusive — ordering download first is defensive.
assign arb_mac_addr = download_cycle ? {2'b00, 1'b1, dio_a[21:0] } :          // ROM/disk download @ 0x400000+
                      clear_cycle    ? {3'b000, clear_addr} :                       // RAM pre-clear @ 0x000000+
                      ~_romOE        ? {2'b00, 1'b1, 4'b0000, memoryAddr[18:1]} :    // Mac II ROM @ 0x400000+
                      (dskReadAckInt || dskReadAckExt) ? {2'b00, 1'b1, memoryAddr[22:1]} : // disk image @ 0x400000+
                                       {3'b000, memoryAddr[22:1]};                   // RAM 0x000000-0x3FFFFF (8MB)

assign arb_mac_din  = download_cycle ? dio_data   : clear_cycle ? 16'h0000     : memoryDataOut;
assign arb_mac_ds   = download_cycle ? 2'b11      : clear_cycle ? 2'b11        : { !_memoryUDS, !_memoryLDS };
assign arb_mac_we   = download_cycle ? dio_write  : clear_cycle ? clear_write  : !_ramWE;
assign arb_mac_oe   = download_cycle ? 1'b0       : clear_cycle ? 1'b0         : (!_ramOE || !_romOE || dskReadAckInt || dskReadAckExt);

wire [15:0] sdram_do   = download_cycle ? 16'hffff : (dskReadAckInt || dskReadAckExt) ? extra_rom_data_demux : arb_mac_dout;

// during rom/disk download ffff is returned so the screen is black during download
// "extra rom" is used to hold the disk image. It's expected to be byte wide and
// we thus need to properly demultiplex the word returned from sdram in that case
wire [15:0] extra_rom_data_demux = memoryAddr[0]? {sdram_out[7:0],sdram_out[7:0]}:{sdram_out[15:8],sdram_out[15:8]};
wire [15:0] sdram_out;
wire [23:0] sdram_dout_addr;   // DBG: word-address that produced sdram_out (coherency probe; pruned if unused)

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
vram_ram #(.WORDS(VRAM_WORDS)) vram_inst (   // 384 KB dual-port (1-8 bpp @ 640x480)
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
	.init           ( !sys_locked              ),  // hold SDRAM in init until clk_sys is lock-stable
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
	.dout           ( sdram_out                ),
	.dout_addr      ( sdram_dout_addr          ),  // DBG: address tag for the coherency probe
	.dbg_we_latch   ( sdram_we_latch           )   // DBG: phantom-write probe
);

// SDRAM Arbiter - share SDRAM between Mac and NuBus video
sdram_arbiter arbiter (
	.clk(clk_sys),
	.clk8_en_p(clk8_en_p),  // SDRAM cycle T0 marker for the coherency handshake
	.reset(!sys_locked),  // Reset with SDRAM (lock-stable), not CPU

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

// ── ALL probe fabric deleted (2026-08-08, owner call) ────────────────────────
// The JTAG instrument decks that lived here and below — dbg_coldinit (4 ISSP),
// the DBG_FPU FPCS probe, dbg_wedge (20 ISSP), dbg_min (82 ISSP) and the
// ncr5380 PWR2/PSEL pair — are physically removed from the core, matching
// MacLC's release posture (probe-less bitstream + marginality anchor). Every
// cone they consumed is pinned by the anchor block below, so their removal
// does not change any net's loaded/unloaded status vs the last known-good
// probe-off fits. To resurrect an instrument for a hardware hunt, revert the
// deleting commit (git log --follow rtl/dbg_wedge.sv) — the read scripts
// (scripts/read_wedge.tcl, read_coldinit.tcl, read_fpu.tcl, cpu_state.tcl)
// are kept in-tree and match the reverted instruments as-is.

// ── Always-on marginality anchor (optimize-core 2026-08-07) ──────────────────
// Ported law from MacLC 4dfb463 / MacIIvi MacIIvi.sv:937: on MacLC, probes-OFF
// fits of this SCSI lineage deterministically corrupted the SCSI read path on
// hardware (Finder colour-icon noise → error-11 / F-line bombs) while every
// probe-bearing fit passed — and STA met either way, so timing analysis does
// NOT predict the class. The protective effect bisected to the fanout of the
// top-level probes. With DBG_WEDGE now stripped for the resource diet, these
// sink registers keep the SAME nets loaded in every build, with no JTAG hub,
// so the fitter treats the SCSI capture/ring/coherency cones as live logic.
// One register per debug word, loaded directly (concatenation of narrow nets
// is fine; XOR/parity folding is NOT — a reduction lets synthesis restructure
// the cones). preserve+noprune = no merging, no retiming, no sweeping.
// Do NOT remove, ifdef, or fold. ~1K FFs is the entire cost.
//   * scsi/ring words = every cone the wedge deck consumed in the last
//     probe-bearing hardware-good build (baseline-fanout consistency);
//     lbar/xorr pin the ring-stale serve cone (MacLC 2026-08-03 extension).
//   * flp words pin the floppy fetch cone (MacLC 2026-08-04 extension —
//     an anchor-less LC build passed the SCSI icon gate yet failed a
//     sustained floppy copy; same swim.v lineage as ours).
//   * coh words pin the SDRAM coherency-escape counters (tap-only regs).
//   * fpcs pins the FPU CIR observability cone (fpu_dbg_cir_state) — our
//     residual-lottery history is FPU-adjacent; keep its layout stable and
//     the DBG_FPU probe re-attachable without a netlist change.
// SCSI words re-based 2026-08-08 with the MacLC SCSI transplant: the old
// v3.x tap set died with the old scsi.v; the pinned words below are exactly
// MacLC's anchor-law SCSI exports (scsi..5 handshake/status, wr write-stall,
// wrfb first-beat, ncr/ncr2 pseudo-DMA machine, ring0/1 below). When
// CDROM_PRESENT goes to 1 in the feature round, ADD anchor words for
// dbg_cda0-4 + dbg_cdur (MacLC pins them; constants until then, so they are
// deliberately not anchored while the CD target is compiled out).
(* preserve, noprune *) reg [31:0] anchor_scsi,  anchor_scsi4, anchor_scsi5;
(* preserve, noprune *) reg [31:0] anchor_wr,    anchor_wrfb;
(* preserve, noprune *) reg [31:0] anchor_ncr,   anchor_ncr2,  anchor_via2;
(* preserve, noprune *) reg [31:0] anchor_adb0,  anchor_adb1,
                                   anchor_adb2,  anchor_adb3;
(* preserve, noprune *) reg [31:0] anchor_coh0,  anchor_coh1;
(* preserve, noprune *) reg [31:0] anchor_flp,   anchor_flp2;
(* preserve, noprune *) reg [31:0] anchor_fpcs;
// (2026-08-08) Ring-cone extension, ported from MacLC's 2026-08-03 anchor
// extension: their 11-word anchor proved INSUFFICIENT — a probes-off fit
// corrupted the Finder colour-icon read path with the anchor present. The
// recurring fingerprint of this class is RING-STALE serving: a ring slot
// served at/past the rd_hps_blk fill boundary. These two words pin that
// exact cone per disk target (scsi.v dbg_ring: the io_busy stall comparator,
// fetch-pacing comparators, and both frontier counters). Same law: never
// remove, ifdef, or fold.
(* preserve, noprune *) reg [31:0] anchor_ring0, anchor_ring1;
always @(posedge clk_sys) begin
	anchor_scsi   <= {dbg_scsi, dbg_scsi2};
	anchor_scsi4  <= {dbg_scsi3, dbg_scsi4};
	anchor_scsi5  <= {16'b0, dbg_scsi5};
	anchor_wr     <= dbg_wr;
	anchor_wrfb   <= dbg_wrfb;
	anchor_ncr    <= dbg_ncr;
	anchor_ncr2   <= dbg_ncr2;
	anchor_via2   <= dbg_via2_irq;
	anchor_adb0   <= dbg_adb;
	anchor_adb1   <= {14'b0, dbg_adb2};
	anchor_adb2   <= dbg_adb3;
	anchor_adb3   <= dbg_adb4;
	anchor_coh0   <= {rd_escape_cnt, wr_escape_cnt};
	anchor_coh1   <= {phantom_wr_cnt, committed_wr_cnt[31:16]};
	anchor_flp    <= {dbg_flp_byte_cnt, dbg_flp_miss_cnt};
	anchor_flp2   <= {dbg_iwm_ack_cnt, dbg_iwm_latch, 1'b0, dbg_iwm_arm_high};
	anchor_fpcs   <= fpu_dbg_cir_state;
	anchor_ring0  <= dbg_ring0;
	anchor_ring1  <= dbg_ring1;
end



endmodule
