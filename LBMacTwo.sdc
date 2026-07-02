# LBMacTwo core timing constraints (referenced from files.qip).
#
# KNOWN RESIDUAL (deliberately NOT constrained): cir_operand_staging ->
# operand_reg (~ -11 ns unconstrained, the fp80_from_single/double conversion
# at operand-transfer completion). bus_frame_proc captures operand_reg on the
# NEXT edge after the last staging write, so this may be a genuine
# single-cycle path — multicycling it without proof risks corrupting FMOVE
# operand loads (the exact failure mode that sank build c8e8c9ad). Leaving it
# violating makes it the fitter's top real priority. Proper fix if it ever
# bites: an RTL pipeline beat in bus_frame_proc, validated by the FPU corpus.
#
# === FPU (mc68881_top) datapath multicycle ===
#
# The mc68881 arithmetic/conversion datapath has combinational cones far
# longer than one clk_sys period (the fp80_to_int_trunc float->int cone alone
# is ~206 ns against the 31.9 ns clock; STA reported -173 ns setup slack /
# restricted Fmax 4.87 MHz on EVERY build of this core to date). The design
# works anyway because the FPU FSM leaves many cycles between the moment a
# source register settles and the moment a result/staging register's value is
# actually consumed:
#
#   - cir_operand_staging reloads EVERY cycle while the dialog FSM sits in
#     CIR_XFER_DST (mc68881_top.vhd, "Fill operand staging" process); the CPU
#     reads it several bus cycles (>= dozens of clk_sys) later.
#   - fp_reg_file_reg writes (ALU `valid` commit) are separated from the next
#     conversion read by a full CIR command dialog (CPU-paced, >> 7 cycles).
#
# Without constraints the fitter treats these as 1-cycle paths: it can't close
# them, reports "Timing requirements not met", and every rebuild re-rolls
# which marginal placement the cone gets — the documented build-to-build
# "FPU timing lottery" (docs/handoff_fpu_timing_closure_2026-06-10.md, memory
# project_macsbug_fpu_context: builds 66ba190f/a164163f wedge the FPU bench
# with stray F-line vec-11; a164163f killed System 7.1.2 boot).
#
# -setup 7 (7 x 31.9 ns = 223 ns > 206 ns worst cone) with the matching
# -hold 6 keeps hold checks at the launch edge per Intel convention.
#
# === Scope discipline (learned the hard way) ===
#
# LAUNCH (-from) set: ONLY registers proven stable >= N cycles before any
# consumer's capture edge — the FP register file (stable for a full CPU-paced
# dialog between commit and next use) and the conversion-engine intermediate
# registers (synthesis loci of in-process variables: fp80_to_int_trunc~N,
# Equal~N, Shift*~N, Add*~N, LessThan~N, Mux*~N — these engines iterate in
# held states and their outputs are consumed via staging that reloads every
# cycle).
#
# DO NOT widen -from to *|u_fpu|* : that relaxes ALU-internal registers ->
# result_* captures, which are `valid`-gated SINGLE-SHOT loads (the data cone
# must settle within the cycle `valid` pulses). Build c8e8c9ad carried that
# over-wide scope and died at boot with sad Mac 0F/0003 (illegal instruction)
# when the ROM's FPU self-probe read skewed results.
#
# CAPTURE (-to) set excludes ALL handshake bits: result_ready_reg and
# exc_event_valid_reg are single-cycle set/clear flags whose skew against
# their data registers corrupts the dialog (data-not-ready reads). CIR dialog
# registers (cir_state_reg, cir_response*, bus handshake) are likewise never
# relaxed.
#
# operand_reg is EXCLUDED from the -setup 7 launch set: the cir_move_pending
# FMOVE path copies operand_reg(1) -> result_*/fp_reg_file_reg exactly ONE
# cycle after bus_frame_proc writes it ("CIR FMOVE deferred copy") — a
# genuine single-cycle path (plain 80-bit copy, trivially fast unconstrained).
# operand_reg gets only the scoped -setup 2 into conversion intermediates
# further below.

