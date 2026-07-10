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
//          4 = { 31'b0, frozen }    5 = raw leak-condition count
//        IF-fetch ring + illegal/F-line fault capture (for raw_leaks=0 crashes):
//          6..9 = ring PCs[0..3]   10/11 = ring words[0,1]/[2,3]
//          12 = {vec[7:4], head[2:1], frozen[0]} ; NEWEST ring word = faulting opcode
//        Free-running EXCEPTION-VECTOR recorder (last-wins; IDs the fatal vector):
//          13 = last_vec_addr (cpuAddr of the most recent FC=5 vector-table read,
//               <0x100 => VBR=0; offset 0x08=bus 0x0C=addr 0x10=illegal 0x2C=F-line)
//          14 = last_vec_pc (last completed IF addr at that vector fetch = faulting PC)
//          15 = {16'b0, vec_seen_count} saturating count of vector-table reads
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

	input  wire [15:0] cpu_din,         // CPU read-data bus (opcode capture for the init-entry detector)
	input  wire [31:0] fpu_dbg_cir_state,

	// ---- happy-mac-reboot differential inputs (2026-07-03; port of the
	//      MacLCii PRC0/PRT1-3 + PSCW deck — docs/jtag_probes.md and
	//      docs/handoff_cold_boot_reboot_2026-06-15.md in that repo) ----
	input  wire [31:0] dbg_ncr2,        // ncr5380 dbg bus; [15:8] = scsi_rst assertion count
	input  wire [31:0] pscw,            // scsi.v bus-reset window snapshot (dbg_wrstall)
	input  wire        cpuReset_n,      // to rule a hardware reset in/out (PRST-lite)

	// ---- coherency detector inputs (2026-06-13) ----
	input  wire        rd_latch,        // sdram_slot_cpu_rd && memoryLatch (RAW latch gate; pre-fix condition)
	input  wire        cpu_rd_take,     // the COHERENCY-FIX accept gate (addr-match || bounded timeout)
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

	// ---- live "last instruction-fetch address" (~ PC) — simplified, no ring ----
	// Latch cpuAddr on each instruction-fetch bus cycle (AS-falling, prog space).
	// LIVE: keys off cpuAS/cpuFC, NOT the SDRAM slot handshake — so it reads
	// reliably while the Mac is frozen (the removed slot-gated IF-ring did not).
	reg [31:0] last_if_addr = 32'd0;
	wire if_event = cpuAS_n_d && !cpuAS_n && cpuRW &&
	                (cpuFC == 3'b010 || cpuFC == 3'b110);
	always @(posedge clk) if (if_event) last_if_addr <= cpuAddr;

	// ---- PRGR : FREE-RUNNING fault-vector recorder (last-wins; IDs the fault) ---
	// Trimmed 2026-06-16 to fit DBG_WEDGE alongside the SCSI ring + write-DTACK gate
	// (full dbg_wedge overflowed by 6 LABs). Dropped the SDRAM-slot-gated coherency
	// detector + 4-deep IF-ring (both runtime-blind at turbo per prior sessions; the
	// module's rd_latch/cpu_rd_take/cpu_rd_addr/dout_addr/rd_word inputs are now
	// simply unread). Kept the LIVE recorder: on any FC=5 read of a processor-fault
	// vector (offset 0x08..0x2C, skipping 0x28 = A-line dispatcher) latch the vector
	// offset + faulting PC and bump a count. At a Sad Mac / error this holds the
	// FATAL vector (0x08=bus 0x0C=addr 0x10=illegal 0x2C=F-line) + PC. Count 0 => no
	// processor-fault vector taken this run (or VBR!=0). All inputs are
	// cpuAS/cpuFC/cpuAddr (live), so it reads correctly while frozen.
	reg [31:0] last_vec_addr  = 32'd0;
	reg [31:0] last_vec_pc    = 32'd0;
	reg [15:0] vec_seen_count = 16'd0;
	wire vec_fault_read = cpuAS_n_d && !cpuAS_n && cpuRW && (cpuFC == 3'b101) &&
	                      (cpuAddr >= 32'h00000008) && (cpuAddr <= 32'h0000002C) &&
	                      (cpuAddr != 32'h00000028);
	always @(posedge clk) begin
		if (vec_fault_read) begin
			last_vec_addr <= cpuAddr;
			last_vec_pc   <= last_if_addr;
			if (vec_seen_count != 16'hFFFF) vec_seen_count <= vec_seen_count + 16'd1;
		end
	end

	// ---- happy-mac-reboot differential (2026-07-03, port of MacLCii PRC0/PRT) ----
	// The reboot has NO hardware signature there (no _cpuReset/RESET/BERR); the
	// working diagnosis method was: (1) count SCSI bus resets — a good boot does
	// exactly ONE (SCSI Manager init), a miss does a SECOND (driver abort) and
	// freeze the two most recent IF PCs at that 2nd reset = the abort caller;
	// (2) count ROM init entries address-independently by detecting the opcode
	// pair `move.w #$2700,sr` ($46FC,$2700) in the fetch stream (cold boot = 2
	// on this ROM per the LCII baseline; +1 when the reboot re-runs init), and
	// keep the latest entry PC. cpu_din is captured DURING the fetch cycle
	// (while AS is low) and committed at the AS rising edge, so bus-turnaround
	// timing can't corrupt the opcode pipeline.
	reg        if_wait   = 1'b0;
	reg [15:0] if_word   = 16'd0;
	reg [15:0] op_prev   = 16'd0;
	reg [23:0] pc_prev   = 24'd0;
	reg [7:0]  sr2700_cnt = 8'd0;
	reg [23:0] sr_entry   = 24'd0;
	reg [7:0]  rstc_d = 8'd0, busrst_cnt = 8'd0;
	reg        trail_frozen = 1'b0;
	reg [23:0] trail_pc1 = 24'd0, trail_pc2 = 24'd0;
	reg [15:0] cpu_reset_falls = 16'd0;
	reg        cpuReset_n_d = 1'b1;
	wire fetch_cplt = if_wait && !cpuAS_n_d && cpuAS_n;   // IF cycle just ended
	always @(posedge clk) begin
		// arm on IF start, sample data while AS low, commit at AS rise
		if (if_event) if_wait <= 1'b1;
		if (if_wait && !cpuAS_n) if_word <= cpu_din;
		if (fetch_cplt) begin
			if_wait <= 1'b0;
			if (op_prev == 16'h46FC && if_word == 16'h2700) begin
				if (sr2700_cnt != 8'hFF) sr2700_cnt <= sr2700_cnt + 8'd1;
				sr_entry <= pc_prev;      // PC of the $46FC = the init entry
			end
			op_prev <= if_word;
			pc_prev <= last_if_addr[23:0];
		end
		// SCSI bus-reset PC trail: freeze at the SECOND reset
		rstc_d <= dbg_ncr2[15:8];
		if (dbg_ncr2[15:8] != rstc_d) begin
			if (busrst_cnt != 8'hFF) busrst_cnt <= busrst_cnt + 8'd1;
			if (busrst_cnt >= 8'd1 && !trail_frozen) begin
				trail_frozen <= 1'b1;
				trail_pc1 <= last_if_addr[23:0];
				trail_pc2 <= pc_prev;
			end
		end
		// PRST-lite: any hardware reset assertions? (LCII proved 0 on their box)
		cpuReset_n_d <= cpuReset_n;
		if (cpuReset_n_d && !cpuReset_n && cpu_reset_falls != 16'hFFFF)
			cpu_reset_falls <= cpu_reset_falls + 16'd1;
	end

	// PRGR readout mux: JTAG source[3:0] selects the field.
	//  0 = PRC0 {busrst_cnt[31:24], sr2700_cnt[23:16], 15'b0, trail_frozen[0]}
	//  1 = PRT1 trail_pc1 (IF PC at the 2nd SCSI bus reset — the abort caller)
	//  2 = PRT2 trail_pc2 (the fetch before it)
	//  3 = PRT3 sr_entry  (latest `move #$2700,sr` init-entry PC)
	//  4 = PSCW target-side bus-reset window snapshot (scsi.v layout)
	//  5 = PRST {16'b0, cpu_reset_falls}
	//  13/14/15 = fault-vector recorder (unchanged)
	// NOTE for readers: write the source index as HEX to quartus_stp
	// (write_source_data parses hex) — decimal 13 becomes 0x13 and reads the
	// default arm (the 2026-07-02 post-mortems hit exactly that).
	wire [3:0] prgr_source;
	reg [31:0] prgr_r = 0;
	always @(posedge clk) begin
		case (prgr_source)
			4'd0:  prgr_r <= {busrst_cnt, sr2700_cnt, 15'd0, trail_frozen};
			4'd1:  prgr_r <= {8'd0, trail_pc1};
			4'd2:  prgr_r <= {8'd0, trail_pc2};
			4'd3:  prgr_r <= {8'd0, sr_entry};
			4'd4:  prgr_r <= pscw;
			4'd5:  prgr_r <= {16'd0, cpu_reset_falls};
			4'd13: prgr_r <= last_vec_addr;              // most-recent fault-vector offset
			4'd14: prgr_r <= last_vec_pc;                // faulting PC (last IF at that vector fetch)
			4'd15: prgr_r <= {16'h0000, vec_seen_count}; // count of fault-vector reads (0 => none/VBR!=0)
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

	// Dedicated single-purpose instances for the fields the PRGR source-mux
	// serves unreliably on hardware (2026-07-10: sources 2/3/13/14/15 alias to
	// source 0's value in every JTAG session, fresh or stale — synthesis prunes
	// or aliases those mux arms; PRGR srcs 0/1/4/5 and the PADR-style dedicated
	// instances have never misbehaved). Probe-only: no source port, so the
	// whole source-write failure class is out of the picture.
	altsource_probe #(.instance_id ("PVEC"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pvec (.probe(last_vec_addr), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PVPC"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pvpc (.probe(last_vec_pc), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PVCN"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pvcn (.probe({16'd0, vec_seen_count}), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PTR2"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_ptr2 (.probe({8'd0, trail_pc2}), .source(), .source_clk(clk), .source_ena(1'b1));
`endif

endmodule
