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

	input  wire [15:0] cpu_din,         // (legacy; now fully unused — IF-ring captures rd_word, not this)
	input  wire [31:0] fpu_dbg_cir_state,

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

	// ---- PRGR : SDRAM read-path COHERENCY violation latch (2026-06-13) ------
	// A violation = the CPU latches read data whose source address (dout_addr)
	// is NOT the address its own read requested (cpu_rd_addr) => a neighbor
	// slot's word leaked into cpu_data. Freeze the FIRST one (with full context)
	// and keep a saturating count, so a post-crash read shows both the exact
	// leak and how many leaks happened this session.
	wire mismatch      = (dout_addr != cpu_rd_addr);
	wire raw_violation = rd_latch && mismatch;                 // leak CONDITION (occurs even when suppressed)
	wire violation     = rd_latch && cpu_rd_take && mismatch;  // DELIVERED into cpu_data (fix target = 0)

	reg        viol_frozen      = 1'b0;
	reg [31:0] viol_cpuAddr     = 0;
	reg [23:0] viol_cpu_rd_addr = 0;
	reg [23:0] viol_dout_addr   = 0;
	reg [15:0] viol_word        = 0;
	reg [15:0] viol_count       = 0;   // saturating: DELIVERED violations (post-fix target = 0)
	reg [15:0] raw_count        = 0;   // saturating: leak conditions seen (delivered OR suppressed)
	always @(posedge clk) begin
		// Capture the FIRST raw leak — its details survive even when the fix suppresses it,
		// so we can still see the bit-22 RAM/ROM signature.
		if (raw_violation) begin
			if (raw_count != 16'hFFFF) raw_count <= raw_count + 16'd1;
			if (!viol_frozen) begin
				viol_frozen      <= 1'b1;
				viol_cpuAddr     <= cpuAddr;
				viol_cpu_rd_addr <= cpu_rd_addr;
				viol_dout_addr   <= dout_addr;
				viol_word        <= rd_word;
			end
		end
		if (violation && viol_count != 16'hFFFF) viol_count <= viol_count + 16'd1;
	end

	// ---- IF-fetch ring + exception-vector capture (2026-06-14, round 2) --------
	// Cracks the raw_leaks=0 crashes (NOT the read-address leak): record every
	// instruction fetch as {PC, opcode}, 4 deep. Two consumers:
	//
	//  (1) RING FREEZE on the illegal(0x10)/F-line(0x2C) exception VECTOR fetch
	//      (FC=5; classic Mac OS keeps VBR=0). Asymmetric region guard: illegal in
	//      ANY region (catches a fault taken during ROM execution); F-line RAM-only
	//      (keeps the benign ROM FPU self-test filtered). NEWEST ring word = the
	//      faulting opcode; compare to the disk/ROM image (garbage=corruption /
	//      real op=feature gap). Only fires for vec 4/11 — a bus/addr error (vec
	//      2/3) won't freeze, by design; the recorder below catches those.
	//
	//  (2) FREE-RUNNING VECTOR RECORDER (last-wins): on any FC=5 read of a PROCESSOR-
	//      FAULT vector (offset 0x08..0x2C, skipping 0x28 = the A-line toolbox
	//      dispatcher that fires constantly) latch {cpuAddr=vector offset, last_if_addr
	//      =faulting PC} and bump a count. Because it OVERWRITES, benign early
	//      boot-probe bus-errors get replaced by the LATEST one — so at the Sad Mac
	//      it holds the FATAL vector + PC, with no false-freeze risk. IDs the
	//      exception the freeze can't (0x08=bus 0x0C=addr 0x10=illegal 0x2C=Fline).
	//      Assumes VBR=0; if it never fires (count=0) on a fault, VBR is non-zero.
	//
	// CAPTURE-EDGE FIX (round 2): log the fetch at the rd_latch&&cpu_rd_take edge —
	// the EXACT cycle dataController latches cpu_data (cpuSlotOwned&&memoryLatch&&
	// cpu_rd_take, LBMacTwo.sv:1322 + dataController_top.sv:218), where rd_word is
	// valid. The old mac_dout_valid (cpu_sdram_rd_done) edge was a cycle too late —
	// sdram_do had moved on, so BOTH cpu_din and rd_word read 0x0000, AND fetches
	// completing off that edge were silently dropped (the ring stopped recording).
	reg [31:0] ifr_addr [0:3];
	reg [15:0] ifr_word [0:3];
	reg [1:0]  ifr_head     = 2'd0;   // next slot to write = OLDEST; head-1 = newest
	reg        ifr_frozen   = 1'b0;
	reg [3:0]  ifr_vec      = 4'd0;   // 11=F-line, 4=illegal
	reg [31:0] last_if_addr = 32'd0;
	reg        ifp_pending  = 1'b0;
	reg [31:0] ifp_addr     = 32'd0;
	// free-running processor-fault vector recorder (last-wins; IDs the fatal vector)
	reg [31:0] last_vec_addr  = 32'd0; // cpuAddr (offset) of the most recent fault-vector read
	reg [31:0] last_vec_pc    = 32'd0; // last completed IF addr at that vector fetch (faulting PC)
	reg [15:0] vec_seen_count = 16'd0; // saturating count of fault-vector reads
	wire if_event = cpuAS_n_d && !cpuAS_n && cpuRW &&        // AS-falling instruction fetch
	                (cpuFC == 3'b010 || cpuFC == 3'b110);
	wire vec_read = !cpuAS_n && cpuRW && (cpuFC == 3'b101);  // FC=5 supervisor-data read (vector fetch)
	wire vec_fault_read = cpuAS_n_d && !cpuAS_n &&           // AS-falling: once per bus cycle
	                cpuRW && (cpuFC == 3'b101) &&
	                (cpuAddr >= 32'h00000008) && (cpuAddr <= 32'h0000002C) &&
	                (cpuAddr != 32'h00000028);              // fault vectors 2-9,11 (skip A-line 10)
	always @(posedge clk) begin
		if (if_event) begin ifp_pending <= 1'b1; ifp_addr <= cpuAddr; end
		// Log the fetch at the TRUE data-delivery edge (= the cpu_data latch). rd_word
		// is valid here; mac_dout_valid was a cycle late (logged 0x0000 + dropped fetches).
		if (ifp_pending && rd_latch && cpu_rd_take) begin
			if (!ifr_frozen) begin
				ifr_addr[ifr_head] <= ifp_addr;
				ifr_word[ifr_head] <= rd_word;
				ifr_head           <= ifr_head + 2'd1;
				last_if_addr       <= ifp_addr;
			end
			ifp_pending <= 1'b0;
		end
		if (ifp_pending && !cpuAS_n_d && cpuAS_n) ifp_pending <= 1'b0;  // AS rose, no data -> abort
		// Asymmetric freeze: illegal in ANY region (catches a ROM-execution fault);
		// F-line in RAM only (filters the benign ROM FPU self-test).
		if (vec_read && !ifr_frozen) begin
			if      (cpuAddr == 32'h00000010)                                begin ifr_frozen <= 1'b1; ifr_vec <= 4'd4;  end
			else if (cpuAddr == 32'h0000002C && last_if_addr < 32'h40000000) begin ifr_frozen <= 1'b1; ifr_vec <= 4'd11; end
		end
		// Free-running recorder: the LAST fault-vector fetch wins (= the fatal one at a Sad Mac).
		if (vec_fault_read) begin
			last_vec_addr <= cpuAddr;
			last_vec_pc   <= last_if_addr;
			if (vec_seen_count != 16'hFFFF) vec_seen_count <= vec_seen_count + 16'd1;
		end
	end

	// PRGR readout mux: JTAG source[3:0] selects the field.
	wire [3:0] prgr_source;
	reg [31:0] prgr_r = 0;
	always @(posedge clk) begin
		case (prgr_source)
			4'd0: prgr_r <= {8'h00, viol_cpu_rd_addr};   // address the CPU WANTED
			4'd1: prgr_r <= {8'h00, viol_dout_addr};     // address it GOT (leak source)
			4'd2: prgr_r <= viol_cpuAddr;                // CPU bus addr at the first leak
			4'd3: prgr_r <= {viol_word, viol_count};     // bad word + DELIVERED count
			4'd4: prgr_r <= {31'b0, viol_frozen};        // status
			4'd5: prgr_r <= {16'h0000, raw_count};       // RAW leak-condition count (occurs even when fixed)
			// IF-fetch ring / illegal-F-line fault capture (4-deep {PC,word}):
			4'd6:  prgr_r <= ifr_addr[0];                // ring slot-0 PC
			4'd7:  prgr_r <= ifr_addr[1];                // ring slot-1 PC
			4'd8:  prgr_r <= ifr_addr[2];                // ring slot-2 PC
			4'd9:  prgr_r <= ifr_addr[3];                // ring slot-3 PC
			4'd10: prgr_r <= {ifr_word[0], ifr_word[1]}; // ring words 0,1
			4'd11: prgr_r <= {ifr_word[2], ifr_word[3]}; // ring words 2,3
			4'd12: prgr_r <= {24'd0, ifr_vec, 1'b0, ifr_head, ifr_frozen}; // [7:4]=vec [2:1]=head [0]=frozen
			// Free-running fault-vector recorder (last-wins; IDs the fatal vector):
			4'd13: prgr_r <= last_vec_addr;              // offset of the most recent fault-vector read
			4'd14: prgr_r <= last_vec_pc;                // faulting PC (last IF at that vector fetch)
			4'd15: prgr_r <= {16'h0000, vec_seen_count}; // count of fault-vector reads (0 => VBR!=0 or none)
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
