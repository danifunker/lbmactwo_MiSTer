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
#include <iomanip>
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

    // ---- Helpers for register injection/readback --------------------
    // The ghdl-synthesized regfile is split across two unpacked arrays:
    //   regfile_n1[i] = bits [7:0]   (low byte)
    //   regfile_n2[i] = bits [31:8]  (upper 24 bits)
    // Indices 0..7 = D0..D7, 8..15 = A0..A7.
    auto set_reg = [](int i, uint32_t v) {
        VERTOPINTERN->tg68k_tests__DOT__cpu__DOT__regfile_n1[i] = v & 0xFF;
        VERTOPINTERN->tg68k_tests__DOT__cpu__DOT__regfile_n2[i] = (v >> 8) & 0xFFFFFF;
    };
    auto get_reg = [](int i) -> uint32_t {
        uint32_t n1 = VERTOPINTERN->tg68k_tests__DOT__cpu__DOT__regfile_n1[i];
        uint32_t n2 = VERTOPINTERN->tg68k_tests__DOT__cpu__DOT__regfile_n2[i];
        return (n2 << 8) | n1;
    };

    // ---- Register-path probe (--probe-regs) ---------------------------
    // Self-test that confirms the verilator-exposed regfile layout
    // (regfile_n1/n2 split) is the same one we use for injection.
    if (argc >= 2 && std::string(argv[1]) == "--probe-regs") {
        // Reset vectors: SSP=$00FFFFF8 at $0, PC=$1000 at $4.
        ram[0x00] = 0x00; ram[0x01] = 0xFF; ram[0x02] = 0xFF; ram[0x03] = 0xF8;
        ram[0x04] = 0x00; ram[0x05] = 0x00; ram[0x06] = 0x10; ram[0x07] = 0x00;
        // MOVE.L D0,(xxx).L $00000200 at $1000:  23C0 0000 0200
        ram[0x1000] = 0x23; ram[0x1001] = 0xC0;
        ram[0x1002] = 0x00; ram[0x1003] = 0x00;
        ram[0x1004] = 0x02; ram[0x1005] = 0x00;
        // STOP #$2700 at $1006: 4E72 2700
        ram[0x1006] = 0x4E; ram[0x1007] = 0x72;
        ram[0x1008] = 0x27; ram[0x1009] = 0x00;

        // Reset.
        top->reset = 1;
        for (int i = 0; i < 32; ++i) tick();
        top->reset = 0;

        // Immediately inject D0 = 0xDEADBEEF before kernel decodes MOVE.L.
        // Verilator splits the 32-bit regfile into two arrays:
        //   regfile_n1[i] = bits [7:0]   (low byte)
        //   regfile_n2[i] = bits [31:8]  (upper 24 bits)
        const uint32_t d0 = 0xDEADBEEFu;
        VERTOPINTERN->tg68k_tests__DOT__cpu__DOT__regfile_n1[0] = d0 & 0xFF;
        VERTOPINTERN->tg68k_tests__DOT__cpu__DOT__regfile_n2[0] = (d0 >> 8) & 0xFFFFFF;
        std::cerr << "Injected D0 = 0x" << std::hex << d0 << std::dec
                  << " before bus startup\n";

        // Trace bus until the kernel halts (STOP fires) or 200 cycles pass.
        uint32_t last_addr = ~0u;
        for (int i = 0; i < 200; ++i) {
            tick();
            uint32_t a = top->addr_out;
            uint8_t  bs = top->busstate;
            if (bs != 0b01 && (a != last_addr || bs == 0b11)) {
                std::cerr << "  cyc " << std::setw(3) << i
                          << " bs=" << int(bs)
                          << " addr=0x" << std::hex << std::setw(8)
                          << std::setfill('0') << a
                          << " data=0x" << std::setw(4) << top->data_write
                          << std::dec << std::setfill(' ') << "\n";
                last_addr = a;
            }
        }

        uint32_t result = (uint32_t(ram[0x200]) << 24)
                        | (uint32_t(ram[0x201]) << 16)
                        | (uint32_t(ram[0x202]) << 8)
                        |  uint32_t(ram[0x203]);
        std::cerr << "RAM[0x200..0x203] = 0x" << std::hex << std::setw(8)
                  << std::setfill('0') << result << std::dec
                  << (result == 0xDEADBEEF ? " ✓ regfile layout confirmed"
                                           : " ✗ MISMATCH — layout wrong")
                  << "\n";
        finish();
        return result == 0xDEADBEEF ? 0 : 1;
    }

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

    // ---- Real JSON test runner ----------------------------------------
    const std::string fname(argv[1]);
    std::ifstream f(fname);
    if (!f) { std::cerr << "Cannot open " << fname << "\n"; finish(); return 1; }
    json corpus = json::parse(f);

    int passed = 0, failed = 0;
    for (auto& t : corpus) {
        const std::string name = t.value("name", "<unnamed>");
        auto& init  = t["initial"];
        auto& final_ = t["final"];
        const uint32_t init_pc   = init["pc"];
        const uint32_t final_pc  = final_["pc"];
        const uint32_t init_ssp  = init["ssp"];

        // Clean RAM, plant reset vectors so kernel boots to init.pc.
        std::fill(ram.begin(), ram.end(), 0);
        ram[0] = (init_ssp >> 24) & 0xFF;
        ram[1] = (init_ssp >> 16) & 0xFF;
        ram[2] = (init_ssp >> 8) & 0xFF;
        ram[3] = init_ssp & 0xFF;
        ram[4] = (init_pc >> 24) & 0xFF;
        ram[5] = (init_pc >> 16) & 0xFF;
        ram[6] = (init_pc >> 8) & 0xFF;
        ram[7] = init_pc & 0xFF;
        // Initial RAM contents from the test (typically just the opcode).
        for (auto& cell : init["ram"]) {
            ram[cell[0].get<uint32_t>()] = cell[1].get<uint32_t>();
        }

        // Reset and immediately inject all 16 registers.
        top->reset = 1;
        for (int i = 0; i < 32; ++i) tick();
        top->reset = 0;
        for (int r = 0; r < 8; ++r) {
            set_reg(r, init["d" + std::to_string(r)].get<uint32_t>());
            set_reg(8 + r, init["a" + std::to_string(r)].get<uint32_t>());
        }

        // Run until the bus has prefetched well past the test
        // instruction. TG68K's prefetch reaches at least one full
        // instruction ahead of execution, so the first fetch at
        // final_pc fires before the register write-back. Wait until we
        // see a fetch at final_pc + 4 to be sure the test instruction
        // committed.
        bool done = false;
        bool saw_final = false;
        for (int cyc = 0; cyc < 5000 && !done; ++cyc) {
            tick();
            if (top->busstate == 0) {
                uint32_t a = top->addr_out & 0xFFFFFFFE;
                if (!saw_final && a == (final_pc & 0xFFFFFFFE)) {
                    saw_final = true;
                } else if (saw_final && a >= (final_pc & 0xFFFFFFFE) + 4) {
                    done = true;
                }
            }
        }

        // Capture post-state and check.
        bool pass = done;
        std::string fail_reason;
        if (!done) {
            fail_reason = "timeout (no fetch at final_pc)";
        } else {
            for (int r = 0; r < 8 && pass; ++r) {
                uint32_t got = get_reg(r);
                uint32_t exp = final_["d" + std::to_string(r)].get<uint32_t>();
                if (got != exp) {
                    char buf[80];
                    snprintf(buf, sizeof(buf), "D%d: got 0x%08X, expected 0x%08X",
                             r, got, exp);
                    fail_reason = buf;
                    pass = false;
                }
            }
            for (int r = 0; r < 8 && pass; ++r) {
                uint32_t got = get_reg(8 + r);
                uint32_t exp = final_["a" + std::to_string(r)].get<uint32_t>();
                if (got != exp) {
                    char buf[80];
                    snprintf(buf, sizeof(buf), "A%d: got 0x%08X, expected 0x%08X",
                             r, got, exp);
                    fail_reason = buf;
                    pass = false;
                }
            }
            for (auto& cell : final_["ram"]) {
                uint32_t addr = cell[0].get<uint32_t>();
                uint8_t  exp  = cell[1].get<uint32_t>();
                if (ram[addr] != exp) {
                    char buf[80];
                    snprintf(buf, sizeof(buf),
                             "RAM[0x%X]: got 0x%02X, expected 0x%02X",
                             addr, ram[addr], exp);
                    fail_reason = buf;
                    pass = false;
                    break;
                }
            }
        }

        if (pass) {
            ++passed;
        } else {
            ++failed;
            std::cerr << "FAIL " << name << ": " << fail_reason << "\n";
            // Disassemble the test instruction for context.
            std::cerr << "  instr: " << disasm_at(init_pc) << "\n";
        }
    }
    std::cerr << "\n" << passed << " passed, " << failed << " failed in "
              << fname << "\n";
    finish();
    return failed ? 1 : 0;
}
