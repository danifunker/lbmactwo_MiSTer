// Integrated TG68K + mc68881_top bench. Uses the tg68k.v bus wrapper, so
// DTACK handshaking is real and the FPU's multi-cycle DSACK response is
// honored.
//
// Test program at $1000:
//   MOVEQ #1,D0
//   FMOVE.L D0,FP0          ; opword $F200 ext $8000 (R/M=1, src=L=D0, dst=FP0, op=FMOVE)
//   FMOVE.X FP0,($200).L    ; opword $F239 ext $4400 (R/M=0, FPn→EA, .X, FP0, op=FMOVE)
//   STOP #$2700
//
// Expected: RAM[$200..$20B] = 3F FF 00 00 80 00 00 00 00 00 00 00 (+1.0)
//
// PHASE 2 STATUS — BLOCKED on FPU bug. The CIR dialog goes:
//   1. CPU writes OpWord ($F200) to CIR byte $08 → ✓ FPU accepts.
//   2. CPU writes Command ($8000) to CIR byte $0A → ✓ FPU accepts.
//   3. CPU polls Response at CIR byte $00 → ✗ returns $0000 forever.
// The FPU's d_out_comb read path (mc68881_top.vhd ~line 3155) has a
// case statement keyed on the peripheral-mode ADDR_* constants. Byte $00
// maps to ADDR_OPSEL — which has NO read case, falling through to the
// default 0. The standard M68020 CIR layout puts Response at byte $00
// (matches what TG68K's CIR dispatcher writes / reads), but the FPU's
// read-side address dispatch never CIR-remaps byte $00 → cir_response_reg.
// Write side gates correctly (cir_mode_reg branches in lines 3463+), but
// the read side does not. Bug in the canonical FPU repo at
// /Users/dani/repos/68881-fpga.

#include <verilated.h>
#include "Vcpu_fpu_tests.h"
#include "Vcpu_fpu_tests__Syms.h"

#include <cstdint>
#include <iostream>
#include <iomanip>
#include <vector>
#include <string>

#define VERILATOR_MAJOR_VERSION (VERILATOR_VERSION_INTEGER / 1000000)
#if VERILATOR_MAJOR_VERSION >= 5
  #define VERTOPINTERN top->rootp
#else
  #define VERTOPINTERN top
#endif

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

static Vcpu_fpu_tests* top = nullptr;
static std::vector<uint8_t> ram;

static inline uint16_t ram_read16(uint32_t a) {
    a &= 0x00FFFFFE;
    return (uint16_t(ram[a]) << 8) | ram[a + 1];
}
static inline void ram_write16(uint32_t a, uint16_t v, bool uds, bool lds) {
    a &= 0x00FFFFFE;
    if (uds) ram[a]     = uint8_t(v >> 8);
    if (lds) ram[a + 1] = uint8_t(v & 0xFF);
}

// Service RAM on every AS=low cycle that isn't an FPU access.
static void service_ram() {
    if (top->as_n) return;
    if (top->fpu_select) return;
    const uint32_t a = top->addr_out;
    if (top->rw_n) {
        // Read
        top->data_in = ram_read16(a);
    } else {
        ram_write16(a, top->data_write, !top->uds_n, !top->lds_n);
    }
}

// One full clock cycle. phi1 / phi2 alternate within the cycle; tg68k.v
// wrapper uses them as clock enables.
static int phase = 0;
static void tick() {
    // Drive phi1 high on even ticks, phi2 high on odd ticks.
    top->phi1 = (phase == 0) ? 1 : 0;
    top->phi2 = (phase == 1) ? 1 : 0;
    top->clk = 0; top->eval();
    main_time++;
    top->clk = 1; top->eval();
    service_ram();
    main_time++;
    phase ^= 1;
}

static void finish() { top->final(); delete top; top = nullptr; }

static void plant_program() {
    ram[0x00] = 0x00; ram[0x01] = 0xFF; ram[0x02] = 0xFF; ram[0x03] = 0xF8;
    ram[0x04] = 0x00; ram[0x05] = 0x00; ram[0x06] = 0x10; ram[0x07] = 0x00;

    // MOVEQ #1,D0
    ram[0x1000] = 0x70; ram[0x1001] = 0x01;
    // FMOVE.L D0,FP0:  F200 / 8000
    ram[0x1002] = 0xF2; ram[0x1003] = 0x00;
    ram[0x1004] = 0x80; ram[0x1005] = 0x00;
    // FMOVE.X FP0,($200).L:  F239 / 4400 / 00000200
    ram[0x1006] = 0xF2; ram[0x1007] = 0x39;
    ram[0x1008] = 0x44; ram[0x1009] = 0x00;
    ram[0x100A] = 0x00; ram[0x100B] = 0x00;
    ram[0x100C] = 0x02; ram[0x100D] = 0x00;
    // STOP #$2700
    ram[0x100E] = 0x4E; ram[0x100F] = 0x72;
    ram[0x1010] = 0x27; ram[0x1011] = 0x00;
}

int main(int argc, char** argv, char** env) {
    top = new Vcpu_fpu_tests();
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    ram.assign(0x01000000, 0x00);
    plant_program();

    bool trace = (argc > 1 && std::string(argv[1]) == "--trace");

    top->reset = 1;
    top->data_in = 0;
    for (int i = 0; i < 32; ++i) tick();
    top->reset = 0;

    // Trace: edge-triggered on as_n falling edge so each bus cycle prints once.
    uint8_t prev_as = 1;
    int max_cycles = 20000;
    for (int cyc = 0; cyc < max_cycles; ++cyc) {
        tick();
        if (trace) {
            uint8_t cur_as = top->as_n;
            if (prev_as && !cur_as) {
                // AS just asserted
                std::cerr << "  cyc " << std::setw(5) << cyc
                          << " fc=" << int(top->fc)
                          << " rw=" << int(top->rw_n)
                          << " addr=0x" << std::hex << std::setw(8)
                          << std::setfill('0') << top->addr_out
                          << (top->rw_n
                                ? (" rd")
                                : (" wr"))
                          << " data=0x" << std::setw(4)
                          << (top->rw_n
                                ? (top->fpu_select
                                     ? (top->fpu_d_out_obs & 0xFFFF)
                                     : ram_read16(top->addr_out))
                                : top->data_write)
                          << std::dec << std::setfill(' ')
                          << (top->fpu_select ? " [FPU]" : "")
                          << "\n";
            }
            prev_as = cur_as;
        }
    }

    static const uint8_t expected[12] = {
        0x3F, 0xFF, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    std::cerr << "RAM[$200..$20B]:";
    for (int i = 0; i < 12; ++i)
        std::cerr << " " << std::hex << std::setw(2) << std::setfill('0')
                  << int(ram[0x200 + i]);
    std::cerr << std::dec << std::setfill(' ') << "\n";
    std::cerr << "Expected:       ";
    for (int i = 0; i < 12; ++i)
        std::cerr << " " << std::hex << std::setw(2) << std::setfill('0')
                  << int(expected[i]);
    std::cerr << std::dec << std::setfill(' ') << "\n";

    bool pass = true;
    for (int i = 0; i < 12; ++i)
        if (ram[0x200 + i] != expected[i]) { pass = false; break; }
    std::cerr << (pass ? "PASS — FPU returned 1.0\n"
                       : "FAIL — RAM contents do not match expected 1.0\n");
    finish();
    return pass ? 0 : 1;
}
