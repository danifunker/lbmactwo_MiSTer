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
	input  wire [31:0] pscw0,           // target0 dbg_wrstall, un-muxed live tap (v3)
	input  wire [15:0] scsi2,           // ncr5380 dbg_scsi2: phases + io_rd/io_wr/io_ack (v3)
	input  wire [31:0] ncr_regs,        // live 5380 {icr_read,mr,tcr,bus lines} (v3.2)
	input  wire [7:0]  rst_count,       // ncr5380 dbg_rst_count: TRUE scsi_rst edges (v3.2)
	input  wire        img_mnt0,        // hps_io img_mounted[0] strobe (v3.5)
	input  wire        img_size_zero,   // img_size == 0 at this moment (v3.5)
	input  wire        mounted0,        // scsi target0 live mounted flag, dbg_scsi[9] (v3.5)
	input  wire [7:0]  selterms0,       // target0 gate-term sampler (v3.6)
	input  wire        berr_pulse,      // top-level berr_out (8us watchdog) (v3.6)
	input  wire [31:0] wringA,          // v3.8 reg-write ring (frozen at abort)
	input  wire [31:0] wringB,
	input  wire [31:0] wringC,
	input  wire [31:0] wringD,
	input  wire [31:0] selid,           // v3.9 selection-target detective
	input  wire [31:0] winh0A,          // v3.11 target0 window history [1],[0]
	input  wire [31:0] winh0B,          // v3.11 target0 window history [3],[2]+count
	input  wire [31:0] iwh,             // v3.12 initiator per-window {sel6,selany} x4
	input  wire [31:0] cmdr0,           // v3.14 target0 last-4 command opcodes
	input  wire [31:0] star0,           // v3.14 target0 last-4 status bytes
	input  wire [31:0] lbar0A,          // v3.15 target0 read LBA ring [1],[0]
	input  wire [31:0] lbar0B,          // v3.15 target0 read LBA ring [3],[2]
	input  wire [31:0] selfail0,        // v3.16 target0 selection-failure tally
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
	// 2026-07-10 REDESIGN after two contaminated captures:
	//  - narrowed to vectors 2/3/4 (bus 0x08/0x0A, address 0x0C/0x0E, illegal
	//    0x10/0x12): the old <=0x2C range leaked the A-line dispatcher's SECOND
	//    word (0x2A — only 0x28 was excluded) = 19k+ toolbox traps/boot, and
	//    counted the NuBus slot scan's deliberate guarded bus errors, drowning
	//    any corruption signal (free-running PVCN was 10k+ on EVERY boot).
	//  - STORM-WINDOWED: captures arm only once trail_frozen sets (= the 2nd
	//    SCSI bus reset = the storm began). Clean boot => count stays 0. The
	//    addr/pc pair is FIRST-wins inside the window = the first fault after
	//    the storm began (the crime scene), not whatever faulted last.
	reg [31:0] last_vec_addr  = 32'd0;   // first vec2/3/4 fetch addr after freeze
	reg [31:0] last_vec_pc    = 32'd0;   // last completed IF at that fetch
	reg [15:0] vec_seen_count = 16'd0;   // vec2/3/4 fetches since freeze
	// v3.3 (2026-07-10, after the ss1 Sad Mac 0F/0003 capture): range widened
	// to 0x08..0x2E (bus/addr/illegal/zdiv/CHK/TRAPV/priv/trace/F-line) minus
	// the A-line dispatcher words 0x28/0x2A — the user's crash class is
	// illegal-instruction (vec 4) and the June lottery also produced F-line
	// (0x2C), which the old 0x08..0x13 filter missed. Gating changed from
	// trail_frozen (storm-only, never fires on a Sad Mac boot) to ff_armed
	// (= first boot-disk READ completed): the NuBus slot scan's deliberate
	// bus errors all happen before disk IO, so post-arm faults are real.
	// v3.6 REDESIGN — dispatch-confirmed fault recorder. Bus-level FC=5 reads
	// of the vector table are ambiguous: the ROM's guarded engines SAVE
	// vectors by reading them (move.l $8.w,... preceded by movem pushes), so
	// both the PC-page filter (v3.4) and any write-burst heuristic fail. The
	// unambiguous signature of a REAL exception dispatch: the next instruction
	// fetch lands AT the address just read out of the vector. A software save
	// never jumps there.
	// cpuAddr[31:2] != 30'hA excludes 0x28..0x2B (A-line dispatcher words).
	wire vec_read_cyc = !cpuAS_n && cpuRW && (cpuFC == 3'b101) &&
	                    (cpuAddr >= 32'h00000008) && (cpuAddr <= 32'h0000002E) &&
	                    (cpuAddr[31:2] != 30'hA);
	reg        vec_rd_live = 1'b0;
	reg [15:0] vec_din_live = 16'd0;
	reg [31:0] vec_rd_addr_l = 32'd0;
	reg [15:0] vec_hi = 16'd0;
	reg        vec_pending = 1'b0;
	reg [31:0] vec_pend_vec = 32'd0;   // vector table offset of the candidate
	reg [31:0] vec_pend_pc  = 32'd0;   // last completed IF before the read
	reg [23:0] vec_handler  = 24'd0;   // handler address read from the vector
	always @(posedge clk) begin
		// capture the vector word: sample during AS-low, commit at AS rise
		if (vec_read_cyc) begin
			vec_rd_live   <= 1'b1;
			vec_din_live  <= cpu_din;
			vec_rd_addr_l <= cpuAddr;
		end
		if (cpuAS_n && vec_rd_live) begin
			vec_rd_live <= 1'b0;
			if (!vec_rd_addr_l[1]) begin
				vec_hi <= vec_din_live;          // high word of the handler long
			end else begin
				vec_pending  <= 1'b1;            // low word: candidate complete
				vec_handler  <= { vec_hi[7:0], vec_din_live };
				vec_pend_vec <= vec_rd_addr_l & 32'hFFFFFFFC;
				vec_pend_pc  <= last_if_addr;
			end
		end
		// dispatch confirmation: the very next IF starts at the handler
		if (vec_pending && if_event) begin
			vec_pending <= 1'b0;
			if (cpuAddr[23:1] == vec_handler[23:1]) begin
				if (vec_seen_count == 16'd0) begin
					last_vec_addr <= vec_pend_vec;
					last_vec_pc   <= vec_pend_pc;
				end
				if (vec_seen_count != 16'hFFFF) vec_seen_count <= vec_seen_count + 16'd1;
			end
		end
	end

	// ---- v3 (2026-07-10): FIRST-FAILURE window + $da6 watch --------------
	// Everything captured so far described the ESTABLISHED storm; the original
	// sin — whatever kills the first transfer after boot IO starts working —
	// has never been seen. Arm after the first successful READ data phase
	// completes on target 0 (pscw0: data_complete with phase==DATA_OUT and not
	// a write), then freeze a pscw0 snapshot + event PC at the FIRST abnormal
	// event: a SCSI bus reset edge (busrst_cnt increment) or a vec2/3/4 fetch.
	// v3.3 FIX: the arm predicate previously read pscw0[19] as "data_complete"
	// per a STALE dbg_wrstall layout comment; bit 19 in the real packing is
	// brst_read_done (frozen at the first normal init reset = always 0), so
	// the window never armed and the ss1 Sad Mac 0F/0003 boot read back all
	// zeros. Real live-read-done is pscw0[7] (win_read_done).
	// ff_evpc[29:24] now records the vector offset (cpuAddr[7:2]) so the
	// fault CLASS (2=bus 3=addr 4=illegal 0xB=F-line) is in the capture.
	// v3.4: freeze ONLY on the abort reset edge (rst edges are rare and real
	// under the honest counter; the vec trigger kept getting sniped by the
	// slot walk). ff_pscw0 = transfer state at the abort (phase/data_cnt/
	// selection count name the dying op); ff_evpc = ncr_regs at the abort
	// (live ICR/MR/TCR + bus lines + dma_en/dreq = what the driver had
	// programmed when it gave up). The trail PC is useless here by design
	// (always inside SCSIReset's hold loop).
	reg        ff_armed  = 1'b0;
	reg        ff_frozen = 1'b0;
	reg [31:0] ff_pscw0  = 32'd0;
	reg [31:0] ff_evpc   = 32'd0;   // v3.4: ncr_regs snapshot at the abort edge
	reg [7:0]  ff_selterms = 8'd0;  // v3.7: gate-term sampler frozen at the edge
	reg [7:0]  busrst_cnt_d = 8'd0;
	always @(posedge clk) begin
		busrst_cnt_d <= busrst_cnt;
		if (!ff_armed && pscw0[7])
			ff_armed <= 1'b1;
		if (ff_armed && !ff_frozen && (busrst_cnt != busrst_cnt_d)) begin
			ff_frozen  <= 1'b1;
			ff_pscw0   <= pscw0;
			ff_evpc    <= ncr_regs;
			ff_selterms <= selterms0;
		end
	end

	// v3.7: scsi_rst held-duration tracker (ncr_regs[7] = live scsi_rst).
	// The deaf-window suspicion: a stale saved-ICR restore re-asserts RST and
	// holds the targets in their reset branch while the ROM retries selection.
	// rst_hold_max = longest continuous assert seen, in 256-clk units (sat FF).
	reg [15:0] rst_hold_cnt = 16'd0;
	reg [7:0]  rst_hold_max = 8'd0;
	always @(posedge clk) begin
		if (ncr_regs[7]) begin
			rst_hold_cnt <= rst_hold_cnt + 16'd1;
			if (rst_hold_cnt[15:8] > rst_hold_max) rst_hold_max <= rst_hold_cnt[15:8];
		end else
			rst_hold_cnt <= 16'd0;
	end

	// $da6 watch: the ROM's SCSI arbitration poll budget is the RAM word at
	// $0DA6 (SCSI Manager reads it move.w $da6.w before every AIP wait). If
	// the residual read-corruption returns a small/zero word here even once,
	// every retry gives up instantly = the observed storm. Latch last value
	// and running MINIMUM of every supervisor-data word read at $DA6.
	reg [15:0] da6_last = 16'hFFFF;
	reg [15:0] da6_min  = 16'hFFFF;
	reg        da6_rd_live = 1'b0;
	reg [15:0] da6_val_live = 16'd0;
	always @(posedge clk) begin
		// capture during the AS-low window (cpu_din valid), commit at AS rise
		if (!cpuAS_n && cpuRW && (cpuFC == 3'b101) && cpuAddr == 32'h00000DA6) begin
			da6_rd_live  <= 1'b1;
			da6_val_live <= cpu_din;
		end
		if (cpuAS_n && da6_rd_live) begin
			da6_rd_live <= 1'b0;
			da6_last <= da6_val_live;
			if (da6_val_live < da6_min) da6_min <= da6_val_live;
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
		// SCSI bus-reset PC trail: freeze at the SECOND reset.
		// v3.2 FIX: this previously watched dbg_ncr2[15:8], which on THIS
		// core carries the live IRQ-machine FLAGS byte (dreq/pmatch/...) —
		// it counted flag churn and saturated 255 on any boot with SCSI
		// activity, poisoning every "storm" classification. Now mirrors
		// ncr5380's dbg_rst_count = actual scsi_rst rising edges.
		rstc_d <= rst_count;
		busrst_cnt <= rst_count;
		if (rst_count != rstc_d) begin
			if (rst_count >= 8'd2 && !trail_frozen) begin
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

	// ---- v3 dedicated instances (all probe-only) ----
	// PWS0: live target-0 wrstall (layout = scsi.v dbg_wrstall:
	//   [15:0]=data_cnt [18:16]=phase [19]=data_complete [20]=io_wr [21]=io_ack
	//   [22]=io_busy [23]=sd_buff_sel [24]=cmd_write [30:25]=tlen [31]=req)
	altsource_probe #(.instance_id ("PWS0"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pws0 (.probe(pscw0), .source(), .source_clk(clk), .source_ena(1'b1));

	// PSIO: live ncr5380 io/phase bits ({16'd0, dbg_scsi2}: [15:14]=empty_cd_ph
	//   [13:11]=t1 phase [10:8]=t0 phase [7]=ecd_ph2 [6]=ecd_req
	//   [5:4]=io_rd [3:2]=io_wr [1:0]=io_ack)
	altsource_probe #(.instance_id ("PSIO"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_psio (.probe({16'd0, scsi2}), .source(), .source_clk(clk), .source_ena(1'b1));

	// PFW / PFWP: first-failure window (frozen pscw0 + event PC)
	altsource_probe #(.instance_id ("PFW"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pfw (.probe(ff_pscw0), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PFWP"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pfwp (.probe(ff_evpc), .source(), .source_clk(clk), .source_ena(1'b1));

	// v3.5/v3.6: mounted-loss detective + BERR pulse counter (PMNT layout)
	reg [3:0] mnt_pulse_cnt = 4'd0, mnt_fall_cnt = 4'd0;
	reg [7:0] berr_cnt = 8'd0;
	reg       img_mnt0_d = 1'b0, mounted0_d = 1'b0, berr_d = 1'b0;
	always @(posedge clk) begin
		img_mnt0_d <= img_mnt0;
		mounted0_d <= mounted0;
		berr_d     <= berr_pulse;
		if (img_mnt0 && !img_mnt0_d && mnt_pulse_cnt != 4'hF)
			mnt_pulse_cnt <= mnt_pulse_cnt + 4'd1;
		if (!mounted0 && mounted0_d && mnt_fall_cnt != 4'hF)
			mnt_fall_cnt <= mnt_fall_cnt + 4'd1;
		if (berr_pulse && !berr_d && berr_cnt != 8'hFF)
			berr_cnt <= berr_cnt + 8'd1;
	end

	// PDAV: {last, min} of supervisor-data word reads at $0DA6 (SCSI arb budget)
	altsource_probe #(.instance_id ("PDAV"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pdav (.probe({da6_last, da6_min}), .source(), .source_clk(clk), .source_ena(1'b1));

	// PICR: live 5380 registers + bus lines (see ncr5380 dbg_regs layout)
	altsource_probe #(.instance_id ("PICR"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_picr (.probe(ncr_regs), .source(), .source_clk(clk), .source_ena(1'b1));

	// PMNT (v3.6 layout): gate-term sampler + BERR count + mount detective.
	//   [31:24] selterms0 = {gate_fire_cnt[3:0], rst@att, busy@att, mounted@att, 0}
	//   [23:16] berr_cnt (top-level 8us watchdog pulses)
	//   [15:12] img_mounted[0] pulse count   [11:8] mounted0 fall count
	//   [1]     live mounted0   [0] live img_mnt0
	altsource_probe #(.instance_id ("PMNT"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pmnt (.probe({selterms0, berr_cnt, mnt_pulse_cnt, mnt_fall_cnt,
	                   6'd0, mounted0, img_mnt0}),
	           .source(), .source_clk(clk), .source_ena(1'b1));

	// PFWS (v3.7): the deaf-window verdict word.
	//   [31:24] selterms0 FROZEN at the abort edge (windowed: describes the
	//           deaf era itself) = {gate_fire[3:0], rst@att, busy@att, mounted@att, 0}
	//   [23:16] selterms0 live
	//   [15:8]  rst_hold_max (longest scsi_rst assert, 256-clk units)
	altsource_probe #(.instance_id ("PFWS"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pfws (.probe({ff_selterms, selterms0, rst_hold_max, 8'd0}),
	           .source(), .source_clk(clk), .source_ena(1'b1));

	// PWRA..PWRD (v3.8): 5380 register-write ring frozen at the abort reset —
	// the System driver's dying words. Entries {rs[2:0], val[7:0]} at [26:16]
	// and [10:0] per word (A=[7],[6]; B=[5],[4]; C=[3],[2]); D packs [1],[0]
	// + head/frozen/count (see ncr5380 dbg_wringD comment).
	altsource_probe #(.instance_id ("PWRA"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pwra (.probe(wringA), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PWRB"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pwrb (.probe(wringB), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PWRC"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pwrc (.probe(wringC), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PWRD"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pwrd (.probe(wringD), .source(), .source_clk(clk), .source_ena(1'b1));

	// PSID (v3.9): {frozen sel_id_or, frozen sel_id_last, live or, live last}.
	// 0x81 in the frozen OR = the System driver selected ID0 (LCII mapping);
	// 0xC0 = it selected our ID6 and the deafness needs another explanation.
	altsource_probe #(.instance_id ("PSID"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_psid (.probe(selid), .source(), .source_clk(clk), .source_ena(1'b1));

	// PWHA/PWHB (v3.11): target0 per-window history, latched race-free in
	// scsi.v at each reset edge (the wedge-side freeze reads windowed
	// accumulators 1-2 clk post-clear — B1 proved every such readout was
	// zeros). winh[k] = {maxphase[2:0], read_done, sel_lvl_seen,
	// gate_all_ever, sel_att_win[4:0]}. A: [21:11]=w1 [10:0]=w0;
	// B: [24:22]=window count, [21:11]=w3 [10:0]=w2.
	altsource_probe #(.instance_id ("PWHA"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pwha (.probe(winh0A), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PWHB"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pwhb (.probe(winh0B), .source(), .source_clk(clk), .source_ena(1'b1));

	// PIWH (v3.12): initiator per-window {sel6[3:0],selany[3:0]} x4 windows,
	// [7:0]=w0 ... [31:24]=w3. Compare w1 against PWHA's w1 target counts.
	altsource_probe #(.instance_id ("PIWH"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_piwh (.probe(iwh), .source(), .source_clk(clk), .source_ena(1'b1));

	// PCMD/PSTS (v3.14): target0 last-4 command opcodes / status bytes,
	// newest in [7:0]. Names the dialog the driver rejects after and whether
	// the target ever returned CHECK CONDITION (0x02).
	altsource_probe #(.instance_id ("PCMD"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pcmd (.probe(cmdr0), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PSTS"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_psts (.probe(star0), .source(), .source_clk(clk), .source_ena(1'b1));

	// PLBA/PLBB (v3.15): target0 read-LBA ring (low16 each), newest in [15:0]
	// of PLBA. Repeats => data rejected + retried; monotone advance => reads
	// succeed and a post-data handshake/IRQ is the reject.
	altsource_probe #(.instance_id ("PLBA"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_plba (.probe(lbar0A), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PLBB"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_plbb (.probe(lbar0B), .source(), .source_clk(clk), .source_ena(1'b1));

	// PSFL (v3.16): selection-failure reason tally, frozen at abort.
	// {attempt[31:24], blk_nonidle[23:16], blk_gate[15:8], reason_or[7:4]}.
	// blk_nonidle dominant => target lingers busy (bus-free/MESSAGE->IDLE fix).
	altsource_probe #(.instance_id ("PSFL"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_psfl (.probe(selfail0), .source(), .source_clk(clk), .source_ena(1'b1));
`endif

endmodule
