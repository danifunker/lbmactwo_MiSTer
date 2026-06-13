// dbg_wedge — focused early-boot/runtime CPU-wedge probe (5 instances).
//
// Trimmed 2026-06-13 from 8 probes to 5 for representative timing: the 8-probe
// build closed at -2.981ns (vs -1.118 probe-free), which amplified the very
// read-path fetch corruption we're measuring. This focused set targets the
// CONFIRMED fault: instruction-fetch corruption -> CPU runaway (NOT the FPU,
// which sits idle through every hang we've captured).
//
//   PADR : cpuAddr snapshot          — where the CPU is (PC / stuck loop)
//   PSTA : packed bus/decoder state  — FC, selFPU/RAM/ROM/NuBus, AS/DTACK/DSACK
//   PACT : _cpuAS falling-edge count — runaway (racing) vs clean halt (static)
//   PFLO : {last F-line opcode, cnt} — phantom-F-line / corrupted-fetch words
//   PFST : fpu_dbg_cir_state         — proves the FPU is idle/uninvolved
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
	input  wire        mac_dout_valid,  // cpu_sdram_rd_done (read-data-valid)

	input  wire [15:0] cpu_din,         // cpu_data_in (fetched word on reads)
	input  wire [31:0] fpu_dbg_cir_state
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

	// ---- PFLO : F-line opcode + count (verbatim from dbg_min) --------------
	// Trigger: IF cycle (cpuFC=2 or 6) AND mac_dout_valid AND cpu_din[15:12]=F.
	wire pflo_if_event = cpuAS_n_d && !cpuAS_n && cpuRW &&
	                     (cpuFC == 3'b010 || cpuFC == 3'b110);
	reg        pflo_pending      = 1'b0;
	reg [31:0] pflo_pending_addr = 0;
	reg [15:0] pflo_last_opcode  = 0;
	reg [15:0] pflo_cnt          = 0;
	always @(posedge clk) begin
		if (pflo_if_event) begin
			pflo_pending      <= 1'b1;
			pflo_pending_addr <= cpuAddr;
		end
		if (pflo_pending && mac_dout_valid) begin
			if (cpu_din[15:12] == 4'hF) begin
				pflo_last_opcode <= cpu_din;
				pflo_cnt         <= pflo_cnt + 16'd1;
			end
			pflo_pending <= 1'b0;
		end
		if (pflo_pending && !cpuAS_n_d && cpuAS_n) // AS rising w/o data valid -> abort
			pflo_pending <= 1'b0;
	end

	reg [31:0] pflo_r = 0;
	reg [31:0] pfst_r = 0;
	always @(posedge clk) begin
		pflo_r <= {pflo_last_opcode, pflo_cnt};
		pfst_r <= fpu_dbg_cir_state;
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

	altsource_probe #(.instance_id ("PFLO"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pflo (.probe(pflo_r), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PFST"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pfst (.probe(pfst_r), .source(), .source_clk(clk), .source_ena(1'b1));
`endif

endmodule