# Launchers come in two name classes:
#  - SOURCE-NAMED (rebuild-stable): the FP register file and the decoded-
#    command state (move_cfg/cir idx/fmt/op-sel, FPctl regs) — written at
#    command decode or ALU commit, consumed a full CPU-paced dialog later.
#    A fresh synthesis keeps these names; rely on them.
#  - OPERATOR-LOCI (rebuild-FRAGILE): conversion-engine intermediates named
#    after expression sites (fp80_to_int_trunc~N, Equal~N, Shift*~N, ...).
#    A re-synthesis can rename these (seen 2026-06-12: a fresh map surfaced
#    move_cfg_decoded_reg.src_idx -> result_ex_reg at -109 ns because the
#    name-list was incomplete). Keep the patterns — they cost only an
#    "ignored filter" warning when unmatched — but CHECK THE STA REPORT
#    after every build; a new >|−30| ns cone usually means a renamed locus
#    to add here.
set fpu_dp_from [get_registers {
    *|mc68881_top:u_fpu|fp_reg_file_reg*
    *|mc68881_top:u_fpu|move_cfg*
    *|mc68881_top:u_fpu|cir_dst_reg_idx*
    *|mc68881_top:u_fpu|cir_src_fmt*
    *|mc68881_top:u_fpu|launch_dst_reg_idx*
    *|mc68881_top:u_fpu|last_op_sel*
    *|mc68881_top:u_fpu|fpcr_reg*
    *|mc68881_top:u_fpu|fpsr_reg*
    *|mc68881_top:u_fpu|fpiar_reg*
    *|mc68881_top:u_fpu|fp80_to_int_trunc*
    *|mc68881_top:u_fpu|Equal*
    *|mc68881_top:u_fpu|Shift*
    *|mc68881_top:u_fpu|Add*
    *|mc68881_top:u_fpu|LessThan*
    *|mc68881_top:u_fpu|Mux*
}]
set fpu_dp_to [remove_from_collection [get_registers {
    *|mc68881_top:u_fpu|result_*
    *|mc68881_top:u_fpu|aux_result_*
    *|mc68881_top:u_fpu|cir_operand_staging*
    *|mc68881_top:u_fpu|fp_reg_file_reg*
    *|mc68881_top:u_fpu|packed_*
    *|mc68881_top:u_fpu|move_packed_*
    *|mc68881_top:u_fpu|move_exc_*
}] [get_registers {*|mc68881_top:u_fpu|result_ready_reg*}]]
# move_packed_* / move_exc_* (2026-06-13): rounds 2/3 staged the inline
# FMOVE-FPn→mem .S/.D/.P conversions into dedicated single-driver regs to lift
# the worst-setup cones off exc_event_*/the move dispatch. Their fan-in is the
# same fp80_from_single/double + fp80_to_packed96_fast conversion that the inline
# path (which terminated at the SDC-covered packed_result_*/result_*) carried —
# launched from the SAME stable fp_reg_file_reg/cir_dst_reg_idx sources already in
# $fpu_dp_from, consumed only when a CPU-paced FMOVE issues. Without this the
# round-3 move_packed_encode_reg cone is analysed single-cycle (-177 ns). Honest
# CPU-paced multicycle, same lever as packed_result_*; do NOT relax handshakes.

set_multicycle_path -setup 7 -from $fpu_dp_from -to $fpu_dp_to
set_multicycle_path -hold  6 -from $fpu_dp_from -to $fpu_dp_to

# operand_hi16_reg (sign+exponent word of an extended/packed operand) has a
# single consumer: the cpGEN dispatch's packed-decimal path (packed_word :=
# operand_hi16_reg & operand_reg, mc68881_top.vhd ~2961) and the conversion
# cone hanging off it. It is written by the FIRST long of the CIR operand
# transfer and consumed at dispatch — two-plus full CPU bus cycles
# (>= 12 clk_sys) later.
set_multicycle_path -setup 2 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_hi16_reg*}]
set_multicycle_path -hold 1 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_hi16_reg*}]

