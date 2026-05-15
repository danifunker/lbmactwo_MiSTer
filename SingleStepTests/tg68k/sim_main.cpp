// SingleStep harness for TG68KdotC_Kernel (68020 mode).
//
// Layout mirrors iigs_simulation/SingleStepTests/sim_main.cpp:
//   - top owns a 24-bit RAM (16 MiB) backing all CPU accesses
//   - one bus access per clkena_in pulse, dispatched by busstate
//   - per-test: load initial RAM + force PC/SR/regs via VERTOPINTERN paths,
//     run the recorded number of cycles, then compare final state
//
// Register injection paths are TBD — see WIRE-UP NOTES below. Until the
// mangled hierarchical names are confirmed, this binary only verifies that
// reset + free-run is healthy when run with no arguments.

#include <verilated.h>
#include "Vtg68k_tests.h"
#include "Vtg68k_tests__Syms.h"

#include <cstdio>
#include <cstdint>
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <algorithm>

#include "../json.hpp"
using json = nlohmann::json;

const char* disassemble_68k_ext(unsigned int pc,
                                const unsigned short* opwords,
                                int num_words);

#define VERILATOR_MAJOR_VERSION (VERILATOR_VERSION_INTEGER / 1000000)
#if VERILATOR_MAJOR_VERSION >= 5
  #define VERTOPINTERN top->rootp
#else
  #define VERTOPINTERN top
#endif

// busstate values
static constexpr uint8_t BS_FETCH = 0b00;
static constexpr uint8_t BS_IDLE  = 0b01;
static constexpr uint8_t BS_READ  = 0b10;
static constexpr uint8_t BS_WRITE = 0b11;

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

static Vtg68k_tests* top = nullptr;
static std::vector<uint8_t> ram;  // 16 MiB

static inline uint16_t ram_read16(uint32_t a) {
    a &= 0x00FFFFFE;
    return (uint16_t(ram[a]) << 8) | ram[a + 1];
}

// Disassemble up to 5 words starting at pc, using current RAM contents.
// Returns a pointer to a static buffer owned by the disassembler.
static const char* disasm_at(uint32_t pc) {
    unsigned short words[5] = {0};
    for (int i = 0; i < 5; ++i) words[i] = ram_read16(pc + i * 2);
    return disassemble_68k_ext(pc, words, 5);
}
static inline void ram_write16(uint32_t a, uint16_t v, bool uds, bool lds) {
    a &= 0x00FFFFFE;
    if (uds) ram[a]     = uint8_t(v >> 8);
    if (lds) ram[a + 1] = uint8_t(v & 0xFF);
}

// Service one bus access if the kernel is asserting one. Called while clkena
// is high right after the rising edge of clk.
static void service_bus() {
    const uint8_t bs = top->busstate;
    if (bs == BS_IDLE) return;
    const uint32_t a = top->addr_out;
    if (bs == BS_FETCH || bs == BS_READ) {
        top->data_in = ram_read16(a);
    } else if (bs == BS_WRITE) {
        ram_write16(a, top->data_write, !top->nUDS, !top->nLDS);
    }
}

static void tick(bool clkena = true) {
    top->clkena_in = clkena ? 1 : 0;
    top->clk = 0;
    top->eval();
    main_time++;
    top->clk = 1;
    top->eval();
    if (clkena) service_bus();
    main_time++;
}

static void finish() {
    top->final();
    delete top;
    top = nullptr;
}

int main(int argc, char** argv, char** env) {
    top = new Vtg68k_tests();
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    ram.assign(0x01000000, 0x00);

    // Reset: assert for several cycles, then release. CPU fetches initial
    // SSP from $000000-3 and initial PC from $000004-7 — leave them at 0
    // for now (kernel will start fetching at $0).
    top->reset = 1;
    top->data_in = 0;
    for (int i = 0; i < 32; ++i) tick();
    top->reset = 0;

    // No JSON yet — just step a few hundred cycles to prove the bus loop
    // is healthy, then exit.
    if (argc < 2) {
        for (int i = 0; i < 256; ++i) tick();
        // Smoke check that the disassembler is linked: plant a NOP at $0400
        // and dump it.
        ram[0x0400] = 0x4e; ram[0x0401] = 0x71;
        std::cerr << "tg68k bench: reset + free-run OK ("
                  << main_time << " sim units)\n"
                  << "disasm check at 0x0400: "
                  << disasm_at(0x0400) << "\n";
        finish();
        return 0;
    }

    // ---- WIRE-UP NOTES ---------------------------------------------------
    // To plumb JSON tests we still need to:
    //   1. Identify the mangled VERTOPINTERN paths for D0..D7/A0..A7,
    //      PC, SR, SSP/USP, VBR. Likely under
    //      tg68k_tests__DOT__cpu__DOT__... — confirm with
    //      `nm obj_dir/Vtg68k_tests__Syms.o` after first build.
    //   2. Decide format for the corpus. Real 68k SingleStepTests entries
    //      record cycle-by-cycle bus transactions, not just final state —
    //      we'll likely match cycle COUNT only and verify final regs + RAM.
    //   3. Implement test loop similar to the iigs harness.
    // ---------------------------------------------------------------------

    const std::string fname(argv[1]);
    std::ifstream f(fname);
    if (!f) {
        std::cerr << "Cannot open " << fname << "\n";
        finish();
        return 1;
    }
    std::cerr << "tg68k bench: JSON test loop not yet implemented "
                 "(register-path discovery pending). File: "
              << fname << "\n";
    finish();
    return 0;
}
