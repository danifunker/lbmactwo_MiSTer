module dataController_top  #(parameter SCSI_DEVS = 2)(
	// clocks:
	input clk32,					// 31.3344 MHz system clock (2 × C15M)
	input clk8_en_p,
	input clk8_en_n,
	input clk16_en_p,				// C15M (15.6672 MHz) — IWM input per MAME spec
	input clk16_en_n,
	input E_rising,
	input E_falling,

	// system control:
	input machineType, // 0 - Mac Plus, 1 - Mac SE
	input [2:0] macModel, // 0=Plus, 1=SE, 2=MacII, 3=MacII FDHD, 4=IIx, 5=IIcx, 6=SE/30
	input [1:0] configRAMSize, // 0=1MB, 1=2MB, 2+=4MB (for VIA2 PA7:6 RAM sizing pins)
	input _systemReset,

	// 68000 CPU control:
	output _cpuReset,
	output [2:0] _cpuIPL,

	// 68000 CPU memory interface:
	input [15:0] cpuDataIn,
	input [3:0] cpuAddrRegHi, // A12-A9
	input [2:0] cpuAddrRegMid, // A6-A4
	input [1:0] cpuAddrRegLo, // A2-A1
	input _cpuUDS,
	input _cpuLDS,
	input _cpuRW,
	input cpuLongword,
	output [15:0] cpuDataOut,

	// peripherals:
	input selectSCSI,
	input selectSCSIDMA,
	output scsiDREQ,
	input selectSCC,
	input selectIWM,
	input selectVIA,
	input selectVIA2,
	input selectSEOverlay,
	input selectNuBus,
	input selectASC,
	input [12:0] cpuAddrASC,
	input [15:0] nubusDataIn,
	input nubus_irq_n,
	input _cpuVMA,

	// RAM/ROM:
	input videoBusControl,
	input cpuBusControl,
	input [15:0] memoryDataIn,
	output [15:0] memoryDataOut,
	input memoryLatch,

	// keyboard:
	input [10:0] ps2_key,
	output capslock,

	// mouse:
	input [24:0] ps2_mouse,

	// serial:
	input serialIn,
	output serialOut,
	input serialCTS,
	output serialRTS,

	// RTC
	input [32:0] timestamp,

	// video:
	output pixelOut,
	input _hblank,
	input _vblank,
	input loadPixels,
	output vid_alt,

	// audio
	output [15:0] ascAudioLeft,
	output [15:0] ascAudioRight,
	output        dbg_asc_irq_n,   // ASC sound IRQ (active-low) for JTAG probe

	// misc
	output memoryOverlayOn,
	output [1:0] glueRAMSize,

	// Mac II HMMU enable (VIA2 PB3 low → 24-bit translated mode)
	output hmmu_active,

	input [1:0] insertDisk,
	input [1:0] diskSides,
	output [1:0] diskEject,
	output [1:0] diskMotor,
	output [1:0] diskAct,

	output [21:0] dskReadAddrInt,
	input dskReadAckInt,
	output [21:0] dskReadAddrExt,
	input dskReadAckExt,

	// connections to io controller
	input   [SCSI_DEVS-1:0] img_mounted,
	input            [31:0] img_size,
	output           [31:0] io_lba[SCSI_DEVS],
	output  [SCSI_DEVS-1:0] io_rd,
	output  [SCSI_DEVS-1:0] io_wr,
	input   [SCSI_DEVS-1:0] io_ack,
	input             [7:0] sd_buff_addr,
	input            [15:0] sd_buff_dout,
	output           [15:0] sd_buff_din[SCSI_DEVS],
	input                   sd_buff_wr,

	// JTAG debug passthrough: NCR5380 selection/arbitration state
	output           [15:0] dbg_scsi,
	output           [15:0] dbg_scsi2,
	output           [15:0] dbg_scsi3,
	output           [15:0] dbg_scsi4,
	output           [15:0] dbg_scsi5,
	output           [31:0] dbg_adb,
	output           [17:0] dbg_adb2
);

	// CPU reset generation
	// For initial CPU reset, RESET and HALT must be asserted for at least 100ms = 800,000 clocks of clk8
	reg [19:0] resetDelay; // 20 bits = 1 million
	wire isResetting = resetDelay != 0;

	initial begin
		// force a reset when the FPGA configuration is completed
		resetDelay <= 20'hFFFFF;
	end

	always @(posedge clk32 or negedge _systemReset) begin
		if (_systemReset == 1'b0) begin
			resetDelay <= 20'hFFFFF;
		end
		else if (clk8_en_p && isResetting) begin
			resetDelay <= resetDelay - 1'b1;
		end
	end
	assign _cpuReset = isResetting ? 1'b0 : 1'b1;

	// interconnects
	wire SEL;
	wire _viaIrq, _via2Irq, _sccIrq, sccWReq;
	wire [15:0] viaDataOut;
	wire [15:0] via2DataOut;
	wire [15:0] iwmDataOut;
	wire [7:0] sccDataOut;
	wire [15:0] scsiDataOut;
	wire [7:0] ascDataOut;
	wire asc_irq_n;
	assign dbg_asc_irq_n = asc_irq_n;
	wire mouseX1, mouseX2, mouseY1, mouseY2, mouseButton;

	// interrupt control - Mac II priority: SCC(4) > VIA2(2) > VIA1(1)
	assign _cpuIPL =
		!_sccIrq  ? 3'b011 :  // SCC → IPL 4
		!_via2Irq ? 3'b101 :  // VIA2 → IPL 2
		!_viaIrq  ? 3'b110 :  // VIA1 → IPL 1
		3'b111;


	reg [15:0] cpu_data;
	always @(posedge clk32) if (cpuBusControl && memoryLatch) cpu_data <= memoryDataIn;

	// CPU-side data output mux
	assign cpuDataOut = selectASC ? { ascDataOut, ascDataOut } :
							  selectIWM ? iwmDataOut :
							  selectVIA ? viaDataOut :
							  selectVIA2 ? via2DataOut :
							  selectNuBus ? nubusDataIn :
							  selectSCC ? { sccDataOut, 8'hEF } :
							  selectSCSI ? scsiDataOut :
							  (cpuBusControl && memoryLatch) ? memoryDataIn : cpu_data;

	// Memory-side
	assign memoryDataOut = cpuDataIn;

	// SCSI
	ncr5380 #(.DEVS(SCSI_DEVS), .ENABLE_EMPTY_CD(1)) scsi(
		.clk(clk32),
		.reset(!_cpuReset),
		.bus_cs(selectSCSI),
		.bus_rs(cpuAddrRegMid),
		.ior(_cpuRW && !_cpuUDS),
		.iow(!_cpuRW && !_cpuUDS),
		.dack(selectSCSIDMA),
		.dma_word(!_cpuUDS && !_cpuLDS),
		.dma_longword(cpuLongword),
		.dma_second_word(cpuAddrRegLo[0]),
		.dreq(scsiDREQ),
		.wdata(cpuDataIn),
		.rdata(scsiDataOut),

		// connections to io controller
		.img_mounted( img_mounted ),
		.img_size( img_size ),
		.io_lba ( io_lba ),
		.io_rd ( io_rd ),
		.io_wr ( io_wr ),
		.io_ack ( io_ack ),

		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din(sd_buff_din),
		.sd_buff_wr(sd_buff_wr),
		.dbg_scsi(dbg_scsi),
		.dbg_scsi2(dbg_scsi2),
		.dbg_scsi3(dbg_scsi3),
		.dbg_scsi4(dbg_scsi4),
		.dbg_scsi5(dbg_scsi5)
	);

	// ASC (Apple Sound Chip)
	asc asc_inst(
		.clk        (clk32),
		.reset      (!_cpuReset),
		.addr       (cpuAddrASC),
		.data_in    (cpuDataIn),
		.data_out   (ascDataOut),
		.cs         (selectASC),
		.rw         (_cpuRW),
		.uds        (!_cpuUDS),
		.lds        (!_cpuLDS),
		.audio_left (ascAudioLeft),
		.audio_right(ascAudioRight),
		.irq_n      (asc_irq_n)
	);

	// count vblanks, and set 1 second interrupt after 60 vblanks
	reg [5:0] vblankCount;
	reg _lastVblank;
	always @(posedge clk32) begin
		if (clk8_en_n) begin
			_lastVblank <= _vblank;
			if (_vblank == 1'b0 && _lastVblank == 1'b1) begin
				if (vblankCount != 59) begin
					vblankCount <= vblankCount + 1'b1;
				end
				else begin
					vblankCount <= 6'h0;
				end
			end
		end
	end
	wire onesec = vblankCount == 59;

	// Mac SE ROM overlay switch
	reg  SEOverlay;
	always @(posedge clk32) begin
		if (!_cpuReset)
			SEOverlay <= 1;
		else if (selectSEOverlay)
			SEOverlay <= 0;
	end

	// VIA1
	wire driveSel; // internal drive select, 0 - upper, 1 - lower

	wire [7:0] via_pa_i, via_pa_o, via_pa_oe;
	wire [7:0] via_pb_i, via_pb_o, via_pb_oe;
	wire viaIrq;

	assign _viaIrq = ~viaIrq;

	//port A
	// VIA1 port A external input values (active when direction = input)
	// VIA1 PA external inputs. PA7 is supplied separately by SCC WReq.
	// MAME's Mac II family reads PA as:
	//   Mac II/FDHD/IIx:  0x81 (PA7 high, PA0 high)
	//   Mac IIcx/SE30:   0xC1 (PA7 high, PA6 high, PA0 high)
	reg [6:0] via_pa_ext;
	always @(*) begin
		case (macModel)
			3'd0, 3'd1:  via_pa_ext = 7'h7F; // Mac Plus, SE: all pulled high
			3'd2, 3'd3,
			3'd4:         via_pa_ext = 7'h01; // Mac II, Mac II FDHD, Mac IIx
			3'd5, 3'd6:  via_pa_ext = 7'h41; // Mac IIcx, SE/30
			default:      via_pa_ext = 7'h7F;
		endcase
	end
	// For output bits (oe=1): read back the output value
	// For input bits (oe=0): read the external hardware value
	assign via_pa_i = {sccWReq, (via_pa_oe[6:0] & via_pa_o[6:0]) | (~via_pa_oe[6:0] & via_pa_ext)};
	// Mac II drive selection is handled by the IWM devsel register. PA4 is
	// memory overlay on Mac II, so it must not gate the internal floppy.
	assign driveSel = 1'b1;
	// Mac II uses VIA PA4 for overlay (same as Mac Plus, NOT Mac SE's SEOverlay)
	assign memoryOverlayOn = ~via_pa_oe[4] | via_pa_o[4];
	assign SEL = ~via_pa_oe[5] | via_pa_o[5];
	assign vid_alt = ~via_pa_oe[6] | via_pa_o[6];

	//port B
	// Mac II VIA1 PB external inputs match MAME macii_state::via_in_b():
	//   PB3 = 1 when no ADB interrupt is pending, PB0 = RTC data, other bits 0.
	// Output bits still read back via via6522's DDR/output mux.
	wire rtcdat_o;
	wire rtc_cko;
	assign via_pb_i = machineType ? {4'b0000, _ADBint, 2'b00, rtcdat_o}
	                              : {1'b1, _hblank, mouseY2, mouseX2, mouseButton, 2'b11, rtcdat_o};

	// VIA2 PB7 output chains to VIA1 CA1 (60.15 Hz timer → 1-second interrupt)
	wire via2_pb7_to_via1_ca1;
	wire via1_ca1 = machineType ? via2_pb7_to_via1_ca1 : _vblank;

	// Mac II VIAs run at C7M/10 ~= 783.36 kHz in MAME and hardware, not at
	// the 32.5 MHz system clock. Keep register access on the CPU/E strobes,
	// but gate VIA timer countdowns with this average-rate enable.
	localparam [31:0] VIA_TIMER_HZ = 32'd783360;
	localparam [31:0] SYS_CLK_HZ = 32'd31334400;  // 2 × C15M (15.6672 MHz)
`ifdef SIMULATION
	reg [31:0] via_timer_hz = VIA_TIMER_HZ;
	initial begin
		integer hz;
		if ($value$plusargs("via_timer_hz=%d", hz) && hz > 0)
			via_timer_hz = hz[31:0];
	end
	wire [31:0] via_timer_step = via_timer_hz;
`else
	wire [31:0] via_timer_step = VIA_TIMER_HZ;
`endif
	reg [31:0] via_timer_acc = 32'd0;
	reg via_timer_tick = 1'b0;
	always @(posedge clk32) begin
		if (!_cpuReset) begin
			via_timer_acc <= 32'd0;
			via_timer_tick <= 1'b0;
		end else if (via_timer_acc >= (SYS_CLK_HZ - via_timer_step)) begin
			via_timer_acc <= via_timer_acc + via_timer_step - SYS_CLK_HZ;
			via_timer_tick <= 1'b1;
		end else begin
			via_timer_acc <= via_timer_acc + via_timer_step;
			via_timer_tick <= 1'b0;
		end
	end

	// Mac II VIA reads mirror the 8-bit VIA register on both 68000 byte lanes
	// (matching MAME's `(data & 0xff) | (data << 8)` handlers).
	assign viaDataOut[7:0] = viaDataOut[15:8];

	via6522 via(
		.clock      (clk32),
		.rising     (E_rising),
		.falling    (E_falling),
		.timer_tick (via_timer_tick),
		.reset      (!_cpuReset),

		.addr       (cpuAddrRegHi),
		.wen        (selectVIA && !_cpuVMA && !_cpuRW),
		.ren        (selectVIA && !_cpuVMA &&  _cpuRW),
		.data_in    (cpuDataIn[15:8]),
		.data_out   (viaDataOut[15:8]),

		.phi2_ref   (),

		//-- pio --
		.port_a_o   (via_pa_o),
		.port_a_t   (via_pa_oe),
		.port_a_i   (via_pa_i),

		.port_b_o   (via_pb_o),
		.port_b_t   (via_pb_oe),
		.port_b_i   (via_pb_i),

		//-- handshake pins
		.ca1_i      (via1_ca1),
		.ca2_i      (rtc_cko),

		.cb1_i      (kbdclk),
		.cb2_i      (cb2_i),
		.cb2_o      (cb2_o),
		.cb2_t      (cb2_t),

		.irq        (viaIrq),
		.sr_active  (via1_sr_active),

		// Snow-style timer-based SR completion
		.sr_ext_complete (via1_sr_ext_complete),
		.sr_ext_load     (via1_sr_ext_load),
		.sr_ext_data     (via1_sr_ext_data)
	);

`ifdef SIMULATION
	// VIA1 IRQ instrumentation — log every IFR/IER change so we can
	// identify which bit is re-asserting the level-1 autovector IRQ.
	reg [6:0] via1_ifr_d, via1_ier_d;
	reg       via1_irq_d;
	reg       onesec_d, pb7_d, ca1_c_d, ca2_c_d;
	reg [31:0] onesec_edges, pb7_edges, ca1_edges, ca2_edges;
	reg [31:0] via1_ora_reads, via1_ora_writes;
	reg [31:0] via1_ifr_writes, via1_ier_writes, via1_any_reads, via1_any_writes;
	reg [63:0] cyc;
	always @(posedge clk32) begin
		cyc <= cyc + 1;
		via1_ifr_d <= via.irq_flags;
		via1_ier_d <= via.irq_mask;
		via1_irq_d <= viaIrq;
		onesec_d   <= rtc_cko;
		pb7_d      <= via2_pb_o[7];
		ca1_c_d    <= via.ca1_c;
		ca2_c_d    <= via.ca2_c;

		// Edge counters — Mac II expectations at 32.5 MHz:
		//   RTC CKO:       1 Hz square wave edges every ~16.25M cycles
		//   via2 PB7:     ~60 Hz (VBL chain) → edge every ~540K cycles
		//   ca1_c (=PB7):  same as PB7
		//   ca2_c (=RTC CKO): same as RTC CKO
		if (rtc_cko && !onesec_d)        onesec_edges <= onesec_edges + 1;
		if (via2_pb_o[7] !== pb7_d)      pb7_edges    <= pb7_edges    + 1;
		if (via.ca1_c && !ca1_c_d)       ca1_edges    <= ca1_edges    + 1;
		if (via.ca2_c && !ca2_c_d)       ca2_edges    <= ca2_edges    + 1;

		// VIA1 register accesses
		if (via.falling) begin
			if (via.ren) via1_any_reads  <= via1_any_reads  + 1;
			if (via.wen) via1_any_writes <= via1_any_writes + 1;
			if (via.addr == 4'h1 && via.ren) via1_ora_reads  <= via1_ora_reads  + 1;
			if (via.addr == 4'h1 && via.wen) via1_ora_writes <= via1_ora_writes + 1;
			if (via.addr == 4'hD && via.wen) via1_ifr_writes <= via1_ifr_writes + 1;
			if (via.addr == 4'hE && via.wen) via1_ier_writes <= via1_ier_writes + 1;
		end

		if ($test$plusargs("via_debug") && via.irq_flags !== via1_ifr_d)
			$display("[VIA1 IFR] cyc=%0d ifr=%02h->%02h ier=%02h irq=%b",
			         cyc, via1_ifr_d, via.irq_flags, via.irq_mask, viaIrq);
		if ($test$plusargs("via_debug") && via.irq_mask !== via1_ier_d)
			$display("[VIA1 IER] cyc=%0d ier=%02h->%02h ifr=%02h irq=%b",
			         cyc, via1_ier_d, via.irq_mask, via.irq_flags, viaIrq);
		if ($test$plusargs("via_debug") && viaIrq !== via1_irq_d)
			$display("[VIA1 IRQ] cyc=%0d irq=%b->%b ifr=%02h ier=%02h",
			         cyc, via1_irq_d, viaIrq, via.irq_flags, via.irq_mask);

		// Periodic stats dump
		if ($test$plusargs("via_debug") && cyc != 0 && cyc[23:0] == 24'h0)
			$display("[STATS] cyc=%0d onesec=%0d pb7=%0d ca1=%0d ca2=%0d anyR=%0d anyW=%0d oraR=%0d oraW=%0d ifrW=%0d ierW=%0d ifr=%02h ier=%02h",
			         cyc, onesec_edges, pb7_edges, ca1_edges, ca2_edges,
			         via1_any_reads, via1_any_writes,
			         via1_ora_reads, via1_ora_writes,
			         via1_ifr_writes, via1_ier_writes,
			         via.irq_flags, via.irq_mask);
	end
`endif

	// VIA2 - NuBus interrupt routing, RAM sizing, timer chain
	wire [7:0] via2_pa_i, via2_pa_o, via2_pa_oe;
	wire [7:0] via2_pb_o, via2_pb_oe;
	wire via2Irq;

	assign _via2Irq = ~via2Irq;

	// VIA2 Port A: {ram_size[1:0], nubus_irq_state[5:0]}
	// PA[7:6] are RAM sizing pins (hardware config from SIMM decoder).
	// ROM reads these to determine SIMM configuration (Snow: expected_sz):
	//   00 = 256K SIMMs (1-2MB configs), 01 = 1MB SIMMs (4-8MB configs)
	// When DDR is output, loopback the output latch; when input, return HW config.
	// PA[5:0] are NuBus slot IRQ state (active-low, directly from video card slot E = bit 5)
	wire [1:0] ram_size_via = configRAMSize[1] ? 2'b01 : 2'b00; // 4MB/8MB->01, 1MB/2MB->00
	assign glueRAMSize = via2_pa_o[7:6];
	assign via2_pa_i = {(via2_pa_oe[7] ? via2_pa_o[7] : ram_size_via[1]),
	                    (via2_pa_oe[6] ? via2_pa_o[6] : ram_size_via[0]),
	                    (via2_pa_o[5] & via2_pa_oe[5]) | (nubus_irq_n & ~via2_pa_oe[5]),
	                    5'b11111};

	// VIA2 Port B: hardwired Mac II value
	// PB7 is output (timer chain to VIA1 CA1), PB[6:0] = 0x4F
	wire [7:0] via2_pb_i = 8'hCF;

	// VIA2 PB7 drives VIA1 CA1 for 60.15 Hz timer chain
	assign via2_pb7_to_via1_ca1 = via2_pb_o[7];

	// VIA2 PB3: Mac II HMMU/AMU enable — active when PB3 is driven low
	// (DDRB[3]=1, ORB[3]=0). Matches MAME macii.cpp `set_hmmu_enable` and
	// Snow bus.rs `amu_active` gating.
	assign hmmu_active = via2_pb_oe[3] & ~via2_pb_o[3];

	// VIA2 CA1: NuBus IRQ aggregator (active-low when any slot asserts IRQ)
	wire via2_ca1 = nubus_irq_n;  // directly from video card for now (Phase 1)

	assign via2DataOut[7:0] = via2DataOut[15:8];

	via6522 via2(
		.clock      (clk32),
		.rising     (E_rising),
		.falling    (E_falling),
		.timer_tick (via_timer_tick),
		.reset      (!_cpuReset),

		.addr       (cpuAddrRegHi),
		.wen        (selectVIA2 && !_cpuVMA && !_cpuRW),
		.ren        (selectVIA2 && !_cpuVMA &&  _cpuRW),
		.data_in    (cpuDataIn[15:8]),
		.data_out   (via2DataOut[15:8]),

		.phi2_ref   (),

		//-- pio --
		.port_a_o   (via2_pa_o),
		.port_a_t   (via2_pa_oe),
		.port_a_i   (via2_pa_i),

		.port_b_o   (via2_pb_o),
		.port_b_t   (via2_pb_oe),
		.port_b_i   (via2_pb_i),

		//-- handshake pins
		.ca1_i      (via2_ca1),
		.ca2_i      (1'b1),      // CA2 not used

		.cb1_i      (asc_irq_n), // CB1: ASC sound IRQ (active-low)
		.cb2_i      (1'b1),      // CB2 not used
		.cb2_o      (),
		.cb2_t      (),

		.irq        (via2Irq),
		.sr_active  (),          // not used for VIA2

		.sr_ext_complete (1'b0),
		.sr_ext_load     (1'b0),
		.sr_ext_data     (8'h00)
	);

	wire _rtccs   = ~via_pb_oe[2] | via_pb_o[2];
	wire rtcck    = ~via_pb_oe[1] | via_pb_o[1];
	wire rtcdat_i = ~via_pb_oe[0] | via_pb_o[0];

	rtc pram (
		.clk        (clk32),
		.reset      (!_cpuReset),
		.timestamp  (timestamp),
		._cs        (_rtccs),
		.ck         (rtcck),
		.dat_i      (rtcdat_i),
		.dat_o      (rtcdat_o),
		.cko        (rtc_cko)
	);

	wire _ADBint;
	wire ADBST0 = ~via_pb_oe[4] | via_pb_o[4];
	wire ADBST1 = ~via_pb_oe[5] | via_pb_o[5];
	wire ADBListen;
	wire via1_sr_active;
	wire adb_resp_pending;  // ADB transceiver still has response bytes to deliver

	// Snow-style timer-based VIA1 shift register completion.
	// The real VIA SR depends on CB1 clocking (kbdclk) which in turn depends
	// on via1_sr_active rising — but SR arming itself has verilator timing
	// issues with wen/falling overlap. This bypass mimics Snow's approach:
	// detect SR/ACR writes at the bus level and complete the shift after
	// a ~3ms delay (matching Snow's SHIFT_DELAY).
	wire via1_wr = selectVIA && !_cpuVMA && !_cpuRW;
	wire via1_sr_wr = via1_wr && cpuAddrRegHi == 4'hA;  // SR write (reg $A)
	wire via1_acr_wr = via1_wr && cpuAddrRegHi == 4'hB; // ACR write (reg $B)
	wire via1_rd    = selectVIA && !_cpuVMA && _cpuRW;  // VIA1 register read
	wire via1_sr_rd = via1_rd && cpuAddrRegHi == 4'hA;  // SR read (reg $A)

	reg [2:0] via1_acr_shift_mode;
	reg [7:0] via1_sr_shadow;
	reg [21:0] via1_shift_timer;
	reg via1_shift_dir;              // 1 = shift-out, 0 = shift-in
	reg via1_sr_ext_complete;
	reg via1_sr_ext_load;
	reg [7:0] via1_sr_ext_data;
	reg via1_sr_out_done;            // pulses when shift-out timer expires
	reg via1_sr_out_pending;
	reg via1_sr_out_ack;

	// ~3ms at 32.5MHz ≈ 97500 clocks. Use 100K for margin. Used while a real
	// response byte is being delivered, so multi-byte responses shift quickly.
	localparam SHIFT_DELAY = 22'd100000;
	// ~11ms (~90Hz). Used for the idle autopoll heartbeat re-arm when no
	// response byte is pending — matches the real Mac II ADB autopoll SR-IRQ
	// rate instead of the 3ms (~333Hz) rate that starved the ASC audio FIFO.
	localparam IDLE_DELAY  = 22'd357500;

	always @(posedge clk32) begin
		if (!_cpuReset) begin
			via1_acr_shift_mode <= 3'b000;
			via1_sr_shadow <= 8'h00;
			via1_shift_timer <= 22'd0;
			via1_shift_dir <= 1'b0;
			via1_sr_ext_complete <= 1'b0;
			via1_sr_ext_load <= 1'b0;
			via1_sr_ext_data <= 8'h00;
			via1_sr_out_done <= 1'b0;
			via1_sr_out_pending <= 1'b0;
		end else begin
			via1_sr_ext_complete <= 1'b0;
			via1_sr_ext_load <= 1'b0;
			via1_sr_out_done <= 1'b0;
			if (via1_sr_out_ack) begin
				via1_sr_out_pending <= 1'b0;
			end

			// Track ACR writes — shadow the shift mode bits
			if (via1_acr_wr) begin
				via1_acr_shift_mode <= cpuDataIn[12:10]; // bits [4:2] of byte
				// ACR changed to shift-out mode: start timer
				if (cpuDataIn[12:10] == 3'b111 && via1_acr_shift_mode != 3'b111) begin
					via1_shift_timer <= SHIFT_DELAY;
					via1_shift_dir <= 1'b1;
				end
				// ACR changed to shift-in mode: start timer for response
				else if (cpuDataIn[12:10] == 3'b011 && via1_acr_shift_mode != 3'b011) begin
					via1_shift_timer <= SHIFT_DELAY;
					via1_shift_dir <= 1'b0;
				end
				// ACR changed to disabled: cancel any pending shift
				else if (cpuDataIn[12:10] == 3'b000) begin
					via1_shift_timer <= 22'd0;
				end
			end

			// Track SR reads — on Mac II the ADB driver reads the VIA SR to
			// fetch each shift-in response byte, and (like a real 6522, and
			// like via6522's trigger_serial which fires on ren|wen of reg $A)
			// that read initiates the NEXT shift-in. via6522 re-arms its
			// shift_active on the read, but the timer shim only watched writes,
			// so the read-initiated shift-in never got a timer and never
			// completed -> sr_ext_complete never pulsed -> shift_active/
			// sr_active stuck high -> the CPU's completion poll spun forever.
			// (Invisible in Verilator's ideal SR timing.) Arm the shift-in
			// timer on an SR read while in shift-in mode to match.
			//
			// The ADB driver leaves ACR in shift-in mode (011) during autopoll
			// and uses the SR-read -> completion -> IFR[2] -> read chain as its
			// polling heartbeat, so we must ALWAYS re-arm here (gating it off
			// when the response buffer drained killed the heartbeat and froze
			// the mouse). But re-arming at the 3ms SHIFT_DELAY every time made
			// that heartbeat run at ~333Hz, far above the real Mac II ADB
			// autopoll SR-IRQ rate, starving the ASC audio FIFO (corrupt audio).
			// Use the fast delay only while a real response byte is pending;
			// otherwise use IDLE_DELAY (~90Hz) to match real-hardware cadence.
			if (via1_sr_rd && via1_acr_shift_mode == 3'b011) begin
				via1_shift_timer <= adb_resp_pending ? SHIFT_DELAY : IDLE_DELAY;
				via1_shift_dir <= 1'b0;
			end

			// Track SR writes — shadow the data and (re)start timer
			if (via1_sr_wr) begin
				via1_sr_shadow <= cpuDataIn[15:8];
				if (via1_acr_shift_mode == 3'b111) begin
					via1_shift_timer <= SHIFT_DELAY;
					via1_shift_dir <= 1'b1;
				end
				if (via1_acr_shift_mode == 3'b011) begin
					via1_shift_timer <= SHIFT_DELAY;
					via1_shift_dir <= 1'b0;
				end
			end

			// Countdown and complete
			if (via1_shift_timer > 22'd1) begin
				via1_shift_timer <= via1_shift_timer - 22'd1;
			end else if (via1_shift_timer == 22'd1) begin
				via1_shift_timer <= 22'd0;
				via1_sr_ext_complete <= 1'b1;
				via1_sr_out_done <= via1_shift_dir;
				if (via1_shift_dir) begin
					via1_sr_out_pending <= 1'b1;
				end
				if (!via1_shift_dir) begin
					// Shift-in complete: load response into SR
					via1_sr_ext_load <= 1'b1;
					via1_sr_ext_data <= kbd_to_mac;
				end
			end
		end
	end

	reg kbdclk;
	reg [10:0] kbdclk_count;
	reg kbd_transmitting, kbd_wait_receiving, kbd_receiving;
	reg adb_recv_pending;
	reg [2:0] kbd_bitcnt;

	wire cb2_i = kbddata_o;
	wire cb2_o, cb2_t;
	wire kbddat_i = ~cb2_t | cb2_o;
	reg kbddata_o;
	reg  [7:0] kbd_to_mac;
	reg kbd_data_valid;

	// Keyboard transmitter-receiver / ADB CB1 clock generator
	// For Mac II: VIA1 SR needs CB1 toggles to shift data in/out.
	// The clock runs when kbd_transmitting/receiving (legacy) OR when
	// For Mac II ADB, only start CB1 clock when we are actively transmitting or
	// receiving. This prevents the clock from starting prematurely (before ADB
	// response data is loaded) when the VIA SR is re-armed but the ORB state
	// transition hasn't happened yet.
	// Mac II uses Snow-style atomic SR byte delivery via via1_sr_ext_complete;
	// path B (CB1 bit-bang) is disabled entirely on Mac II to avoid racing
	// path A. See docs/adb_shift_plan.md.
	wire kbd_clk_active = !machineType &&
	                      ((kbd_transmitting && !kbd_wait_receiving) || kbd_receiving);
	always @(posedge clk32) begin
		if (clk8_en_p) begin
			if (kbd_clk_active) begin
				kbdclk_count <= kbdclk_count + 1'd1;
				if (kbdclk_count == (machineType ? 8'd80 : 12'd1300)) begin // ~165usec - Mac Plus / faster - ADB
					kbdclk <= ~kbdclk;
					kbdclk_count <= 0;
					if (kbdclk) begin
						// shift before the falling edge
						if (kbd_transmitting) kbd_out_data <= { kbd_out_data[6:0], kbddat_i };
						if (kbd_receiving) kbddata_o <= kbd_to_mac[7-kbd_bitcnt];
					end
				end
			end else begin
				kbdclk_count <= 0;
				kbdclk <= 1;
			end
		end
	end

	// Keyboard control
	always @(posedge clk32) begin
		reg kbdclk_d;
		reg ADBListenD;
		reg via1_sr_active_d;
		if (!_cpuReset) begin
			kbd_bitcnt <= 0;
			kbd_transmitting <= 0;
			kbd_wait_receiving <= 0;
			kbd_data_valid <= 0;
			adb_recv_pending <= 0;
			ADBListenD <= 0;
			via1_sr_active_d <= 0;
			via1_sr_out_ack <= 1'b0;
		end else if (clk8_en_p) begin
			if (kbd_in_strobe && !machineType) begin
				kbd_to_mac <= kbd_in_data;
				kbd_data_valid <= 1;
			end

			// ADB response: buffer the byte, defer clocking until VIA1 SR is armed.
			// The ROM reads/writes VIA1 SR to arm the shift register (shift_active=1)
			// before expecting CB1 clocks. Starting immediately would race ahead.
			// Mac II: stash ADB response byte for path A (3 ms SR timer)
			// to deliver via sr_ext_data = kbd_to_mac. Do NOT start path B.
			if (adb_dout_strobe && machineType) begin
				kbd_to_mac <= adb_dout;
			end

			kbd_out_strobe <= 0;
			adb_din_strobe <= 0;
			via1_sr_out_ack <= 1'b0;
			kbdclk_d <= kbdclk;
			via1_sr_active_d <= via1_sr_active;

			// Snow-style shift-out completion: deliver byte to ADB transceiver
			if (via1_sr_out_pending && machineType) begin
				adb_din_strobe <= 1;
				adb_din <= via1_sr_shadow;
				via1_sr_out_ack <= 1'b1;
			end

			// Only the Macintosh can initiate communication over the keyboard lines. On
			// power-up of either the Macintosh or the keyboard, the Macintosh is in
			// charge, and the external device is passive. The Macintosh signals that it's
			// ready to begin communication by pulling the keyboard data line low.
			if (!machineType && !kbd_transmitting && !kbd_receiving && !kbddat_i) begin
				kbd_transmitting <= 1;
				kbd_bitcnt <= 0;
			end

			// ADB transmission start — either from ADB Listen or VIA1 SR shift-out.
			// VIA1 SR drives CB2 with command bits; we capture them into kbd_out_data
			// and deliver to ADB module after 8 bits, same as the Listen path.
			// Only start when VIA is shifting OUT (cb2_t=1). When VIA is shifting IN
			// (cb2_t=0, ACR mode 011), we must NOT start kbd_transmitting — instead
			// kbd_receiving will start via adb_recv_pending to drive response data on CB2.
			// Mac II path-B start trigger removed: path A (via1_sr_out_done →
			// adb_din_strobe) delivers the shifted-out byte to the ADB
			// transceiver 3 ms after the SR write. See docs/adb_shift_plan.md.

			// The last bit of the command leaves the keyboard data line low; the
			// Macintosh then indicates it's ready to receive the keyboard's response by
			// setting the data line high.
			if (kbd_wait_receiving && kbddat_i && kbd_data_valid) begin
				kbd_wait_receiving <= 0;
				kbd_receiving <= 1;
				kbd_transmitting <= 0;
			end

			// send/receive bits at rising edge of the keyboard clock
			if (~kbdclk_d & kbdclk) begin
				kbd_bitcnt <= kbd_bitcnt + 1'd1;

				if (kbd_bitcnt == 3'd7) begin
					if (kbd_transmitting) begin
						if (!machineType) begin
							kbd_out_strobe <= 1;
							kbd_wait_receiving <= 1;
						end else begin
							adb_din_strobe <= 1;
							adb_din <= kbd_out_data;
							kbd_transmitting <= 0;
						end
					end
					if (kbd_receiving) begin
						kbd_receiving <= 0;
						kbd_data_valid <= 0;
					end
				end
			end
		end
	end

	// IWM — clocked at C15M (15.6672 MHz) per MAME spec; module divides by 2
	// internally to recover the ~7.8336 MHz fclk that times GCR bit cells.
	iwm i(
		.clk(clk32),
		.cep(clk16_en_p),
		.cen(clk16_en_n),
		._reset(_cpuReset),
		.selectIWM(selectIWM),
		._cpuRW(_cpuRW),
		._cpuUDS(_cpuUDS),
		._cpuLDS(_cpuLDS),
		.dataIn(cpuDataIn),
		.cpuAddrRegHi(cpuAddrRegHi),
		.SEL(SEL),
		.driveSel(driveSel),
		.dataOut(iwmDataOut),
		.insertDisk(insertDisk),
		.diskSides(diskSides),
		.diskEject(diskEject),
		.diskMotor(diskMotor),
		.diskAct(diskAct),

		.dskReadAddrInt(dskReadAddrInt),
		.dskReadAckInt(dskReadAckInt),
		.dskReadAddrExt(dskReadAddrExt),
		.dskReadAckExt(dskReadAckExt),
		.dskReadData(memoryDataIn[7:0])
	);

	// SCC
	scc s(
		.clk(clk32),
		.cep(clk8_en_p),
		.cen(clk8_en_n),
		.reset_hw(~_cpuReset),
		.cs(selectSCC && (_cpuLDS == 1'b0 || _cpuUDS == 1'b0)),
		.we(!_cpuRW),  // Mac II: CPU R/W signal (Mac Plus used !_cpuLDS for odd-address writes)
		.rs(cpuAddrRegLo), 
		.wdata(cpuDataIn[15:8]),
		.rdata(sccDataOut),
		._irq(_sccIrq),
		.dcd_a(mouseX1),
		.dcd_b(mouseY1),
		.wreq(sccWReq),
		.txd(serialOut),
		.rxd(serialIn),
		.cts(serialCTS),
		.rts(serialRTS)
		);

	// Video
	videoShifter vs(
		.clk32(clk32),
		.memoryLatch(memoryLatch),
		.dataIn(memoryDataIn),
		.loadPixels(loadPixels),
		.pixelOut(pixelOut));

	// Mouse
	ps2_mouse mouse(
		.clk(clk32),
		.ce(clk8_en_p),
		.reset(~_cpuReset),
		.ps2_mouse(ps2_mouse),
		.x1(mouseX1),
		.y1(mouseY1),
		.x2(mouseX2),
		.y2(mouseY2),
		.button(mouseButton));

	wire [7:0] kbd_in_data;
	wire kbd_in_strobe;
	reg  [7:0] kbd_out_data;
	reg  kbd_out_strobe;

	// Keyboard
	ps2_kbd kbd(
		.clk(clk32),
		.ce(clk8_en_p),
		.reset(~_cpuReset),
		.ps2_key(ps2_key),
		.data_out(kbd_out_data),              // data from mac
		.strobe_out(kbd_out_strobe),
		.data_in(kbd_in_data),         // data to mac
		.strobe_in(kbd_in_strobe),
		.capslock(capslock)
		);

	reg  [7:0] adb_din;
	reg        adb_din_strobe;
	wire [7:0] adb_dout;
	wire       adb_dout_strobe;

	adb adb(
		.clk(clk32),
		.clk_en(clk8_en_p),
		.reset(~_cpuReset),
		.st({ADBST1, ADBST0}),
		._int(_ADBint),
		.viaBusy(kbd_transmitting || kbd_receiving),
		.listen(ADBListen),
		.adb_din(adb_din),
		.adb_din_strobe(adb_din_strobe),
		.adb_dout(adb_dout),
		.adb_dout_strobe(adb_dout_strobe),

		.ps2_mouse(ps2_mouse),
		.ps2_key(ps2_key),
		.resp_pending(adb_resp_pending),
		.dbg_adb(adb_dbg)
	);

	// Read-only ADB/VIA1-SR debug snapshot for JTAG ISSP:
	// [31:29] acr_shift_mode [28] shift_dir [27] sr_active [26] sr_out_done
	// [25] sr_out_ack [24] sr_out_pending [23:16] sr_shadow [15:0] adb FSM state
	wire [15:0] adb_dbg;
	assign dbg_adb = {via1_acr_shift_mode, via1_shift_dir, via1_sr_active,
	                  via1_sr_out_done, via1_sr_out_ack, via1_sr_out_pending,
	                  via1_sr_shadow, adb_dbg};

	// Shift-in completion diagnosis: [17:1]=via1_shift_timer (is it counting
	// down or stuck?), [0]=via1_sr_ext_complete pulse (does completion ever
	// fire?). dbg_min counts the completes and snapshots the timer.
	assign dbg_adb2 = {via1_shift_timer[16:0], via1_sr_ext_complete};

endmodule

// NOTE: The rest of the file remains unchanged - this is just the critical fix
// to move the parameter definition to the module header where it belongs.
// The parameter SCSI_DEVS is now properly defined BEFORE it's used in the port list.
