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
	wire vec_read_all = !cpuAS_n && cpuRW && (cpuFC == 3'b101) &&
	                    (cpuAddr >= 32'h00000008) && (cpuAddr <= 32'h0000002E);
	reg        va_rd_live = 1'b0;
	reg [15:0] va_din_live = 16'd0;
	reg [31:0] va_rd_addr_l = 32'd0;
	reg [15:0] va_hi = 16'd0;
	reg        va_pending = 1'b0;
	reg [31:0] va_pend_vec = 32'd0;
	reg [31:0] va_pend_pc  = 32'd0;
	reg [23:0] va_handler  = 24'd0;
	reg [31:0] fault_vec = 32'd0;   // vector offset of the fatal exception
	reg [31:0] fault_pc  = 32'd0;   // faulting PC (last IF before the dispatch)
	reg [7:0]  fault_cnt = 8'd0;
	always @(posedge clk) begin
		if (vec_read_all) begin
			va_rd_live   <= 1'b1;
			va_din_live  <= cpu_din;
			va_rd_addr_l <= cpuAddr;
		end
		if (cpuAS_n && va_rd_live) begin
			va_rd_live <= 1'b0;
			if (!va_rd_addr_l[1]) va_hi <= va_din_live;      // high word of handler
			else begin
				va_pending  <= 1'b1;
				va_handler  <= { va_hi[7:0], va_din_live };
				va_pend_vec <= va_rd_addr_l & 32'hFFFFFFFC;
				va_pend_pc  <= last_if_addr;
			end
		end
		if (va_pending && if_event) begin
			va_pending <= 1'b0;
			// LAST-WINS, post-arm, dispatch-confirmed (next IF lands at the
			// handler read from the vector). Rationale: the A-line vector (the
			// consistent Sad Mac 0F/0A) points at the ROM Trap Dispatcher, same
			// as every normal Toolbox A-trap, so a handler-address gate can't
			// isolate the fatal one. Instead rely on the HALT: after the fatal
			// exception the CPU enters SysError and spins in the 0x2Exx monitor,
			// which issues NO further exceptions — so the final capture before
			// the freeze IS the fatal faulting instruction. (On a healthy boot
			// A-traps keep firing, but we only read this on a stuck/Sad-Mac boot.)
			if (ff_armed && (cpuAddr[23:1] == va_handler[23:1])) begin
				fault_vec <= va_pend_vec;
				fault_pc  <= va_pend_pc;
				if (fault_cnt != 8'hFF) fault_cnt <= fault_cnt + 8'd1;
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
	altsource_probe #(.instance_id ("PRST"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	// [7:0] = fault_cnt (was armed_vec_count; that read 0 on both faces since
	// the fatal vector is A-line, excluded upstream). fault_cnt>0 => the FATAL
	// catcher fired and PVEC/PVPC hold the vector+PC.
	) cp_prst (.probe({cpu_reset_falls[7:0], pll_unlock_falls, last_reset_src,
	                   reset_src_valid, fault_cnt}),
	           .source(), .source_clk(clk), .source_ena(1'b1));

	// PVEC/PVPC repurposed 2026-07-11f to the FATAL-fault catcher (fault_vec/
	// fault_pc), which INCLUDES the A-line vector (the consistent Sad Mac 0F/0A).
	// armed_vec_addr/pc (in-range-only, A-line excluded) read 0 on both observed
	// faces, so this is strictly more informative. fault_vec low byte = the 68k
	// vector: 0x28 A-line(0F/0A), 0x10 illegal, 0x0C addr-err(0F/03), 0x2C F-line.
	altsource_probe #(.instance_id ("PVEC"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pvec (.probe(fault_vec), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(.instance_id ("PVPC"), .probe_width (32), .source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pvpc (.probe(fault_pc), .source(), .source_clk(clk), .source_ena(1'b1));

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