# cir_operand_staging -> cir_conv_src_reg: the round-1 pipeline-beat operand
# conversion (fp80_from_int/single/double/extended/packed). This is the ONLY
# clean reg->reg failing-setup cone in the FPU (-10.9 ns slow corner); the other
# failing cones (move_packed_encode/move_exc_*/conv_fp_src) are an entangled
# combinational converter cloud terminating at SDC-covered move_* registers.
#
# PROVEN >= 2-cycle window (traced 2026-06-14, mc68881_top.vhd cir_dialog_proc):
#   CIR_XFER_SRC finalizes cir_operand_staging on the last operand word (it is
#   written ONLY in state CIR_XFER_SRC, line ~4070, so it cannot change after) ->
#   CIR_XFER_SRC_WAIT pulses cir_conv_start -> cir_conv_src_reg is captured on the
#   WAIT->WAIT2 edge (bus_frame_proc line ~2209), launch->capture spans the WAIT
#   hold state(s). cir_launch_alu then shallow-copies cir_conv_src_reg into
#   operand_reg one edge later. cir_conv_src_reg has EXACTLY ONE driver (this
#   conversion) and the -to is scoped to it alone, so this relaxes only the
#   conversion cone -- never a result_*/handshake/FPctl path. This is the RTL
#   pipeline beat the KNOWN RESIDUAL note at the top of this file anticipated;
#   the FSM already provides the cycles, the SDC just never told STA.
set_multicycle_path -setup 2 \
    -from [get_registers {*|mc68881_top:u_fpu|cir_operand_staging*}] \
    -to   [get_registers {*|mc68881_top:u_fpu|cir_conv_src_reg*}]
set_multicycle_path -hold 1 \
    -from [get_registers {*|mc68881_top:u_fpu|cir_operand_staging*}] \
    -to   [get_registers {*|mc68881_top:u_fpu|cir_conv_src_reg*}]

# divrem post-divide pipeline beat (2026-06-15, with enable_divrem_g): the
# ST_POST_DIV cone quot_reg -> post_mant_ext_reg (a ~115-bit leading-one encode +
# OR-prefix scan + barrel-shift + gradual-underflow, ~37 ns) was single-cycle and
# failed setup by -5.456 ns -> a wrong FDIV quotient mantissa on silicon -> Finder
# hard-lock on app launch (ideal-timing Verilator hid it). mc68881_divrem_unit now
# inserts ST_POST_DIV_PRE so quot_reg is held stable for TWO cycles before
# post_mant_ext_reg captures (quot_reg is final at the ST_DIV_ITER exit and is
# untouched in PRE/POST_DIV -- a PROVEN window). post_mant_ext_reg has exactly one
# driver and the -to is scoped to it, so only this conversion cone is relaxed.
set_multicycle_path -setup 2 \
    -from [get_registers {*|mc68881_divrem_unit:*|quot_reg*}] \
    -to   [get_registers {*|mc68881_divrem_unit:*|post_mant_ext_reg*}]
set_multicycle_path -hold 1 \
    -from [get_registers {*|mc68881_divrem_unit:*|quot_reg*}] \
    -to   [get_registers {*|mc68881_divrem_unit:*|post_mant_ext_reg*}]

# operand_reg / CPU-side bus sources -> the conversion-engine intermediate
# registers. These engines (FINT/FINTRZ, packed encode/decode) capture their
# first pipeline variables at dispatch or later — multiple cycles after the
# final operand-CIR write; CPU bus writes are AS-scoped stable >= 4 clk_sys
# before the accept edge. Endpoint scope deliberately EXCLUDES result_* /
# fp_reg_file_reg so the single-cycle cir_move deferred-copy stays tight.
# fpu_wr_hi (the emu-level first-beat latch of the 2-beat Operand-CIR write
# adapter, LBMacTwo.sv) is the same bus-paced class as operand_reg: latched on
# the first 16-bit write, consumed no earlier than the second write's accept
# edge, a full CPU bus cycle (>= 4 clk_sys) later. 2026-07-01 census: its
# arcs into the conversion loci were the only ones in this class left out.
set_multicycle_path -setup 2 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_reg* *|tg68k:tg68k_inst|* *|fpu_wr_hi[*]}] \
    -to   [get_registers {*|mc68881_top:u_fpu|fp80_to_int_trunc* *|mc68881_top:u_fpu|Equal* *|mc68881_top:u_fpu|Shift* *|mc68881_top:u_fpu|Add* *|mc68881_top:u_fpu|LessThan* *|mc68881_top:u_fpu|Mux*}]
