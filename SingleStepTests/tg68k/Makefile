V       = verilator
TOP     = --top-module tg68k_tests
RTL     = ../../rtl

SIM_INC = ../../verilator/sim
V_INC   = +incdir+$(RTL) +incdir+$(RTL)/tg68k

V_DEFINE = +define+SIMULATION=1 \
           -CFLAGS "-I.. -I$(SIM_INC) -g" \
           --timescale-override 1ps/1ps \
           -Wno-TIMESCALEMOD -Wno-fatal \
           -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-IMPLICIT \
           -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT \
           -Wno-CASEINCOMPLETE -Wno-UNSIGNED -Wno-CMPCONST \
           -Wno-LATCH -Wno-UNDRIVEN -Wno-MISINDENT -Wno-COMBDLY \
           -Wno-INITIALDLY -Wno-SYNCASYNCNET -Wno-ALWNEVER

# Per CLAUDE.md: verilator uses the ghdl-generated .v sources + the SV pkg.
V_SRC = \
  tg68k_tests.v \
  $(RTL)/tg68k/TG68K_Pack.sv \
  $(RTL)/tg68k/TG68K_ALU.v \
  $(RTL)/tg68k/TG68KdotC_Kernel.v

C_SRC = sim_main.cpp \
        $(SIM_INC)/m68kdasm.c \
        $(SIM_INC)/m68k_dasm_stubs.cpp

V_OPT = --x-assign fast --x-initial fast --noassert
EXE   = ./obj_dir/Vtg68k_tests
VOUT  = obj_dir/Vtg68k_tests.cpp

# 68k SingleStepTests corpus — auto-cloned on first build. Large (~190 MB
# checkout + ~190 MB .git); gitignored at the repo root. NOT touched by
# `make clean`. Use `make distclean` if you really want to drop it.
TESTDATA_DIR  = 680x0
TESTDATA_REPO = https://github.com/SingleStepTests/680x0.git

all: $(TESTDATA_DIR) $(EXE)

$(TESTDATA_DIR):
	@echo "Test corpus '$(TESTDATA_DIR)' not found — cloning $(TESTDATA_REPO)."
	@echo "This is ~400 MB and will be reused across builds. Skip with"
	@echo "  make $(EXE)   (corpus not needed to build the bench itself)"
	git clone --depth=1 $(TESTDATA_REPO) $(TESTDATA_DIR)

$(VOUT): $(V_SRC) Makefile
	$V -cc $(V_OPT) -exe --Mdir ./obj_dir $(V_DEFINE) $(V_INC) $(TOP) \
	   $(V_SRC) $(C_SRC)

$(EXE): $(VOUT) $(C_SRC)
	cd obj_dir && $(MAKE) -f Vtg68k_tests.mk OBJCACHE=

run: $(TESTDATA_DIR) $(EXE)
	./test.sh

clean:
	rm -rf obj_dir

# Wipes the corpus too. Separate target so a routine `clean` never costs
# you a 400 MB re-download.
distclean: clean
	rm -rf $(TESTDATA_DIR)

.PHONY: all run clean distclean
