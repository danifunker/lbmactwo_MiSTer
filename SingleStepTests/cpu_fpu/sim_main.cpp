// Integrated TG68K + mc68881_top bench. Uses the tg68k.v bus wrapper, so
// DTACK handshaking is real and the FPU's multi-cycle DSACK response is
// honored.
//
// Test program at $1000:
//   MOVEQ #1,D0
//   FMOVE.L D0,FP0     ; opword $F200 ext $4000 (opclass 010, src=L, dst=FP0)
//   FMOVE.L FP0,D1     ; opword $F201 ext $6000 (opclass 011, dst=L, src=FP0)
//   STOP #$2700
//
// Both encodings verified via Musashi disassembler. Pass condition: D1 == 1
// after STOP (D0 → FP0 → D1 round-trip).
//
// (Earlier B-1 hang was a bench-side bug: cpu_fpu_tests.v drove
// mc68881_top.a_in raw, omitting the CIR address remap LBMacTwo.sv applies.
// Fixed there; the FPU's CIR read path is correct.)

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
    // FMOVE.L D0,FP0:  F200 / 4000
    ram[0x1002] = 0xF2; ram[0x1003] = 0x00;
    ram[0x1004] = 0x40; ram[0x1005] = 0x00;
    // FMOVE.L FP0,D1:  F201 / 6000
    ram[0x1006] = 0xF2; ram[0x1007] = 0x01;
    ram[0x1008] = 0x60; ram[0x1009] = 0x00;
    // STOP #$2700
    ram[0x100A] = 0x4E; ram[0x100B] = 0x72;
    ram[0x100C] = 0x27; ram[0x100D] = 0x00;
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
    uint8_t prev_micro = 0xFF;
    int max_cycles = 20000;
    for (int cyc = 0; cyc < max_cycles; ++cyc) {
        tick();
        if (trace) {
            // Per-micro_state print on transitions, for debugging the FPU
            // dialog. Concise — drop to {ms, xfer_data, D1} on changes.
            uint8_t cur_micro = top->dbg_micro_state;
            if (cur_micro != prev_micro) {
                std::cerr << "    [cyc " << std::setw(5) << cyc
                          << "] ms=" << std::dec << int(cur_micro)
                          << " xfer_data=0x" << std::hex << std::setw(8)
                          << std::setfill('0') << top->dbg_cp_xfer_data
                          << " D1=0x" << std::setw(8) << top->dbg_d1
                          << std::dec << std::setfill(' ') << "\n";
                prev_micro = cur_micro;
            }
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

    // Read D0, D1 from TG68K's regfile (split [7:0] / [31:8] arrays —
    // same convention as the tg68k bench's --probe-regs path).
    auto get_reg = [](int i) -> uint32_t {
        uint32_t n1 = VERTOPINTERN->cpu_fpu_tests__DOT__cpu__DOT__tg68k__DOT__regfile_n1[i];
        uint32_t n2 = VERTOPINTERN->cpu_fpu_tests__DOT__cpu__DOT__tg68k__DOT__regfile_n2[i];
        return (n2 << 8) | n1;
    };
    uint32_t d0 = get_reg(0);
    uint32_t d1 = get_reg(1);
    std::cerr << "D0 = 0x" << std::hex << std::setw(8) << std::setfill('0') << d0
              << "  (MOVEQ #1 -> expect 0x00000001)\n"
              << "D1 = 0x" << std::setw(8) << d1
              << "  (FMOVE.L D0,FP0; FMOVE.L FP0,D1 round-trip -> expect 0x00000001)\n"
              << std::dec << std::setfill(' ');

    bool pass = (d0 == 1) && (d1 == 1);
    std::cerr << (pass ? "PASS — FMOVE.L D0,FP0,D1 round-trip works\n"
                       : "FAIL — FMOVE round-trip did not produce expected value\n");
    finish();
    return pass ? 0 : 1;
}