set_multicycle_path -hold 1 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_reg* *|tg68k:tg68k_inst|* *|fpu_wr_hi[*]}] \
    -to   [get_registers {*|mc68881_top:u_fpu|fp80_to_int_trunc* *|mc68881_top:u_fpu|Equal* *|mc68881_top:u_fpu|Shift* *|mc68881_top:u_fpu|Add* *|mc68881_top:u_fpu|LessThan* *|mc68881_top:u_fpu|Mux*}]

# Exception-classification operand staging: exc_event data registers capture
# regfile / operand-derived values at dispatch (sources stable >= 2 cycles by
# CPU pacing). DATA registers only — exc_event_valid_reg is a strict
# single-cycle handshake and is deliberately NOT relaxed. Launch scope is the
# same stable-source set as above (NOT u_fpu|*, so dispatch-enable cones from
# CIR dialog registers stay single-cycle).
set exc_data_to [remove_from_collection \
    [get_registers {*|mc68881_top:u_fpu|exc_event_*}] \
    [get_registers {*|mc68881_top:u_fpu|exc_event_valid_reg*}]]
set exc_data_from [get_registers {
    *|mc68881_top:u_fpu|fp_reg_file_reg*
    *|mc68881_top:u_fpu|operand_reg*
    *|mc68881_top:u_fpu|fp80_to_int_trunc*
    *|mc68881_top:u_fpu|Equal*
    *|mc68881_top:u_fpu|Shift*
    *|mc68881_top:u_fpu|Add*
    *|mc68881_top:u_fpu|LessThan*
    *|mc68881_top:u_fpu|Mux*
    *|tg68k:tg68k_inst|*
    *|fpu_wr_hi[*]
}]
set_multicycle_path -setup 2 -from $exc_data_from -to $exc_data_to
set_multicycle_path -hold 1  -from $exc_data_from -to $exc_data_to

# === 2026-07-01 census follow-up (see scratch/sta_census_jun16db.log) ===
#
# The Jun-16 build's full failing-endpoint census (55 endpoints, WNS -112.6)
# split into: two REAL cones fixed in RTL (the packed encode/decode integer
# dividers in mc68881_top.vhd and the divrem ST_SQRT_POST single-cycle round,
# both rewritten 2026-07-01), plus three paced false-positive classes that the
# rules below describe honestly. Scope discipline from the file header still
# applies: no handshakes (result_ready_reg, exc_event_valid_reg,
# cir_response*, cir_state*), no ALU-valid single-shot commits (fpsr_reg,
# alu result_reg), and operand_reg -> result_*/fp_reg_file stays single-cycle
# (the cir_move deferred copy).

# --- FPU bus-write capture registers ---
#
# fpu_wr_hi (LBMacTwo.sv ~:782) is the first 16-bit beat of the 2-beat
# Operand-CIR write adapter; it is consumed when the SECOND beat's bus write
# is accepted, a full CPU-paced write later (>= 4 clk_sys stable). TG68-side
# launches (regfile through the data_write mux) are AS-scoped stable >= 4
# clk_sys before any FPU accept edge (same argument as the operand_reg rule
# above). Endpoints are pure bus-capture data registers: command decode
# products (micro_total/micro_remaining: total_cycles from the command word),
# FMOVEM shadow, FMOVE control staging, and the CPU-written result staging
# (result_lo/hi/ex/ex_hi captured from operand-CIR writes). The -from list is
# CPU-side ONLY so ALU `valid`-gated single-shot loads and the operand_reg
# deferred copy keep their single-cycle checks (the c8e8c9ad lesson).
set fpu_buscap_from [get_registers {
    *|tg68k:tg68k_inst|*
    *|fpu_wr_hi[*]
}]
set fpu_buscap_to [get_registers {
    *|mc68881_top:u_fpu|micro_total_reg*
    *|mc68881_top:u_fpu|micro_remaining_reg*
    *|mc68881_top:u_fpu|fp_movem_shadow_reg*
    *|mc68881_top:u_fpu|ctrl_move_data_reg*
    *|mc68881_top:u_fpu|ctrl_move_sel_reg*
    *|mc68881_top:u_fpu|result_lo_reg*
    *|mc68881_top:u_fpu|result_hi_reg*
    *|mc68881_top:u_fpu|result_ex_reg*
    *|mc68881_top:u_fpu|result_ex_hi_reg*
    *|mc68881_top:u_fpu|conv_fp_src*
}]
set_multicycle_path -setup 2 -from $fpu_buscap_from -to $fpu_buscap_to
set_multicycle_path -hold 1  -from $fpu_buscap_from -to $fpu_buscap_to

