module dataController_top  #(parameter SCSI_DEVS = 2)(
	// clocks:
	input clk32,					// 32.5 MHz pixel clock
	input clk8_en_p,
	input clk8_en_n,
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
	output [15:0] cpuDataOut,

	// peripherals:
	input selectSCSI,
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

	// misc
	output memoryOverlayOn,
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
	input                   sd_buff_wr
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
	wire [7:0] scsiDataOut;
	wire [7:0] ascDataOut;
	wire asc_irq_n;
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
	assign cpuDataOut = selectASC ? { ascDataOut, 8'hEF } :
							  selectIWM ? iwmDataOut :
							  selectVIA ? viaDataOut :
							  selectVIA2 ? via2DataOut :
							  selectNuBus ? nubusDataIn :
							  selectSCC ? { sccDataOut, 8'hEF } :
							  selectSCSI ? { scsiDataOut, 8'hEF } :
							  (cpuBusControl && memoryLatch) ? memoryDataIn : cpu_data;

	// Memory-side
	assign memoryDataOut = cpuDataIn;

	// SCSI
	ncr5380 #(SCSI_DEVS) scsi(
		.clk(clk32),
		.reset(!_cpuReset),
		.bus_cs(selectSCSI),
		.bus_rs(cpuAddrRegMid),
		.ior(!_cpuUDS),
		.iow(!_cpuLDS),
		.dack(cpuAddrRegHi[0]),   // A9
		.wdata(cpuDataIn[15:8]),
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
		.sd_buff_wr(sd_buff_wr)
	);

	// ASC (Apple Sound Chip)
	asc asc_inst(
		.clk        (clk32),
		.reset      (!_cpuReset),
		.addr       (cpuAddrASC),
		.data_in    (cpuDataIn[15:8]),
		.data_out   (ascDataOut),
		.cs         (selectASC),
		.rw         (_cpuRW),
		.ds         (!_cpuUDS),
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
	// Bits [2:0] = model sense, bit 6 = model6 sense
	// Directly from Snow emulator via1_a_in() per model:
	//   Mac Plus/SE:      0x7F (all pulled high)
	//   Mac II:           0x01 (model=1, model6=0)
	//   Mac II FDHD:      0x01 (model=1, model6=0, different ROM handles SWIM)
	//   Mac IIx:          0x00 (model=0, model6=0)
	//   Mac IIcx/SE30:    0x43 (model=3, model6=1)
	reg [6:0] via_pa_ext;
	always @(*) begin
		case (macModel)
			3'd0, 3'd1:  via_pa_ext = 7'h7F; // Mac Plus, SE: all pulled high
			3'd2, 3'd3:  via_pa_ext = 7'h03; // Mac II, Mac II FDHD: model=1, bit1=1 (no dongle)
			3'd4:         via_pa_ext = 7'h00; // Mac IIx: model=0
			3'd5, 3'd6:  via_pa_ext = 7'h43; // Mac IIcx, SE/30: model=3, model6=1
			default:      via_pa_ext = 7'h7F;
		endcase
	end
	// For output bits (oe=1): read back the output value
	// For input bits (oe=0): read the external hardware value
	assign via_pa_i = {sccWReq, (via_pa_oe[6:0] & via_pa_o[6:0]) | (~via_pa_oe[6:0] & via_pa_ext)};
	assign driveSel = machineType ? ~via_pa_oe[4] | via_pa_o[4] : 1'b1;
	// Mac II uses VIA PA4 for overlay (same as Mac Plus, NOT Mac SE's SEOverlay)
	assign memoryOverlayOn = ~via_pa_oe[4] | via_pa_o[4];
	assign SEL = ~via_pa_oe[5] | via_pa_o[5];
	assign vid_alt = ~via_pa_oe[6] | via_pa_o[6];

	//port B
	assign via_pb_i = {1'b1, {3{machineType}} | {_hblank, mouseY2, mouseX2}, machineType ? _ADBint : mouseButton, 2'b11, rtcdat_o};

	// VIA2 PB7 output chains to VIA1 CA1 (60.15 Hz timer → 1-second interrupt)
	wire via2_pb7_to_via1_ca1;
	wire via1_ca1 = machineType ? via2_pb7_to_via1_ca1 : _vblank;

	assign viaDataOut[7:0] = 8'hEF;

	via6522 via(
		.clock      (clk32),
		.rising     (E_rising),
		.falling    (E_falling),
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
		.ca2_i      (onesec),

		.cb1_i      (kbdclk),
		.cb2_i      (cb2_i),
		.cb2_o      (cb2_o),
		.cb2_t      (cb2_t),

		.irq        (viaIrq)
	);

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
	assign via2_pa_i = {(via2_pa_oe[7] ? via2_pa_o[7] : ram_size_via[1]),
	                    (via2_pa_oe[6] ? via2_pa_o[6] : ram_size_via[0]),
	                    (via2_pa_o[5] & via2_pa_oe[5]) | (nubus_irq_n & ~via2_pa_oe[5]),
	                    5'b11111};

	// VIA2 Port B: hardwired Mac II value
	// PB7 is output (timer chain to VIA1 CA1), PB[6:0] = 0x4F
	wire [7:0] via2_pb_i = 8'hCF;

	// VIA2 PB7 drives VIA1 CA1 for 60.15 Hz timer chain
	assign via2_pb7_to_via1_ca1 = via2_pb_o[7];

	// VIA2 CA1: NuBus IRQ aggregator (active-low when any slot asserts IRQ)
	wire via2_ca1 = nubus_irq_n;  // directly from video card for now (Phase 1)

	assign via2DataOut[7:0] = 8'hEF;

	via6522 via2(
		.clock      (clk32),
		.rising     (E_rising),
		.falling    (E_falling),
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

		.irq        (via2Irq)
	);

	wire _rtccs   = ~via_pb_oe[2] | via_pb_o[2];
	wire rtcck    = ~via_pb_oe[1] | via_pb_o[1];
	wire rtcdat_i = ~via_pb_oe[0] | via_pb_o[0];
	wire rtcdat_o;

	rtc pram (
		.clk        (clk32),
		.reset      (!_cpuReset),
		.timestamp  (timestamp),
		._cs        (_rtccs),
		.ck         (rtcck),
		.dat_i      (rtcdat_i),
		.dat_o      (rtcdat_o)
	);

	wire _ADBint;
	wire ADBST0 = ~via_pb_oe[4] | via_pb_o[4];
	wire ADBST1 = ~via_pb_oe[5] | via_pb_o[5];
	wire ADBListen;

	reg kbdclk;
	reg [10:0] kbdclk_count;
	reg kbd_transmitting, kbd_wait_receiving, kbd_receiving;
	reg [2:0] kbd_bitcnt;

	wire cb2_i = kbddata_o;
	wire cb2_o, cb2_t;
	wire kbddat_i = ~cb2_t | cb2_o;
	reg kbddata_o;
	reg  [7:0] kbd_to_mac;
	reg kbd_data_valid;

	// Keyboard transmitter-receiver
	always @(posedge clk32) begin
		if (clk8_en_p) begin
			if ((kbd_transmitting && !kbd_wait_receiving) || kbd_receiving) begin
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
		if (!_cpuReset) begin
			kbd_bitcnt <= 0;
			kbd_transmitting <= 0;
			kbd_wait_receiving <= 0;
			kbd_data_valid <= 0;
			ADBListenD <= 0;
		end else if (clk8_en_p) begin
			if (kbd_in_strobe && !machineType) begin
				kbd_to_mac <= kbd_in_data;
				kbd_data_valid <= 1;
			end

			if (adb_dout_strobe && machineType) begin
				kbd_to_mac <= adb_dout;
				kbd_receiving <= 1;
			end

			kbd_out_strobe <= 0;
			adb_din_strobe <= 0;
			kbdclk_d <= kbdclk;

			// Only the Macintosh can initiate communication over the keyboard lines. On
			// power-up of either the Macintosh or the keyboard, the Macintosh is in
			// charge, and the external device is passive. The Macintosh signals that it's
			// ready to begin communication by pulling the keyboard data line low.
			if (!machineType && !kbd_transmitting && !kbd_receiving && !kbddat_i) begin
				kbd_transmitting <= 1;
				kbd_bitcnt <= 0;
			end

			// ADB transmission start
			if (machineType && !kbd_transmitting && !kbd_receiving) begin
				ADBListenD <= ADBListen;
				if (!ADBListenD && ADBListen) begin
					kbd_transmitting <= 1;
					kbd_bitcnt <= 0;
				end
			end

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

	// IWM
	iwm i(
		.clk(clk32),
		.cep(clk8_en_p),
		.cen(clk8_en_n),
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
		.ps2_key(ps2_key)
	);

endmodule

// NOTE: The rest of the file remains unchanged - this is just the critical fix
// to move the parameter definition to the module header where it belongs.
// The parameter SCSI_DEVS is now properly defined BEFORE it's used in the port list.
