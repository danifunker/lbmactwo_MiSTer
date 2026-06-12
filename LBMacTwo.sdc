# LBMacTwo core timing constraints (referenced from files.qip).
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
# Scope is the FPU-internal datapath cones ONLY (register file / operand /
# conversion-locus registers -> result / staging / regfile-commit registers).
# The CIR dialog registers (cir_state_reg, cir_response*, bus handshake) are
# genuinely single-cycle against the CPU handshake and are deliberately NOT
# relaxed.

# FROM is deliberately wide (any u_fpu-internal register): the violating
# launchers are synthesis-generated loci of the conversion/normalization
# datapath (fp80_to_int_trunc~N, ShiftRight2~N, Add87~N, ...) whose mangled
# names shift between Quartus runs, so enumerating them is not robust. The
# TO list is the load-bearing safety scope: only the result / staging /
# regfile-commit registers — all of which the FSM consumes many cycles after
# their sources settle (staging reloads every cycle while CIR_XFER_DST holds;
# results are CPU-paced). CIR dialog registers are NOT in the TO list, so
# their capture timing stays single-cycle.
# operand_reg is EXCLUDED from the launch set: the cir_move_pending FMOVE path
# copies operand_reg(1) -> result_*/fp_reg_file_reg exactly ONE cycle after
# bus_frame_proc writes it (mc68881_top.vhd "CIR FMOVE deferred copy") — that
# copy is a genuine single-cycle path and must not be relaxed. (It is a plain
# 80-bit register copy, trivially fast; it needs no multicycle.)
# Residual accepted hazard: packed_* -> result_* (FBCD completion copy) is
# relaxed by this scope; if the corpus FBCD family ever regresses, carve it
# out the same way operand_reg is.
set fpu_dp_from [remove_from_collection \
    [get_registers {*|mc68881_top:u_fpu|*}] \
    [get_registers {*|mc68881_top:u_fpu|operand_reg*}]]
set fpu_dp_to [get_registers {
    *|mc68881_top:u_fpu|result_*
    *|mc68881_top:u_fpu|cir_operand_staging*
    *|mc68881_top:u_fpu|fp_reg_file_reg*
    *|mc68881_top:u_fpu|packed_*
}]

set_multicycle_path -setup 7 -from $fpu_dp_from -to $fpu_dp_to
set_multicycle_path -hold  6 -from $fpu_dp_from -to $fpu_dp_to

# operand_hi16_reg (sign+exponent word of an extended/packed operand) has a
# single consumer: the cpGEN dispatch's packed-decimal path (packed_word :=
# operand_hi16_reg & operand_reg, mc68881_top.vhd ~2961) and the conversion
# cone hanging off it. It is written by the FIRST long of the CIR operand
# transfer and consumed at dispatch — two-plus full CPU bus cycles
# (>= 12 clk_sys) later. Its conversion cone misses one period by ~10ns;
# -setup 2 closes it with margin while demanding far less stability than
# the FSM actually provides.
set_multicycle_path -setup 2 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_hi16_reg*}]
set_multicycle_path -hold 1 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_hi16_reg*}]

# operand_reg -> the conversion-engine intermediate registers (synthesis-
# named after the in-process variables' expression loci: fp80_to_int_trunc~N,
# Equal*~N). These engines (FINT/FINTRZ, packed encode/decode) capture their
# first pipeline variables at dispatch or later — multiple cycles after the
# final operand-CIR write. Endpoint scope deliberately EXCLUDES result_* /
# fp_reg_file_reg so the single-cycle cir_move deferred-copy of operand_reg
# stays tightly constrained (see operand_reg exclusion above).
set_multicycle_path -setup 2 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_reg* *|TG68KdotC_Kernel:tg68k|regfile*}] \
    -to   [get_registers {*|mc68881_top:u_fpu|fp80_to_int_trunc* *|mc68881_top:u_fpu|Equal* *|mc68881_top:u_fpu|Shift* *|mc68881_top:u_fpu|Add* *|mc68881_top:u_fpu|LessThan* *|mc68881_top:u_fpu|Mux*}]
set_multicycle_path -hold 1 \
    -from [get_registers {*|mc68881_top:u_fpu|operand_reg* *|TG68KdotC_Kernel:tg68k|regfile*}] \
    -to   [get_registers {*|mc68881_top:u_fpu|fp80_to_int_trunc* *|mc68881_top:u_fpu|Equal* *|mc68881_top:u_fpu|Shift* *|mc68881_top:u_fpu|Add* *|mc68881_top:u_fpu|LessThan* *|mc68881_top:u_fpu|Mux*}]

# Exception-classification operand staging: exc_event_{result,opa,opb}_reg
# capture regfile / conversion-cone values at dispatch (sources stable for a
# full CPU-paced dialog beforehand). DATA registers only — the
# exc_event_valid_reg handshake bit is a strict single-cycle set/clear and is
# deliberately NOT relaxed.
set_multicycle_path -setup 2 \
    -from [get_registers {*|mc68881_top:u_fpu|*}] \
    -to   [remove_from_collection \
              [get_registers {*|mc68881_top:u_fpu|exc_event_*}] \
              [get_registers {*|mc68881_top:u_fpu|exc_event_valid_reg*}]]
set_multicycle_path -hold 1 \
    -from [get_registers {*|mc68881_top:u_fpu|*}] \
    -to   [remove_from_collection \
              [get_registers {*|mc68881_top:u_fpu|exc_event_*}] \
              [get_registers {*|mc68881_top:u_fpu|exc_event_valid_reg*}]]