# --- Decoded-command registers -> conversion-engine loci ---
#
# The SOURCE-NAMED decode registers (move_cfg*, cir_dst_reg_idx, cir_src_fmt,
# launch_dst_reg_idx, last_op_sel, FPctl regs -- the rebuild-stable half of
# $fpu_dp_from) are written at command decode and stable for the whole
# CPU-paced dialog; the conversion loci (fp80_to_int_trunc~N, Equal~N, ...)
# recompute every cycle. The -setup 7 rule relaxes decode-reg arcs into the
# deep $fpu_dp_to endpoints but the loci-as-endpoints were only reachable
# from operand_reg/tg68k (rule above): census 2026-07-01 surfaced
# move_cfg_decoded_reg.mem_fmt -> fp80_to_int_trunc/Equal178 at -7.5 once the
# other launches were described. Deliberately NOT loci->loci: the engines
# iterate in held states, those arcs are genuinely single-cycle.
# cir_command_reg/cir_instr_type are the same class: latched at the command
# CIR write accept; the conversion engines step under their own FSM enables
# no earlier than dispatch (>= 2 edges after the latch: accept -> decode ->
# launch). micro_*/result staging captured AT the dispatch edge itself stay
# deliberately un-relaxed (see the buscap rule's endpoint list).
set fpu_decode_from [get_registers {
    *|mc68881_top:u_fpu|move_cfg*
    *|mc68881_top:u_fpu|cir_dst_reg_idx*
    *|mc68881_top:u_fpu|cir_src_fmt*
    *|mc68881_top:u_fpu|launch_dst_reg_idx*
    *|mc68881_top:u_fpu|last_op_sel*
    *|mc68881_top:u_fpu|fpcr_reg*
    *|mc68881_top:u_fpu|fpsr_reg*
    *|mc68881_top:u_fpu|fpiar_reg*
    *|mc68881_top:u_fpu|cir_command_reg*
    *|mc68881_top:u_fpu|cir_instr_type*
}]
set fpu_conv_loci [get_registers {
    *|mc68881_top:u_fpu|fp80_to_int_trunc*
    *|mc68881_top:u_fpu|Equal*
    *|mc68881_top:u_fpu|Shift*
    *|mc68881_top:u_fpu|Add*
    *|mc68881_top:u_fpu|LessThan*
    *|mc68881_top:u_fpu|Mux*
}]
set_multicycle_path -setup 2 -from $fpu_decode_from -to $fpu_conv_loci
set_multicycle_path -hold 1  -from $fpu_decode_from -to $fpu_conv_loci

# --- FMOVE-to-mem flush-through staging, state-bit/operand launches ---
#
# The move_exc_* / move_packed_encode_reg / cir_operand_staging registers
# recompute EVERY edge from conv_fp_src (mc68881_top.vhd alu_control_proc
# head, ~:2889) and are consumed only at a CPU-paced dispatch or CPU read, at
# minimum one full bus access (>= 4 clk_sys) after cir_state_reg enters/leaves
# CIR_XFER_DST (the conv_fp_src mux select) or after the last operand-CIR
# write. A capture on the first edge after a select/operand change may be
# stale; the register re-captures settled data on the next edge, long before
# any consumer reads it. The fp_reg_file-side launches of these same
# endpoints are already covered by the -setup 7 rule above; this adds only
# the state-bit and operand-side launch arcs (census: move_exc_double_rt_pre
# -18.0 from CIR_XFER_DST, move_exc_double_ovfl -15.0 from operand_reg,
# cir_operand_staging -3.8). conv_fp_src* catches the fitter-materialized
# duplicates of these staging registers (conv_fp_src[N]~M_OTERM in the
# census) on BOTH sides: as endpoints (they recapture the mux every cycle)
# and as launches into the downstream staging (synthesis merged the
# fp_reg_file write-bypass into them, so tg68k-side write data reaches them
# too -- same AS-scoped >= 4 clk_sys stability as every bus-write arc).
set fpu_stage_from [get_registers {
    *|mc68881_top:u_fpu|cir_state_reg.CIR_XFER_DST
    *|mc68881_top:u_fpu|operand_reg*
    *|mc68881_top:u_fpu|operand_hi16_reg*
    *|mc68881_top:u_fpu|conv_fp_src*
    *|tg68k:tg68k_inst|*
}]
set fpu_stage_to [get_registers {
    *|mc68881_top:u_fpu|move_exc_*
    *|mc68881_top:u_fpu|move_packed_encode_reg*
    *|mc68881_top:u_fpu|cir_operand_staging*
    *|mc68881_top:u_fpu|conv_fp_src*
}]
set_multicycle_path -setup 2 -from $fpu_stage_from -to $fpu_stage_to
set_multicycle_path -hold 1  -from $fpu_stage_from -to $fpu_stage_to

