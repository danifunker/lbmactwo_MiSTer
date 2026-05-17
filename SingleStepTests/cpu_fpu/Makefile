V       = verilator
TOP     = --top-module cpu_fpu_tests
RTL     = ../../rtl

SIM_INC = ../../verilator/sim
V_INC   = +incdir+$(RTL) +incdir+$(RTL)/tg68k +incdir+$(RTL)/mc68881

V_DEFINE = +define+SIMULATION=1 \
           -CFLAGS "-I.. -I$(SIM_INC) -g" \
           --timescale-override 1ps/1ps \
           -Wno-TIMESCALEMOD -Wno-fatal \
           -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-IMPLICIT \
           -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT \
           -Wno-CASEINCOMPLETE -Wno-UNSIGNED -Wno-CMPCONST \
           -Wno-LATCH -Wno-UNDRIVEN -Wno-MISINDENT -Wno-COMBDLY \
           -Wno-INITIALDLY -Wno-SYNCASYNCNET -Wno-ALWNEVER \
           -Wno-PROCASSWIRE -Wno-BLKANDNBLK -Wno-MULTIDRIVEN

# TG68K from ghdl-generated .v + SV pkg, plus fpu_lite Verilog FPU.
V_SRC = \
  cpu_fpu_tests.v \
  $(RTL)/tg68k/TG68K_Pack.sv \
  $(RTL)/tg68k/TG68K_ALU.v \
  $(RTL)/tg68k/TG68KdotC_Kernel.v \
  $(RTL)/tg68k/tg68k.v \
  $(RTL)/mc68881/fpu_lite/mc68881_top.v

C_SRC = sim_main.cpp \
        $(SIM_INC)/m68kdasm.c \
        $(SIM_INC)/m68k_dasm_stubs.cpp

V_OPT = --x-assign fast --x-initial fast --noassert
EXE   = ./obj_dir/Vcpu_fpu_tests
VOUT  = obj_dir/Vcpu_fpu_tests.cpp

all: $(EXE)

$(VOUT): $(V_SRC) Makefile
	$V -cc $(V_OPT) -exe --Mdir ./obj_dir $(V_DEFINE) $(V_INC) $(TOP) \
	   $(V_SRC) $(C_SRC)

$(EXE): $(VOUT) $(C_SRC)
	cd obj_dir && $(MAKE) -f Vcpu_fpu_tests.mk OBJCACHE=

run: $(EXE)
	$(EXE)

clean:
	rm -rf obj_dir

.PHONY: all run clean
