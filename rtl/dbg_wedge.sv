// dbg_wedge — SDRAM read-path COHERENCY detector + CPU-state probe (5 instances).
//
// 2026-06-13 rewrite. Replaces the IF-fetch ring — which only ever froze on the
// benign DETERMINISTIC 0x0000C0Cx illegal (a red herring, byte-identical every
// boot, that masked the real fault) — with a detector that catches the residual
// read corruption AT ITS SOURCE.
//
// Mechanism: the fefc429 `cpuSlotOwned`/`cpu_data` handshake occasionally latches
// a NEIGHBOR slot's SDRAM word instead of the CPU's own (LBMacTwo.sv:903-919 +
// dataController_top.sv:216). sdram.v now tags every `dout` with the word-address
// that produced it (`dout_addr`). When the CPU latches read data (`rd_latch` =
// the exact `sdram_slot_cpu_rd && memoryLatch` gate dataController uses) but
// `dout_addr` != the address the CPU is reading (`cpu_rd_addr` = arb_mac_addr,
// combinationally stable for the whole held read cycle), the latched word came
// from the wrong transaction = the bug, caught in the act. Per-word compare is
// false-positive-safe (a 68020 longword is two separate owned word-slots, each
// matching its own address).
//
//   PADR : cpuAddr snapshot          — where the CPU is
//   PSTA : packed bus/decoder state  — FC, selects, AS/DTACK/DSACK
//   PACT : _cpuAS falling-edge count — runaway vs static
//   PFST : fpu_dbg_cir_state         — proves the FPU is idle/uninvolved
//   PRGR : COHERENCY violation latch — source[3:0] selects the readout field:
//          0 = cpu_rd_addr  (address the CPU WANTED)
//          1 = dout_addr    (address it GOT — the leak source)
//          2 = cpuAddr @ first violation (CPU bus addr / PC context)
//          3 = { bad word[31:16], 16-bit saturating violation count[15:0] }
//          4 = { 31'b0, frozen }
//
// Same instance_ids as dbg_min, so scripts/cpu_state.tcl reads it unchanged.
// Gated by DBG_WEDGE (not DBG_PROBES). Read: quartus_stp_tcl -t scripts/cpu_state.tcl

module dbg_wedge (
	input  wire        clk,             // clk_sys

	input  wire [31:0] cpuAddr,
	input  wire [2:0]  cpuFC,
	input  wire        cpuAS_n,
	input  wire        cpuRW,
	input  wire        cpuDTACK_n,
	input  wire        cpuUDS_n,
	input  wire        cpuLDS_n,

	input  wire        selectFPU,
	input  wire        selectRAM,
	input  wire        selectROM,
	input  wire        selectNuBus,
	input  wire        fpu_dsack0_n,
	input  wire        fpu_dsack1_n,
	input  wire        mac_dout_valid,  // cpu_sdram_rd_done

	input  wire [15:0] cpu_din,         // (legacy; unused by the coherency detector)
	input  wire [31:0] fpu_dbg_cir_state,

	// ---- coherency detector inputs (2026-06-13) ----
	input  wire        rd_latch,        // sdram_slot_cpu_rd && memoryLatch (the cpu_data latch gate)
	input  wire [23:0] cpu_rd_addr,     // word-addr the CPU is reading (arb_mac_addr, stable in-cycle)
	input  wire [23:0] dout_addr,       // word-addr that produced the SDRAM word being latched
	input  wire [15:0] rd_word          // the SDRAM word being latched (memoryDataIn)
);

	// ---- PADR / PSTA : coherent snapshots (verbatim from dbg_min) ----------
	reg [31:0] cpuAddr_r = 0;
	reg [31:0] sta_r = 0;
	always @(posedge clk) begin
		cpuAddr_r <= cpuAddr;
		sta_r <= {
			13'd0,
			mac_dout_valid,                 // [18]
			fpu_dsack1_n, fpu_dsack0_n,     // [17:16]
			selectNuBus, selectROM,         // [15:14]
			selectRAM, selectFPU,           // [13:12]
			cpuLDS_n, cpuUDS_n,             // [11:10]
			cpuDTACK_n, cpuRW, cpuAS_n,     // [9:7]
			cpuFC,                          // [6:4]
			4'd0
		};
	end

	// ---- PACT : free-running bus-cycle counter (frozen => CPU hung) --------
	reg        cpuAS_n_d = 1'b1;
	reg [31:0] as_cycles  = 0;
	always @(posedge clk) begin
		cpuAS_n_d <= cpuAS_n;
		if (cpuAS_n_d && !cpuAS_n)   // falling edge of _cpuAS = new bus cycle
			as_cycles <= as_cycles + 32'd1;
	end

	// ---- PFST : FPU CIR state (live) ---------------------------------------
	reg [31:0] pfst_r = 0;
	always @(posedge clk) pfst_r <= fpu_dbg_cir_state;

	// ---- PRGR : SDRAM read-path COHERENCY violation latch (2026-06-13) ------
	// A violation = the CPU latches read data whose source address (dout_addr)
	// is NOT the address its own read requested (cpu_rd_addr) => a neighbor
	// slot's word leaked into cpu_data. Freeze the FIRST one (with full context)
	// and keep a saturating count, so a post-crash read shows both the exact
	// leak and how many leaks happened this session.
	wire violation = rd_latch && (dout_addr != cpu_rd_addr);

	reg        viol_frozen      = 1'b0;
	reg [31:0] viol_cpuAddr     = 0;
	reg [23:0] viol_cpu_rd_addr = 0;
	reg [23:0] viol_dout_addr   = 0;
	reg [15:0] viol_word        = 0;
	reg [15:0] viol_count       = 0;   // saturating
	always @(posedge clk) begin
		if (violation) begin
			if (viol_count != 16'hFFFF) viol_count <= viol_count + 16'd1;
			if (!viol_frozen) begin
				viol_frozen      <= 1'b1;
				viol_cpuAddr     <= cpuAddr;
				viol_cpu_rd_addr <= cpu_rd_addr;
				viol_dout_addr   <= dout_addr;
				viol_word        <= rd_word;
			end
		end
	end

	// PRGR readout mux: JTAG source[3:0] selects the field.
	wire [3:0] prgr_source;
	reg [31:0] prgr_r = 0;
	always @(posedge clk) begin
		case (prgr_source)
			4'd0: prgr_r <= {8'h00, viol_cpu_rd_addr};   // address the CPU WANTED
			4'd1: prgr_r <= {8'h00, viol_dout_addr};     // address it GOT (leak source)
			4'd2: prgr_r <= viol_cpuAddr;                // CPU bus addr at the violation
			4'd3: prgr_r <= {viol_word, viol_count};     // bad word + saturating count
			4'd4: prgr_r <= {31'b0, viol_frozen};        // status
			default: prgr_r <= 32'hC0DE0000;
		endcase
	end

`ifndef SIMULATION
	altsource_probe #(.instance_id ("PADR"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_padr (.probe(cpuAddr_r), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PSTA"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_psta (.probe(sta_r), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PACT"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pact (.probe(as_cycles), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PFST"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pfst (.probe(pfst_r), .source(), .source_clk(clk), .source_ena(1'b1));

	// PRGR: coherency violation readout — source[3:0] selects the field.
	altsource_probe #(.instance_id ("PRGR"), .probe_width (32), .source_width(4),
		.sld_auto_instance_index ("YES")
	) cp_prgr (.probe(prgr_r), .source(prgr_source), .source_clk(clk), .source_ena(1'b1));
`endif

endmodule