# === TG68 kernel clock-enable multicycle ===
#
# The CPU kernel steps ONLY on its clock-enable edges: tg68k.v:46 gates
# clkena_in = phi1 AND (slot ready OR internal cycle); phi1 = clk16_en_p =
# !busPhase[0] (addrController_top.v:82), a strict every-other-clk_sys
# enable, so two consecutive enabled edges are impossible (status_turbo is
# constant 1 and only selects clk16 vs clk8 -- both alternating-or-slower).
# Every register process in TG68KdotC_Kernel.vhd and TG68K_ALU.vhd is gated
# by clkena_in or clkena_lw (= clkena_in AND memmaskmux(3) AND !halted, a
# SUBSET of clkena_in edges) -- audited process-by-process 2026-07-01; the
# only ungated register is use_VBR_Stackframe, a static config decode.
# Kernel-internal reg->reg paths therefore have a TRUE budget of >= 2
# clk_sys; the 1-cycle STA check has false-failed on every build of this
# core (census: regfile->regfile -7.5 x520, data_write_tmp -10.3, ALU Flags
# -7.1, memaddr_delta/memmask/RDindex/oddout -2..-7.5).
#
# Scope: kernel-internal ONLY. Both -from and -to are inside
# TG68KdotC_Kernel (the pattern also matches the TG68K_ALU child), so paths
# from kernel registers to raw-clk consumers outside the kernel (SDRAM
# arbiter, FPU bus captures, dbg probes) keep single-cycle checks, and the
# FPU-bound arcs are governed by the scoped FPU rules above instead.
set tg68_kernel_regs [get_registers {*|TG68KdotC_Kernel:tg68k|*}]
set_multicycle_path -setup 2 -from $tg68_kernel_regs -to $tg68_kernel_regs
set_multicycle_path -hold 1  -from $tg68_kernel_regs -to $tg68_kernel_regs

# === SCSI read-data register (scsi_din_reg) — fit-independent CSR read ===
#
# Port of MacLC 0c8844b Layer 2 (2026-07-02). scsi_din_reg
# (dataController_top.sv, next to the CPU read mux) registers the ncr5380
# rdata cone one clk_sys before the CPU-side mux; its deepest input is the
# CSR BSY bit (scsi.v phase reg -> |target_bsy -> CSR -> rdata), historically
# THE fit-sensitive net behind the intermittent BSY=0 misread -> SCSI Manager
# abort -> bus reset class. The register reloads EVERY cycle and the CPU
# consumes it only at the tg68_din_r latch, >= 8 clk_sys after AS/select
# settle (immediate-DTACK PIO and DREQ-gated pseudo-DMA alike), and a status
# read does not advance the SCSI protocol -- so the cone INTO the register
# genuinely has >= 2 cycles (flush-through, same pattern as the FPU staging
# rules above). Crediting 2x here stops STA over-constraining the deep BSY
# cone to one period (the "STA passes but HW fails" trap on marginal fits).
# The register's fan-OUT (mux -> tg68_din_r) stays single-cycle.
set_multicycle_path -setup -end 2 -to [get_keepers {*|scsi_din_reg[*]}]
set_multicycle_path -hold  -end 1 -to [get_keepers {*|scsi_din_reg[*]}]
