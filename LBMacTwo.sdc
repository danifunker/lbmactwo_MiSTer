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
set_multicycle_path -setup 2 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_reg* *|tg68k:tg68k_inst|*}] \
    -to   [get_registers {*|mc68881_top:u_fpu|fp80_to_int_trunc* *|mc68881_top:u_fpu|Equal* *|mc68881_top:u_fpu|Shift* *|mc68881_top:u_fpu|Add* *|mc68881_top:u_fpu|LessThan* *|mc68881_top:u_fpu|Mux*}]
set_multicycle_path -hold 1 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_reg* *|tg68k:tg68k_inst|*}] \
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
}]
set_multicycle_path -setup 2 -from $exc_data_from -to $exc_data_to
set_multicycle_path -hold 1  -from $exc_data_from -to $exc_data_to
