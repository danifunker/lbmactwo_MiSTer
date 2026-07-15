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
	input  wire [15:0] cpu_dout,        // CPU write-data bus (driver-region write snoop, 2026-07-13c)
	input  wire        hmmu_act,        // hmmu_active: 1 = 24-bit mapping engaged (2026-07-15 v3)
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
	input  wire [15:0] scsi_hs,         // full dbg_scsi live handshake word (2026-07-12l):
	                                    // {out_en,sel,bsy,target_bsy[1:0],mounted[1:0],
	                                    //  icr_adata, bus_data[7:0]}
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
	input  wire [31:0] xorr0A,          // v3.17 target0 delivered-data XOR ring [1],[0]
	input  wire [31:0] xorr0B,          // v3.17 target0 delivered-data XOR ring [3],[2]
	input  wire [31:0] selfail0,        // v3.16 target0 selection-failure tally
	input  wire [31:0] via2_irq_state,  // via6522 dbg_irq_state: {irq_out, IER[6:0],
	                                    //  0, IFR_eff[6:0], PCR[7:0], ACR[7:0]} (PVIA)
	// ---- ADB/VIA1-SR stall probes (2026-07-11: System-startup ADB wait) ----
	input  wire [31:0] adb_state,       // dataController dbg_adb: [31:29]=acr_shift_mode
	                                    //  [28]=shift_dir [27]=sr_active [26]=sr_out_done
	                                    //  [25]=sr_out_ack [24]=sr_out_pending [23:16]=sr_shadow
	                                    //  [15:0]=adb FSM {_int,dout_stb,din_stb,listen,
	                                    //  cmd_processed,cmd_valid,st[1:0],cmd_byte[7:0]}
	input  wire [17:0] adb_timer,       // dbg_adb2: [17:1]=via1_shift_timer [0]=sr_ext_complete
	input  wire [31:0] adb_rd_ring,     // dbg_adb3: last 4 bytes CPU READ from VIA1 SR
	input  wire [31:0] adb_ld_ring,     // dbg_adb4: last 4 bytes LOADED into VIA1 SR
	input  wire        cpuReset_n,      // to rule a hardware reset in/out (PRST-lite)
	// ---- reset-cause snapshot (2026-07-11e: Happy-Mac->clean-restart) ----
	// Live core-reset source terms; bit sense = the raw signal, so an ACTIVE
	// cause reads: sys_locked=0 (PLL unlock), pram_ready=0, clear_done=0,
	// pram_force_reset=1, RESET=1, buttons1=1, osd_reset_req=1.
	input  wire [6:0]  reset_src,       // {sys_locked,pram_ready,clear_done,
	                                    //  pram_force_reset,RESET,buttons1,osd_reset_req}
	// ---- SDRAM coherency timeout-escape counters (2026-07-12: PESC) ----
	input  wire [15:0] rd_escapes,      // read timeout-escapes (latched wrong word)
	input  wire [15:0] wr_escapes,      // write timeout-escapes (forced done, no owned slot)
	input  wire        berr_inhibit,    // TG68 berr_inhibit_active (68020 bus-error rerun)

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

	// ---- FATAL-FAULT PC catcher (2026-07-11f) --------------------------------
	// The Sad Mac face is CONSISTENTLY 0F/0A = an A-line (vector 10 / offset
	// 0x28) exception, which the recorder above deliberately EXCLUDES (to avoid
	// counting the millions of normal Toolbox A-traps). To get the faulting PC
	// of the fatal exception (any vector), run a PARALLEL dispatch-confirmed
	// pipeline that INCLUDES 0x28, but capture (last-wins) ONLY when the handler
	// the CPU dispatches to lands in the ROM SysError / serial-monitor region
	// [0x40002E00,0x40003400] (confirmed: the Sad Mac spins there — PADR
	// 0x3210/0x3296, 0x3284->bra 0x2edc). A normal A-trap dispatches to the Trap
	// Dispatcher, never into that region, so this is immune to Toolbox traffic
	// and names exactly the fault that produced the Sad Mac.
	//   fault_pc in valid System/ROM code (that Snow also runs) => the OPCODE was
	//     corrupted in RAM = SDRAM read/fetch-path corruption.
	//   fault_pc garbage / mid-instruction => a bad branch target = control-flow
	//     / write-path (pointer) corruption.
	// ---- GENUINE-EXCEPTION reboot-cause catcher (2026-07-12, user steer) ------
	// The soft reboot at Happy Mac = the CPU executes fetched garbage -> a REAL
	// exception -> SysError/restart -> ROM re-runs (this is a SOFT reboot: no
	// _cpuReset, cpu_reset_falls stays 1). Prior catchers FALSE-FIRED on a
	// vector-through jmp (movea.l $vec,a0; jmp (a0) = an FC=5 vector READ with
	// NO stack-frame push), which is why 0x447E was ambiguous. A GENUINE
	// exception PUSHES a frame first (FC=5 WRITES to the SSP) THEN reads the
	// vector. Gate on that. Keep a 2-deep ring of the last genuine exceptions
	// and FREEZE it at the reboot (the restart's ROM SCSI busrst edge, or the
	// 3rd move #$2700,SR) so it holds the fault that CAUSED the reboot.
	// gx_v low byte = 68k vector offset: 0x08 bus-err / 0x0C addr-err /
	// 0x10 illegal / 0x20 privilege (a garbage move-to-SR faults here!) /
	// 0x28 line-A / 0x2C line-F.
	// v2 (2026-07-12): SUPERVISOR (not FC==5 exactly) on both legs — the
	// 07-12 Sad Mac 0F/0003 boot read vec_seen_count=0 on the UNGATED legacy
	// recorder, so a genuine TG68K dispatch may drive FC=6 on the vector
	// read; the frame-push gate (not the FC value) is what kills the
	// vector-through false-fires. IACK (FC=7) still excluded.
	wire fc5_write = !cpuAS_n && !cpuRW && cpuFC[2] && (cpuFC != 3'b111);   // frame push
	wire exc_vecrd = !cpuAS_n &&  cpuRW && cpuFC[2] && (cpuFC != 3'b111) &&
	                 (cpuAddr >= 32'h00000008) && (cpuAddr <= 32'h0000002E);
	reg [4:0]  push_win   = 5'd0;   // cycles since the last frame-push write
	reg        exc_rd_live = 1'b0;
	reg [15:0] exc_din    = 16'd0;
	reg [31:0] exc_addr_l = 32'd0;
	reg [15:0] exc_hi     = 16'd0;
	reg        exc_pending = 1'b0;
	reg        exc_genuine = 1'b0;  // this vector read had a preceding frame push
	reg [23:0] exc_handler = 24'd0;
	reg [31:0] exc_pc = 32'd0; reg [7:0] exc_v = 8'd0; reg [15:0] exc_o = 16'd0;
	reg [31:0] gx_pc = 0, gx_pc_p = 0;   // faulting PC (newest, previous)
	reg [7:0]  gx_v  = 0, gx_v_p  = 0;   // vector offset (newest, previous)
	reg [15:0] gx_op = 0, gx_op_p = 0;   // opcode at fault (newest, previous)
	reg [7:0]  gx_cnt = 0;               // # genuine exceptions post-arm
	reg        gx_frozen = 1'b0;
	reg [15:0] berr_inh_cnt = 0; reg berr_inh_d = 1'b0;
	always @(posedge clk) begin
		berr_inh_d <= berr_inhibit;
		if (berr_inhibit && !berr_inh_d && berr_inh_cnt != 16'hFFFF)
			berr_inh_cnt <= berr_inh_cnt + 16'd1;
		// frame-push detection window
		if (fc5_write) push_win <= 5'd16;
		else if (push_win != 5'd0) push_win <= push_win - 5'd1;
		// vector-read: two 16-bit halves of the handler pointer
		if (exc_vecrd) begin
			exc_rd_live <= 1'b1; exc_din <= cpu_din; exc_addr_l <= cpuAddr;
			if (push_win != 5'd0) exc_genuine <= 1'b1;   // a frame was just pushed
		end
		if (cpuAS_n && exc_rd_live) begin
			exc_rd_live <= 1'b0;
			if (!exc_addr_l[1]) exc_hi <= exc_din;        // high word of handler
			else begin
				exc_pending <= 1'b1; exc_handler <= { exc_hi[7:0], exc_din };
				exc_v <= exc_addr_l[7:0]; exc_pc <= last_if_addr; exc_o <= op_prev;
			end
		end
		// dispatch-confirmed (next IF at the handler) AND genuine (frame pushed).
		// v2 (2026-07-12): arm on the FIRST ROM init entry (sr2700_cnt>=1 —
		// fires on every boot, diskless included; the old ff_armed needed a
		// completed SCSI read and NEVER ARMED on the 07-12 diskless Sad Mac).
		// A-line (0x28) excluded from the ring entirely (normal Toolbox
		// dispatch churn). FREEZE only on a FATAL-class fault — illegal 0x10,
		// zdiv 0x14, privilege 0x20, F-line 0x2C with a non-ROM fault PC (the
		// boot FPU self-probe F-lines from ROM are benign) — so a pass-1
		// restart no longer discards the pass-2 fault (the old sr2700>=3
		// freeze threw away this morning's 0F/0003). Bus/addr errors
		// (0x08/0x0C) enter the ring as precursors but never freeze.
		if (exc_pending && if_event) begin
			exc_pending <= 1'b0;
			// exc_v records the LOW-word address of the vector read, so A-line
			// arrives as 0x2A, not 0x28 — mask [7:2] to exclude 0x28-0x2B.
			// (Measured 2026-07-12: with != 0x28 only, the ?-park idle loop's
			// normal Toolbox A-traps churned the ring at full rate — gx_cnt
			// saturated and the ring held the prefetch-shifted word after the
			// newest A-trap, e.g. 0x46C6 @ 0x447E.)
			if ((sr2700_cnt != 8'd0) && exc_genuine &&
			    (exc_v[7:2] != 6'b001010) &&
			    (cpuAddr[23:1] == exc_handler[23:1])) begin
				if (!gx_frozen) begin
					gx_v_p <= gx_v; gx_pc_p <= gx_pc; gx_op_p <= gx_op;   // shift ring
					gx_v <= exc_v; gx_pc <= exc_pc; gx_op <= exc_o;
					if ((exc_v == 8'h10) || (exc_v == 8'h14) || (exc_v == 8'h20) ||
					    ((exc_v == 8'h2C) && (exc_pc[31:20] != 12'h408)))
						gx_frozen <= 1'b1;
				end
				if (gx_cnt != 8'hFF) gx_cnt <= gx_cnt + 8'd1;   // counts even frozen
			end
			exc_genuine <= 1'b0;
		end
		// JTAG unfreeze/rearm: park PRGR source on 0xA to clear the freeze
		// (reader writes A, re-reads, writes back 0).
		if (prgr_source == 4'hA)
			gx_frozen <= 1'b0;
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

	// ---- RESET-CAUSE + post-arm fault recorder (2026-07-11e) -----------------
	// The residual failure is Happy-Mac -> clean restart -> ?-park (screenshots
	// scratch/via2fix/visual/: t14 Happy Mac, t16 bare gray, t23 ? disk). The
	// ~3.5s ADB/SCSI activity previously blamed is the RESTART's ROM re-init.
	// This block answers the mechanism: did the machine actually assert
	// cpuReset (core reset from PLL-unlock / PRAM / watchdog), or did the CPU
	// jump to ROM entry via an unhandled/handler-driven exception?
	//   cpu_reset_falls (existing): baseline 1 at power-on; >1 => a real core
	//     reset happened at the restart.
	//   pll_unlock_falls: sys_locked 1->0 edges (PLL lock loss, the lead suspect
	//     for an intermittent under-load restart).
	//   last_reset_src: the source terms snapshotted at the cpuReset falling
	//     edge (decode per the reset_src port comment).
	//   armed_vec_*: post-first-disk-read (ff_armed) LAST-wins dispatch-confirmed
	//     exception vector offset + faulting PC — excludes the ROM's benign
	//     early-boot FPU F-line self-probe, names a real System-era fault.
	reg [6:0]  reset_src_d      = 7'h7F;
	reg [7:0]  pll_unlock_falls = 8'd0;
	reg [6:0]  last_reset_src   = 7'd0;
	reg        reset_src_valid  = 1'b0;
	reg        rst_n_dd         = 1'b1;
	reg [31:0] armed_vec_addr   = 32'd0;
	reg [31:0] armed_vec_pc     = 32'd0;
	reg [7:0]  armed_vec_count  = 8'd0;
	always @(posedge clk) begin
		reset_src_d <= reset_src;
		rst_n_dd    <= cpuReset_n;
		if (reset_src_d[6] && !reset_src[6] && pll_unlock_falls != 8'hFF)
			pll_unlock_falls <= pll_unlock_falls + 8'd1;
		if (rst_n_dd && !cpuReset_n) begin
			last_reset_src  <= reset_src;   // raw terms at the reset edge
			reset_src_valid <= 1'b1;
		end
		// LAST-wins dispatch-confirmed fault, gated post-disk-arm. Mirrors the
		// vec_pending->handler-landing test used for the first-wins recorder.
		if (ff_armed && vec_pending && if_event &&
		    (cpuAddr[23:1] == vec_handler[23:1])) begin
			armed_vec_addr <= vec_pend_vec;
			armed_vec_pc   <= vec_pend_pc;
			if (armed_vec_count != 8'hFF) armed_vec_count <= armed_vec_count + 8'd1;
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

	// ---- boot-1 give-up PC trail (2026-07-12l) --------------------------------
	// The boot chain reads DDM/driver/partmap byte-perfect then stops issuing
	// SCSI commands without any exception. Freeze a 4-deep IF-PC trail ~2s after
	// the LAST read-ring change: the frozen PCs land either in the on-disk
	// driver's RAM code (naming its failing check) or the ROM's give-up path.
	// Armed by the first ring push; watchdog reloads on every ring change.
	reg [23:0] gv_pc0 = 0, gv_pc1 = 0, gv_pc2 = 0, gv_pc3 = 0;  // 0 = newest
	reg [23:0] gv_prev2 = 0, gv_prev3 = 0;                       // rolling history
	reg [31:0] gv_lbar_d = 0;
	reg [26:0] gv_wd = 0;
	reg        gv_armed = 0, gv_frozen = 0;

	// ---- call-history ring (2026-07-13) ---------------------------------------
	// The give-up PC 0x6DD8 sits inside the driver's copy loop 1B96 — but 1B96
	// has FIVE callers (185E in the partition classifier 1800, plus the "storm"
	// parse-loop sites 1BF4/1C68/1C8E/1D18). A consecutive-IF trail inside a
	// 3-instruction copy loop can never show WHICH one entered it, nor the outer
	// loop's back-edge. This ring latches the last 8 driver JSR/BSR call-site PCs
	// (bits [16:1] — lossless for driver code < 0x20000). Frozen with the give-up
	// trail (gv_frozen). Newest entry chr0 = the immediate caller of whatever the
	// CPU is executing at give-up; a repeating chr pattern = the non-terminating
	// scan (its call sequence + back-edge). Gated to the driver PC window so ROM
	// boot / memtest fetches can never seed it.
	reg [15:0] chr0=0, chr1=0, chr2=0, chr3=0, chr4=0, chr5=0, chr6=0, chr7=0;
	wire is_call_word = (if_word[15:6] == 10'b0100111010) ||  // JSR  0x4E80-0x4EBF
	                    (if_word[15:8] == 8'h61);              // BSR  0x61xx

	// ---- runaway-copy forensics v2 (2026-07-13c) -------------------------------
	// v1 (data-read ring, decoded 07-13) PROVED: copy_calls=2 / cls_calls=3 (no
	// poll storm — ONE copy invocation never terminates), the copy's source
	// marches up the STACK (0x3FFB94..9A) with stride 2 (word reads — the static
	// 1BAC is a BYTE copy 0x18DB), and the call ring held 8 jsr/bsr-pattern words
	// fetched at driver offsets whose FILE words are NOT calls (0x0AC6/0x0DF8/
	// 0x0EBE/0x1380). Both instruments agree: the driver CODE IMAGE IN RAM is
	// corrupted (delivery was xorr-proven byte-perfect and the ROM's pmBootCksum
	// re-verified the RAM image THIS boot — the driver ran — so corruption strikes
	// DURING driver execution). Two v2 probes discriminate the corruption channel:
	//  * WRITE SNOOP (FIRST-wins): after the driver starts executing (first IF
	//    in its image), capture the FIRST 2 bus-visible CPU writes into
	//    [0x522E,0x782E) as {writer PC, addr[16:1], data} + a saturating count.
	//    First-wins because the runaway copy may spray the image with thousands
	//    of downstream writes — the FIRST write is the original sin. The video
	//    arbiter port is tied off (VRAM = dedicated BRAM), so the CPU is the
	//    ONLY SDRAM writer: count=0 with corruption present ⇒ no bus write ever
	//    targeted the image ⇒ SDRAM-electrical / address-path-internal only.
	//  * COPY-ARG CAPTURE: on each copy entry (IF at 0x6DC4) latch the six
	//    stack-arg words the prologue reads (1B9E src, 1BA2 dst, 1BA6 len) —
	//    last-wins = the runaway instance. Names the garbage src/dst/len exactly:
	//    dst shows WHAT the runaway is trashing; len tells whether the stack arg
	//    itself was corrupted.
	reg        dr_live = 0;
	reg [15:0] dr_val_live = 0;
	reg [7:0]  copy_calls = 0;   // IF fetches of 1B96 entry (0x522E+0x1B96=0x6DC4)
	reg [7:0]  cls_calls  = 0;   // IF fetches of 1800 entry (0x522E+0x1800=0x6A2E)
	// write snoop
	reg        drv_exec = 0;     // driver image has begun executing
	reg        wr_live = 0;
	reg [15:0] wr_val_live = 0;
	reg [31:0] wr_addr_live = 0;
	reg [23:0] wr_pc_live = 0;
	reg [15:0] wpc0=0, wpc1=0;   // {pc_is_high, pc[15:1]} per write (flag ⇒ ROM/high PC)
	reg [15:0] wad0=0, wad1=0;   // addr[16:1] per write
	reg [15:0] wdt0=0, wdt1=0;   // data word per write
	reg [5:0]  wsn_cnt = 0;      // saturating count of post-exec driver-image writes
	// ---- v3 (2026-07-15c): the MMU-mode question -----------------------------
	// The spray writer is the card DeclROM's gray-paint (base 0xFs00_0000,
	// _SwapMMUMode(32-bit)-wrapped). Post-hmmu bus addr 0x522E for a paint at
	// 0xFE000A00+ is exactly what 24-BIT masking produces ⇒ the paint must be
	// running with hmmu_active=1 on the failing boot. Capture:
	//  * hmmu_at_hit + writer FC + FULL writer PC at the FIRST in-image write;
	//  * a 4-deep ring of hmmu_active TRANSITIONS as {is_high, pc[14:1], newval}
	//    (frozen with gv) — shows the swap sequence and any ISR flipping it back.
	reg        hmmu_d = 0;
	reg [15:0] hxr0=0, hxr1=0, hxr2=0, hxr3=0;   // [15]=pc_is_high [14:1]=pc[14:1] [0]=new hmmu_act
	reg [31:0] hit_ctx = 0;   // v4: {hmmu_at_hit, addr[31:25], writer_pc[23:0]}
	reg        hit_seen = 0;
	reg [2:0]  wr_fc_live = 0;
	always @(posedge clk) begin
		// driver-execution arm: first program fetch inside the driver image.
		// All loader writes precede this (the ROM loads + checksums, THEN jsr's).
		if (if_event && sr2700_cnt != 8'd0 &&
		    cpuAddr[23:0] >= 24'h00522E && cpuAddr[23:0] < 24'h00782E)
			drv_exec <= 1'b1;
		// data-read sampler (settle-safe commit idiom, as the $da6 watch above)
		if (!cpuAS_n && cpuRW && (cpuFC == 3'b101 || cpuFC == 3'b001)) begin
			dr_live      <= 1'b1;
			dr_val_live  <= cpu_din;
		end
		if (cpuAS_n && dr_live) begin
			dr_live <= 1'b0;
		end
		// hmmu_active transition ring (v3): {pc_is_high, pc[14:1], new value}
		hmmu_d <= hmmu_act;
		if (hmmu_act != hmmu_d && !gv_frozen && sr2700_cnt != 8'd0) begin
			hxr0 <= {(|last_if_addr[23:15]), last_if_addr[14:1], hmmu_act};
			hxr1 <= hxr0; hxr2 <= hxr1; hxr3 <= hxr2;
		end
		// CPU write sampler + driver-image snoop
		if (!cpuAS_n && !cpuRW && (cpuFC == 3'b101 || cpuFC == 3'b001)) begin
			wr_live      <= 1'b1;
			wr_val_live  <= cpu_dout;
			wr_addr_live <= cpuAddr;
			wr_pc_live   <= last_if_addr[23:0];
			wr_fc_live   <= cpuFC;
		end
		if (cpuAS_n && wr_live) begin
			wr_live <= 1'b0;
			// v6 (2026-07-15f): v5 dissolved — the 0xEA48/[0xE000,0xF800)
			// region is the ROM's LEGIT RAM-resident boot workspace (first
			// write = ptr 0x00004AE8 stored at 0xE2F4 by in-region code at
			// 0xE6EA, 24-bit, early). The remaining hard corruption evidence
			// is the alias CALL-WORDS fetched at driver CODE offsets. This
			// build watches ONE known-corrupted code word: abs 0x60EC
			// (driver+0x0EBE, file word 0x2A2B, fetched as a jsr/bsr alias).
			// NOTHING legitimately writes mid-code — any hit is the corruptor.
			// First-wins {pc,addr,data} x2 + count, true-RAM gated, armed from
			// first ROM init.
			if (!gv_frozen && sr2700_cnt != 8'd0 &&
			    wr_addr_live[31:24] == 8'h00 &&
			    wr_addr_live[23:0] >= 24'h0060EC && wr_addr_live[23:0] < 24'h0060EE) begin
				if (!hit_seen) begin
					hit_seen <= 1'b1;
					hit_ctx  <= {hmmu_act, wr_addr_live[31:25], wr_pc_live[23:0]};
				end
				if (wsn_cnt == 6'd0) begin
					wpc0 <= {(|wr_pc_live[23:16]), wr_pc_live[15:1]};
					wad0 <= wr_addr_live[16:1];
					wdt0 <= wr_val_live;
				end else if (wsn_cnt == 6'd1) begin
					wpc1 <= {(|wr_pc_live[23:16]), wr_pc_live[15:1]};
					wad1 <= wr_addr_live[16:1];
					wdt1 <= wr_val_live;
				end
				if (wsn_cnt != 6'h3F) wsn_cnt <= wsn_cnt + 6'd1;
			end
		end
		if (if_event && !gv_frozen && sr2700_cnt != 8'd0) begin
			if (cpuAddr[23:0] == 24'h006DC4 && copy_calls != 8'hFF)
				copy_calls <= copy_calls + 8'd1;
			if (cpuAddr[23:0] == 24'h006A2E && cls_calls != 8'hFF)
				cls_calls <= cls_calls + 8'd1;
		end
	end
	always @(posedge clk) begin
		gv_lbar_d <= lbar0A;
		// Gate the armer on the ROM actually running (first move #$2700,SR seen):
		// at power-up the ring's uninitialized state reads as a "change" on the
		// first cycles, arming the watchdog while the CPU is still reset-held —
		// the 2s expiry then froze four zeros long before boot (measured
		// fd18024f: armed=1 frozen=1 pc0..3=0 with the machine parked healthy).
		if (sr2700_cnt != 8'd0 && lbar0A != gv_lbar_d && lbar0A != 32'd0) begin
			gv_armed <= 1'b1;
			gv_wd    <= 27'd0;
		end else if (gv_armed && !gv_frozen) begin
			if (gv_wd == 27'd62_000_000) begin      // ~2s of clk_sys silence
				gv_frozen <= 1'b1;
				gv_pc0 <= last_if_addr[23:0];
				gv_pc1 <= pc_prev;
				gv_pc2 <= gv_prev2;
				gv_pc3 <= gv_prev3;
			end else
				gv_wd <= gv_wd + 27'd1;
		end
	end
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
			// (0x447E-specific capture retired 2026-07-12 — the reboot-cause
			// catcher above supersedes it; op_prev/pc_prev feed exc_o/exc_pc.)
			// call-history ring: push the call-site PC on any driver JSR/BSR.
			// driver image = LBA64 x19 = 0x2600 bytes @ base 0x522E => [0x522E,0x782E);
			// window [0x5000,0x7900) covers it whole with a little margin.
			if (is_call_word && !gv_frozen && sr2700_cnt != 8'd0 &&
			    last_if_addr >= 32'h00005000 && last_if_addr < 32'h00007900) begin
				chr0 <= last_if_addr[16:1];
				chr1 <= chr0; chr2 <= chr1; chr3 <= chr2;
				chr4 <= chr3; chr5 <= chr4; chr6 <= chr5; chr7 <= chr6;
			end
			op_prev <= if_word;
			gv_prev3 <= gv_prev2;
			gv_prev2 <= pc_prev;
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
			// src1/2 + srcC repurposed 2026-07-15c (were the copy-arg capture —
			// decoded: garbage regs, wandering entry): the MMU-mode probe.
			// src1/2 = hmmu_active transition ring, newest [0]; each half =
			// {pc_is_high(1), pc[14:1], new_value(1)}.
			4'd1:  prgr_r <= {hxr1, hxr0};   // hmmu transitions [1],[0]
			4'd2:  prgr_r <= {hxr3, hxr2};   // hmmu transitions [3],[2]
			// src3 = {wsn_cnt[5:0], gv_armed, gv_frozen, gv_pc0(newest IF PC)};
			// wsn_cnt = post-exec driver-image WRITE count (snoop; 0x3F = sat).
			4'd3:  prgr_r <= {wsn_cnt, gv_armed, gv_frozen, gv_pc0};
			// src4/5 + srcE/F repurposed 2026-07-13 (were the v3.8 5380 reg-write
			// ring wringA-D, already decoded 07-12p): the CALL-HISTORY ring — the
			// last 8 driver JSR/BSR call-site PCs (bits [16:1], 2 per word, chr0 =
			// newest), FROZEN with the give-up trail. Decode each 16-bit half back
			// to a driver offset via (half<<1)-0x522E. chr0 = who called the code
			// the CPU is stuck in at give-up; a repeating chr sequence = the
			// non-terminating partition scan's loop + back-edge.
			4'd4:  prgr_r <= {chr1, chr0};   // call ring: [1],[0] (0 = newest)
			4'd5:  prgr_r <= {chr3, chr2};   // call ring: [3],[2]
			// v2 catcher diagnostics (2026-07-12): arm/freeze visibility so a
			// blind instrument can never masquerade as a null result again.
			4'd6:  prgr_r <= {ff_armed, (sr2700_cnt != 8'd0), gx_frozen, 1'b0,
			                  berr_inh_cnt[11:0], gx_cnt,
			                  busrst_cnt[3:0], sr2700_cnt[3:0]};
			4'd7:  prgr_r <= {gx_op_p, gx_v_p, cls_calls}; // prev-fault op+vec; low
			                                            // byte = classifier-1800
			                                            // entry count (sat FF)
			// src8/9/11 repurposed 2026-07-13c (were the data-read ring, decoded:
			// stride-2 stack reads = corrupted-code runaway): the WRITE SNOOP —
			// FIRST 2 bus-visible CPU writes into the driver image [0x522E,0x782E)
			// AFTER the driver began executing ([0] = first = the original sin;
			// later writes only bump wsn_cnt). wpc half-word =
			// {pc_is_high(1), pc[15:1]} — flag set ⇒ writer PC ≥ 0x10000 (ROM).
			4'd8:  prgr_r <= {wpc1, wpc0};              // snoop writer PCs [2nd],[1st]
			4'd9:  prgr_r <= {wad1, wad0};              // snoop addr[16:1]  [2nd],[1st]
			4'd11: prgr_r <= {wdt1, wdt0};              // snoop data words  [2nd],[1st]
			// srcC = first masked-window write context (v4):
			// {hmmu_at_hit(1), addr[31:25](7), writer_pc[23:0]}.
			// addr[31:25]=1111000_ ⇒ the slot-0 paint at 0xF000xxxx (dropped
			// writes); =0 ⇒ a true RAM write.
			4'd12: prgr_r <= hit_ctx;
			4'hA:  prgr_r <= 32'hACACACAC;              // unfreeze parked (see gx block)
			4'd13: prgr_r <= {copy_calls, gv_pc1};       // give-up trail 1-back; top
			                                            // byte = copy-1B96 entry
			                                            // count (sat FF)
			4'd14: prgr_r <= {chr5, chr4};               // call ring: [5],[4]
			4'd15: prgr_r <= {chr7, chr6};               // call ring: [7],[6]
			default: prgr_r <= 32'hC0DE0000;
		endcase
	end

// ---- REFOCUSED PROBE DECK (2026-07-11) ----------------------------------
// The 7-build bisect arc retired 22 instances (SDC/timing, probe-race,
// ID-mismatch, data-corruption, prefetch-ring — all eliminated). This lean
// 8-probe deck keeps only what the OPEN question and a fix's validation need,
// relieving the fit on the ~99%-full device (the accumulated 30-instance deck
// pushed place&route past 11 min of fitting). Retired probes remain in git
// history (commit aaf6a38) if a specific readout is ever needed again.
//   PADR - live PC (booting vs stuck at the 0x268F2 selection wait)
//   PACT - bus-cycle counter (frozen => CPU hung)
//   PRGR - src0 {busrst_cnt, sr2700_cnt, frozen} = the PASS/FAIL signal
//          (good boot = 1 reset / 2 inits / frozen 0)
//   PWHA/PWHB - per-window target history (attempts vs dialogs)
//   PCMD/PSTS - command-opcode / status rings (confirms reads still GOOD)
//   PSFL - selection-failure reason tally (the decisive open measurement)
`ifndef SIMULATION
	altsource_probe #(.instance_id ("PADR"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_padr (.probe(cpuAddr_r), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PACT"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pact (.probe(as_cycles), .source(), .source_clk(clk), .source_ena(1'b1));

	// PRGR: source[3:0] selects the readout field; src0 = the pass/fail word.
	altsource_probe #(.instance_id ("PRGR"), .probe_width (32), .source_width(4),
		.sld_auto_instance_index ("YES")
	) cp_prgr (.probe(prgr_r), .source(prgr_source), .source_clk(clk), .source_ena(1'b1));

	// PWHA/PWHB: target0 per-window history, latched race-free in scsi.v at each
	// reset edge. winh[k] = {maxphase[2:0], read_done, sel_att_win[3:0],
	// dialogs_win[2:0]}. A: [21:11]=w1 [10:0]=w0; B: [24:22]=count, w3, w2.
	altsource_probe #(.instance_id ("PWHA"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pwha (.probe(winh0A), .source(), .source_clk(clk), .source_ena(1'b1));

	// PWHB RETIRED 2026-07-11e (SCSI window history, settled) — fit room for PRST/PVEC/PVPC.
	// altsource_probe #(.instance_id ("PWHB"), .probe_width (32), .source_width(1),
	// 	.sld_auto_instance_index ("YES")
	// ) cp_pwhb (.probe(winh0B), .source(), .source_clk(clk), .source_ena(1'b1));

	// PCMD/PSTS: target0 last-4 command opcodes / status bytes, newest in [7:0].
	altsource_probe #(.instance_id ("PCMD"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pcmd (.probe(cmdr0), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PSTS"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_psts (.probe(star0), .source(), .source_clk(clk), .source_ena(1'b1));

	// PRST/PVEC/PVPC (2026-07-11e): reset-mechanism deck. Retired PWHB/PSFL/PPH2
	// (settled SCSI-window probes) to make fit room — SCSI is exonerated
	// (delivers correct data, all reads complete; the failure is the post-
	// Happy-Mac restart). PRST decode:
	//   [31:24]=cpu_reset_falls (baseline 1; >1 => a real core reset at restart)
	//   [23:16]=pll_unlock_falls (sys_locked 1->0 edges = PLL lock loss)
	//   [15:9]=last_reset_src {sys_locked,pram_ready,clear_done,pram_force_reset,
	//          RESET,buttons1,osd_reset_req} snapshot at the reset edge
	//   [8]=reset_src_valid  [7:0]=armed_vec_count (post-arm dispatch-confirmed
	//          exceptions; >0 => a real System-era fault dispatched)
	// PVEC = armed_vec_addr (vector offset: 0x08 bus, 0x0C addr, 0x10 illegal,
	//          0x2C F-line, ...);  PVPC = armed_vec_pc (faulting PC).
	// PRST [7:0] = gx_cnt = # GENUINE (frame-pushed) exceptions post-arm.
	altsource_probe #(.instance_id ("PRST"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_prst (.probe({cpu_reset_falls[7:0], pll_unlock_falls, last_reset_src,
	                   reset_src_valid, gx_cnt}),
	           .source(), .source_clk(clk), .source_ena(1'b1));

	// PVEC/PVPC/PBPC = GENUINE-EXCEPTION reboot-cause catcher (2026-07-12), the
	// fault that triggers the Happy-Mac soft reboot. Frame-push-gated (a real
	// exception stacks a frame = FC=5 writes; a vector-through jmp does not — the
	// filter that kills the old 0x447E false-fire), frozen at the reboot.
	// PVEC = {gx_op[31:16], 0, gx_v[7:0]} = newest fault opcode + vector. Vector:
	//   0x08 bus, 0x0C addr, 0x10 illegal, 0x20 PRIVILEGE (a garbage move-to-SR
	//   faults here), 0x28 line-A, 0x2C line-F. PVPC = gx_pc = newest faulting PC.
	altsource_probe #(.instance_id ("PVEC"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pvec (.probe({gx_op, 8'h00, gx_v}), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PVPC"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pvpc (.probe(gx_pc), .source(), .source_clk(clk), .source_ena(1'b1));

	// PBPC = {gx_v_p[31:24], gx_pc_p[23:0]} = the PREVIOUS genuine exception
	// (vector + PC). Distinguishes the fatal fault from benign hardware-probe
	// bus errors that precede it (those are vec 0x08/0x0C, recovered).
	altsource_probe #(.instance_id ("PBPC"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pbpc (.probe({gx_v_p, gx_pc_p[23:0]}), .source(), .source_clk(clk), .source_ena(1'b1));

	// PESC (2026-07-12) = {berr_inh_cnt[31:16], 0, gx_cnt[7:0]}. berr_inh_cnt =
	// TG68 berr_inhibit rising edges post-arm = 68020 bus-error RERUNs (the only
	// path that can re-feed a stale word as an opcode in this core; a nonzero
	// count near the reboot implicates the berr rerun). gx_cnt = # genuine
	// exceptions. (SDRAM escapes retired — measured 0/0 twice, timeout ruled out.)
	altsource_probe #(.instance_id ("PESC"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pesc (.probe({berr_inh_cnt, 8'h00, gx_cnt}), .source(), .source_clk(clk), .source_ena(1'b1));

	// PSFL RETIRED 2026-07-11e (selection-failure tally, refuted =0) — fit room.
	// altsource_probe #(.instance_id ("PSFL"), .probe_width (32), .source_width(1),
	// 	.sld_auto_instance_index ("YES")
	// ) cp_psfl (.probe(selfail0), .source(), .source_clk(clk), .source_ena(1'b1));

	// PVIA (re-added 2026-07-11 for the o_drq_lvl fix validation): VIA2
	// interrupt machinery, live. [31]=irq_out [30:24]=IER [22:16]=IFR_eff
	// [15:8]=PCR [7:0]=ACR. With the raw-REQ CA2 rewire, IFR_eff bit 0 must
	// read 1 whenever the target holds REQ (any phase); at a livelock it
	// names the flag the driver is starving on (IER shows poll vs interrupt).
	altsource_probe #(.instance_id ("PVIA"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pvia (.probe(via2_irq_state), .source(), .source_clk(clk), .source_ena(1'b1));

	// PICR/PPH2 (2026-07-11 v2): live chip + bus + target-phase state for the
	// deaf-bus hypothesis — after the fatal READ6, does target0 return to
	// IDLE and release BSY before the driver's next selection?
	// PICR = ncr_regs: [31:24]=icr_read [23:16]=mr [15:12]=tcr [7]=rst
	//   [6]=sel [5]=bsy [4]=req_bus [3]=ack [2]=atn [1]=dma_en [0]=dreq
	// PPH2 = dbg_scsi2 (zero-extended): [13:11]=target1 phase
	//   [10:8]=target0 phase (0=IDLE) [5:4]=io_rd [3:2]=io_wr [1:0]=io_ack
	altsource_probe #(.instance_id ("PICR"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_picr (.probe(ncr_regs), .source(), .source_clk(clk), .source_ena(1'b1));

	// PPH2 RETIRED 2026-07-11e (target phase, SCSI exonerated) — fit room.
	// altsource_probe #(.instance_id ("PPH2"), .probe_width (32), .source_width(1),
	// 	.sld_auto_instance_index ("YES")
	// ) cp_pph2 (.probe({16'd0, scsi2}), .source(), .source_clk(clk), .source_ena(1'b1));

	// PADB/PAB2/PAB3/PAB4 (2026-07-11): the System-startup ADB transaction
	// stall. Burst captures prove the failing boots die in the ROM ADB-wait
	// loop (0x6DD8 spinning on ADBBase+$15D bit5) for ~3.5s with SCSI idle
	// and healthy, then fall to the ?-rescan. These name the stalled layer:
	// PADB = shim mode/dir + transceiver FSM {st, cmd_byte, cmd_valid...};
	// PAB2 = live shift timer (parked at 1 => the hold-at-1 deadlock branch);
	// PAB3/PAB4 = last 4 SR bytes read by CPU / loaded by shim.
	altsource_probe #(.instance_id ("PADB"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_padb (.probe(adb_state), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PAB2"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pab2 (.probe({14'd0, adb_timer}), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PAB3"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pab3 (.probe(adb_rd_ring), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PAB4"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pab4 (.probe(adb_ld_ring), .source(), .source_clk(clk), .source_ena(1'b1));
`endif

endmodule
