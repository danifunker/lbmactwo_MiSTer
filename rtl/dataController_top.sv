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
	// this SDRAM slot started with the CPU's own read command at its t=0
	// (registered in LBMacTwo.sv) — the only slots whose memoryLatch tail
	// may be captured as CPU read data. See cpu_data comment below.
	input cpuSlotOwned,
	input cpu_rd_take,   // COHERENCY FIX (2026-06-13): only latch/forward read data
	                     // when its source address matched the request (LBMacTwo.sv)
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

	// PRAM persistence passthrough (LBMacTwo.sv PRAM FSM <-> rtc pram[])
	input        pram_load_wr,
	input  [7:0] pram_load_addr,
	input  [7:0] pram_load_data,
	input  [7:0] pram_save_addr,
	output [7:0] pram_save_data,
	output       pram_wr_stb,

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
	input [1:0] diskMFM,    // disk is MFM-format (ISM/SWIM path): {ext,int}
	input [1:0] diskHD,     // disk is 1.44MB HD (vs 720K DD): {ext,int}
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
	input             [4:0] sd_buff_addr_hi, // hps_io addr[12:8] (CD whole-frame bursts)
	input            [15:0] sd_buff_dout,
	output           [15:0] sd_buff_din[SCSI_DEVS],
	input                   sd_buff_wr,

	// JTAG debug passthrough — MacLC-transplant export set (2026-08-08).
	// Probe decks are deleted; these feed ONLY the top-level marginality
	// anchor. The pre-transplant v3.x taps (scsi_wr/wr0/regs/selt0/wring*/
	// selid/winh*/iwh/cmdr0/star0/lbar0*/xorr0*/selfail0) no longer exist in
	// MacLC's ncr5380/scsi.v; their anchor-law equivalents are wr/wrfb/ring.
	output           [31:0] dbg_ring0,     // read-ring serve/refill, target 0 (anchor)
	output           [31:0] dbg_ring1,     // read-ring serve/refill, target 1 (anchor)
	output           [15:0] dbg_scsi,
	output           [15:0] dbg_scsi2,
	output           [15:0] dbg_scsi3,
	output           [15:0] dbg_scsi4,
	output           [15:0] dbg_scsi5,
	output           [31:0] dbg_wr,        // write-stall snapshot, data-phase-routed
	output           [31:0] dbg_wrfb,      // write first-beat forensics (anchor)
	output           [31:0] dbg_ncr,       // NCR5380 host-side pseudo-DMA stall
	output           [31:0] dbg_ncr2,      // NCR5380 write loss-mechanism counters
	output           [31:0] dbg_via2_irq,  // VIA2 {irq_out, IER, IFR_eff, PCR, ACR} (PVIA)
	output           [31:0] dbg_adb,
	output           [17:0] dbg_adb2,
	output           [31:0] dbg_adb3,   // last 4 bytes CPU READ from VIA1 SR
	output           [31:0] dbg_adb4,   // last 4 bytes LOADED into VIA1 SR (shift-in)
	output                  mouse_has_event_o,

	// Floppy/IWM byte-stream diagnostics (PFLP / PIWM / PFLT probes)
	output           [15:0] dbg_flp_byte_cnt,
	output           [15:0] dbg_flp_miss_cnt,
	output           [7:0]  dbg_flp_disk_data,
	output           [15:0] dbg_iwm_ack_cnt,
	output           [7:0]  dbg_iwm_latch,
	output           [6:0]  dbg_iwm_arm_high,
	output           [6:0]  dbg_flp_track,
	output                  dbg_flp_side,
	output           [15:0] dbg_flp_step_cnt,

	// PIRQ probe: per-source IRQ assert signals (active-low) for edge counting
	// in dbg_min. These are the inputs to the _cpuIPL priority cascade.
	output                  dbg_via1_irq_n,
	output                  dbg_via2_irq_n,
	output                  dbg_scc_irq_n
);

	// CPU reset generation
	// For initial CPU reset, RESET and HALT must be asserted for at least 100ms.
	// At clk8_en_p = 7.8336 MHz that's ~783,360 ticks; the 20-bit counter
	// (1,048,575 ticks ≈ 134 ms) leaves ample margin.
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
	wire [15:0] iwmDataOut;   // SWIM read data (name kept for lineage)
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

	// JTAG-debug taps on the unencoded source signals.
	assign dbg_via1_irq_n = _viaIrq;
	assign dbg_via2_irq_n = _via2Irq;
	assign dbg_scc_irq_n  = _sccIrq;


	// Latch SDRAM read data ONLY from a slot the CPU's own read command
	// started (cpuSlotOwned, registered at the slot's t=0 in LBMacTwo.sv).
	// The old `cpuBusControl && memoryLatch` gate latched EVERY CPU-slot
	// tail — including slots whose SDRAM transaction was a refresh or a
	// neighbor master's, leaving the PREVIOUS transaction's word (legacy
	// slot-0 video fetch, or the CPU's own prior fetch) in cpu_data. That
	// neighbor word reaching the CPU = the journal 0x51C9/0x0000 disk
	// corruption and the mid-pseudo-DMA F-line (vec 11) stray trap.
	reg [15:0] cpu_data;
	always @(posedge clk32) if (cpuSlotOwned && memoryLatch && cpu_rd_take) cpu_data <= memoryDataIn;

	// SCSI read-path fit-stabilization (port of MacLC periph_din_reg, 0c8844b —
	// the fix behind the LC/LCII "SCSI latch" reliability): the deepest cone in
	// the whole CPU read mux is the 5380 CSR's BSY bit (scsi.v phase reg →
	// |target_bsy → CSR → ncr5380 rdata → this mux → tg68_din_r). Left
	// combinational it fits with ~0.2-0.4 ns slack on a lucky placement and
	// FAILS on an unlucky one — the CPU then intermittently reads BSY=0 while
	// the target holds BSY=1, the SCSI Manager aborts, and the bus resets (the
	// boot-time dice-roll class). Registering it makes the margin
	// fit-independent. The +1 clk32 of staleness is absorbed on every consumer:
	// both PIO CSR reads (immediate-DTACK async cycle) and DREQ-gated
	// pseudo-DMA reads latch tg68_din_r at kernel s_state 6, >= 4 phi ticks
	// (>= 8 clk32) after AS/select settle, and a status read does not advance
	// the SCSI protocol, so the registered copy is settled long before capture.
	// DMA read data is start-of-cycle-latched inside ncr5380 (dma_*_latched /
	// the dma_settle fix), so its registered copy is likewise stable at capture.
	// Matching LBMacTwo.sdc multicycle credits the real window on the cone INTO
	// this register; its fan-out to the CPU stays single-cycle.
	reg [15:0] scsi_din_reg;
	always @(posedge clk32) scsi_din_reg <= scsiDataOut;

	// CPU-side data output mux
	assign cpuDataOut = selectASC ? { ascDataOut, ascDataOut } :
							  selectIWM ? iwmDataOut :
							  selectVIA ? viaDataOut :
							  selectVIA2 ? via2DataOut :
							  selectNuBus ? nubusDataIn :
							  selectSCC ? { sccDataOut, 8'hEF } :
							  selectSCSI ? scsi_din_reg :
							  (cpuSlotOwned && memoryLatch && cpu_rd_take) ? memoryDataIn : cpu_data;

	// Memory-side
	assign memoryDataOut = cpuDataIn;

	// SCSI
	// Latched 5380 interrupt → VIA2 CB2 (IFR bit 3); DRQ → VIA2 CA2 (IFR
	// bit 0). Mac II wiring per Snow macii/via2.rs. Active-low into the VIA:
	// the OS programs VIA2 PCR=0 (input, negative edge), so the flag latches
	// on assertion. The HD SC 4.3 driver's async path sleeps on these flags
	// between pseudo-DMA chunks — unwired, it polls the IFR forever (the
	// Welcome wedge at every HPS 512-byte REQ pause).
	// CA2 takes the RAW bus REQ level (o_drq_lvl, Snow get_drq() parity),
	// NOT the flow-controlled dreq: Snow's healthy-boot trace shows the
	// System driver's post-transfer completion wait rides IFR bit 0 through
	// the DATA→STATUS handoff, where dreq (dma_en-gated + settle-masked)
	// goes quiet — that starvation is the MacAtrium first-boot livelock.
	// scsiDREQ still paces DACK-cycle DTACK at the top level (untouched).
	wire scsiIRQ;
	wire scsiDRQlvl;
	// MacLC SCSI transplant (2026-08-08, owner call): ncr5380.sv + scsi.v are
	// now the MacLC master pair wholesale (their months of HW-hardened fixes:
	// port-B prefetch dpram + cc81843 host-face pipeline, write lane-slip fix,
	// REQ look-ahead stall, 12-byte CDBs, Toolbox + CD command sets). Only
	// documented seams differ: o_drq_lvl (Mac II VIA2 CA2), CDROM_PRESENT(0)
	// (CD target compiled out until the feature round frees its ~5.7K ALMs).
	// The old scsi_empty_cd stub saga (2026-07-10 reset storm, probe-proven on
	// be5c1800) is closed by construction: MacLC's pair has no empty-CD
	// instantiation, and the real CD target — when enabled — completes 12-byte
	// group-5 CDBs.
	// Toolbox note: target 0 carries TOOLBOX_ENABLE in MacLC's ncr5380; with
	// tb_mounted tied 0 below it stays dormant (tb_ready never sets) until the
	// VD_TOOLBOX hps slot is wired in the feature round.
	ncr5380 #(.DEVS(SCSI_DEVS), .CDROM_PRESENT(0)) scsi(
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
		.o_irq(scsiIRQ),
		.o_drq_lvl(scsiDRQlvl),
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
		.sd_buff_addr_hi(sd_buff_addr_hi),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din(sd_buff_din),
		.sd_buff_wr(sd_buff_wr),

		// Toolbox / CD-changer / CD-ROM hps slots: not wired yet (VDNUM=3).
		// Inputs tied inactive; outputs open. Feature round wires slots 3/4/5.
		.tb_mounted(1'b0),
		.tb_lba(),
		.tb_rd(),
		.tb_wr(),
		.tb_ack(1'b0),
		.tb_buff_din(),
		.cdtb_mounted(1'b0),
		.cdtb_lba(),
		.cdtb_rd(),
		.cdtb_wr(),
		.cdtb_ack(1'b0),
		.cdtb_buff_din(),
		.cd_snd_l(),
		.cd_snd_r(),
		.cd_enable(1'b0),
		.cd_img_mounted(1'b0),
		.cd_io_lba(),
		.cd_io_rd(),
		.cd_io_wr(),
		.cd_io_ack(1'b0),
		.cd_sd_buff_din(),

		.dbg_scsi(dbg_scsi),
		.dbg_scsi2(dbg_scsi2),
		.dbg_scsi3(dbg_scsi3),
		.dbg_scsi4(dbg_scsi4),
		.dbg_scsi5(dbg_scsi5),
		.dbg_wr(dbg_wr),
		.dbg_wrfb(dbg_wrfb),
		.dbg_cda0(),
		.dbg_cda1(),
		.dbg_cda2(),
		.dbg_cda3(),
		.dbg_cda4(),
		.dbg_cdur(),
		.dbg_ncr(dbg_ncr),
		.dbg_ncr2(dbg_ncr2),
		.dbg_ring0(dbg_ring0),
		.dbg_ring1(dbg_ring1)
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

	// Mac II VIAs run at C7M/10 ≈ 783.36 kHz in MAME and hardware, not at
	// the 31.3344 MHz system clock. Keep register access on the CPU/E strobes,
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
		.ca2_lvl_i  (1'b0),      // level overlays unused on VIA1
		.cb2_lvl_i  (1'b0),

		.cb1_i      (kbdclk),
		.cb2_i      (cb2_i),
		.cb2_o      (cb2_o),
		.cb2_t      (cb2_t),

		.irq        (viaIrq),
		.dbg_irq_state (),
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

		// Edge counters — Mac II expectations at clk_sys = 31.3344 MHz:
		//   RTC CKO:       1 Hz square wave edges every ~15.67M cycles
		//   via2 PB7:     ~60 Hz (VBL chain) → edge every ~522K cycles
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
		// PURE-LEVEL SCSI flags (Snow-exact, 2026-07-11 v2). Snow's IFR bits
		// 0/3 are re-stamped from the live 5380 lines every tick — they SELF-
		// CLEAR when the line drops. The 6522 edge latch broke that: once the
		// first REQ set IFR bit 0, it stayed 1 without an ORA access, so the
		// driver's per-byte "wait for DRQ" passed while REQ was still low and
		// the CDB byte it then wrote was swallowed (boot-A f71b27c capture:
		// 7th dialog opens, CDB never completes, PCMD ring frozen at the map
		// walk). Tie the edge inputs inactive: no edge events, IFR bit 0/3 =
		// the lvl overlays alone = live REQ / live 5380 irq_latch. VIA-side
		// clears become no-ops on never-set latches, matching Snow's
		// overridden-clear semantics exactly.
		.ca2_i      (1'b1),        // no edges: IFR bit 0 = pure REQ level
		.ca2_lvl_i  (scsiDRQlvl),  // = o_drq_lvl = raw bus REQ, any phase
		.cb2_lvl_i  (scsiIRQ),   // level overlay: IFR bit 3 reads 1 while IRQ latched

		.cb1_i      (asc_irq_n), // CB1: ASC sound IRQ (active-low)
		.cb2_i      (1'b1),      // no edges: IFR bit 3 = pure 5380 irq_latch level
		.cb2_o      (),
		.cb2_t      (),

		.irq        (via2Irq),
		.dbg_irq_state (dbg_via2_irq),
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
		.cko        (rtc_cko),

		.pram_load_wr   (pram_load_wr),
		.pram_load_addr (pram_load_addr),
		.pram_load_data (pram_load_data),
		.pram_save_addr (pram_save_addr),
		.pram_save_data (pram_save_data),
		.pram_wr_stb    (pram_wr_stb)
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
	// High once the ADB chip has produced a response byte (adb_dout_strobe)
	// that the shift-in completion hasn't yet delivered to the SR. Lets the
	// shim deliver bytes the instant they're produced instead of on a blind
	// timer, eliminating the stale-byte reads that corrupted mouse packets.
	reg via1_kbd_to_mac_fresh;

	// ~3ms at 31.3344 MHz ≈ 94,000 clocks. Use 100K for margin. Used while a
	// real response byte is being delivered, so multi-byte responses shift
	// quickly.
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
			via1_kbd_to_mac_fresh <= 1'b0;
		end else begin
			via1_sr_ext_complete <= 1'b0;
			via1_sr_ext_load <= 1'b0;
			via1_sr_out_done <= 1'b0;
			if (via1_sr_out_ack) begin
				via1_sr_out_pending <= 1'b0;
			end

			// Latch "fresh response byte available" the cycle the ADB chip
			// strobes a new byte out. kbd_to_mac (other always block) captures
			// the byte on the same clk8_en_p window, so by the time the
			// shift-in completion below consumes it the value is valid.
			if (clk8_en_p && adb_dout_strobe && machineType) begin
				via1_kbd_to_mac_fresh <= 1'b1;
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

			// Countdown.
			if (via1_shift_timer > 22'd1) begin
				via1_shift_timer <= via1_shift_timer - 22'd1;
			end

			// Completion.
			//
			// SHIFT-OUT (cmd byte to chip): unchanged — fire on timer expiry,
			// delivering the byte to the ADB transceiver.
			if (via1_shift_dir) begin
				if (via1_shift_timer == 22'd1) begin
					via1_shift_timer    <= 22'd0;
					via1_sr_ext_complete <= 1'b1;
					via1_sr_out_done     <= 1'b1;
					via1_sr_out_pending  <= 1'b1;
				end
			end else begin
				// SHIFT-IN (response byte to CPU). The old code completed on
				// the free-running 3ms timer, decoupled from when the ADB
				// chip actually produced the byte — so it fired 1-2 times
				// with STALE kbd_to_mac (00) before the real response, and
				// ROM's first read even grabbed the leftover cmd byte from
				// shift_reg. ROM framed that garbage as the mouse packet and
				// rejected it. Fix:
				//   (a) the instant the chip produces a fresh byte
				//       (adb_dout_strobe -> via1_kbd_to_mac_fresh), complete
				//       immediately with that byte — no stale window;
				//   (b) otherwise fall back to the timer ONLY when it is safe
				//       (no response pending, or the bus is IDLE because ROM
				//       aborted) so the idle-autopoll heartbeat keeps firing
				//       and we never deadlock waiting for a byte that won't come.
				if (via1_kbd_to_mac_fresh) begin
					via1_shift_timer      <= 22'd0;
					via1_sr_ext_complete  <= 1'b1;
					via1_sr_ext_load      <= 1'b1;
					via1_sr_ext_data      <= kbd_to_mac;
					via1_kbd_to_mac_fresh <= 1'b0;
				end else if (via1_shift_timer == 22'd1) begin
					if (!adb_resp_pending || adb_bus_idle) begin
						via1_shift_timer     <= 22'd0;
						via1_sr_ext_complete <= 1'b1;
						via1_sr_ext_load     <= 1'b1;
						via1_sr_ext_data     <= kbd_to_mac;
					end
					// else: response pending but chip hasn't produced the
					// next byte yet — hold timer at 1, re-check next cycle.
				end
			end
		end
	end

	// ADB bus idle = {ST1,ST0} == 2'b11 (see adb.sv ST_IDLE). Used to release
	// the shift-in fresh-byte gate if ROM abandons a transaction.
	wire adb_bus_idle = ADBST0 & ADBST1;

	// === DIAGNOSTIC: SR byte-sequence capture ===
	// dbg_adb3: last 4 bytes the CPU READ from VIA1 SR (high byte, where the
	//   Mac 6522 presents SR). This is ground truth of what ROM receives.
	// dbg_adb4: last 4 bytes LOADED into the SR by the shim (shift-in path).
	// Compare the two: if loads look right (e.g. 83,85,83,85 from the forced
	// mouse response) but reads differ, the SR is being corrupted between
	// load and read (e.g. the cmd-byte shift-out echoing into shift_reg).
	reg        via1_sr_rd_d;
	reg [31:0] dbg_sr_read_seq;
	reg [31:0] dbg_sr_load_seq;
	always @(posedge clk32) begin
		if (!_cpuReset) begin
			via1_sr_rd_d    <= 1'b0;
			dbg_sr_read_seq <= 32'd0;
			dbg_sr_load_seq <= 32'd0;
		end else begin
			via1_sr_rd_d <= via1_sr_rd;
			// Capture ONLY shift-in-mode reads (ACR=011) so the sequence
			// reflects what ROM frames as DATA, excluding the harmless
			// transmit-flag-clear read that returns the cmd-byte echo while
			// ACR is still in shift-out mode (111).
			if (via1_sr_rd && !via1_sr_rd_d && via1_acr_shift_mode == 3'b011)
				dbg_sr_read_seq <= {dbg_sr_read_seq[23:0], viaDataOut[15:8]};
			if (via1_sr_ext_load && !via1_shift_dir)
				dbg_sr_load_seq <= {dbg_sr_load_seq[23:0], via1_sr_ext_data};
		end
	end
	assign dbg_adb3 = dbg_sr_read_seq;
	assign dbg_adb4 = dbg_sr_load_seq;

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
	// IWM-era probe outputs with no SWIM equivalent: hold at 0 so the top-level
	// probe wiring (dbg_iwm_ack_cnt / dbg_iwm_arm_high) stays connected.
	assign dbg_iwm_ack_cnt  = 16'd0;
	assign dbg_iwm_arm_high = 7'd0;

	swim sw(
		.clk(clk32),
		.cep(clk8_en_p),
		.cen(clk8_en_n),
		._reset(_cpuReset),
		.selectSWIM(selectIWM),
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
		.diskMFM(diskMFM),
		.diskHD(diskHD),
		.diskEject(diskEject),
		.diskMotor(diskMotor),
		.diskAct(diskAct),

		.dskReadAddrInt(dskReadAddrInt),
		.dskReadAckInt(dskReadAckInt),
		.dskReadAddrExt(dskReadAddrExt),
		.dskReadAckExt(dskReadAckExt),
		.dskReadData(memoryDataIn[7:0]),

		// PFLP / PIWM diagnostic ports
		.dbg_iwm_latch(dbg_iwm_latch),
		.dbg_flp_byte_cnt(dbg_flp_byte_cnt),
		.dbg_flp_miss_cnt(dbg_flp_miss_cnt),
		.dbg_flp_disk_data(dbg_flp_disk_data),
		.dbg_flp_track(dbg_flp_track),
		.dbg_flp_side(dbg_flp_side),
		.dbg_flp_step_cnt(dbg_flp_step_cnt)
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
		.dbg_adb(adb_dbg),
		.mouse_has_event_o(mouse_has_event_o)
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

`ifdef SIMULATION
	// ADB/VIA1-SR event trace (+adb_debug): every CPU-visible event of the
	// transceiver dialog, for the System-startup ADBReInit stall. One line
	// per event; the 0x6DD8 spin means the interesting run is only a few
	// hundred lines.
	reg [1:0] adb_st_d;
	always @(posedge clk32) begin
		if ($test$plusargs("adb_debug")) begin
			adb_st_d <= {ADBST1, ADBST0};
			if (adb_st_d != {ADBST1, ADBST0})
				$display("[ADB %0t] ST %b -> %b", $time, adb_st_d, {ADBST1, ADBST0});
			if (via1_acr_wr)
				$display("[ADB %0t] ACR<=%02x (sr mode %b -> %b)", $time,
				         cpuDataIn[15:8], via1_acr_shift_mode, cpuDataIn[12:10]);
			if (via1_sr_wr)
				$display("[ADB %0t] SRW %02x (mode=%b)", $time, cpuDataIn[15:8], via1_acr_shift_mode);
			if (via1_sr_rd)
				$display("[ADB %0t] SRR (mode=%b timer=%0d pend=%b)", $time,
				         via1_acr_shift_mode, via1_shift_timer, adb_resp_pending);
			if (via1_sr_ext_complete)
				$display("[ADB %0t] COMPLETE dir=%b load=%b data=%02x fresh_was=%b timer_was=%0d",
				         $time, via1_shift_dir, via1_sr_ext_load, via1_sr_ext_data,
				         via1_kbd_to_mac_fresh, via1_shift_timer);
			if (adb_din_strobe)
				$display("[ADB %0t] DIN  %02x (transceiver st=%b)", $time, adb_din, {ADBST1, ADBST0});
			if (adb_dout_strobe)
				$display("[ADB %0t] DOUT %02x (transceiver)", $time, adb_dout);
		end
	end
`endif

endmodule

// NOTE: The rest of the file remains unchanged - this is just the critical fix
// to move the parameter definition to the module header where it belongs.
// The parameter SCSI_DEVS is now properly defined BEFORE it's used in the port list.
