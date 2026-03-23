#include <verilated.h>
#include "Vemu.h"
#include "Vemu__Syms.h"

#include "imgui.h"
#include "implot.h"
#ifndef _MSC_VER
#include <stdio.h>
#include <SDL.h>
#include <SDL_opengl.h>
#else
#define WIN32
#include <dinput.h>
#endif

#define VERILATOR_MAJOR_VERSION (VERILATOR_VERSION_INTEGER / 1000000)

#if VERILATOR_MAJOR_VERSION >= 5
#define VERTOPINTERN top->rootp
#else
#define VERTOPINTERN top
#endif

#include "sim_console.h"
#include "sim_bus.h"
#include "sim_blkdevice.h"
#include "sim_video.h"
#include "sim_audio.h"
#include "sim_input.h"
#include "sim_clock.h"
#include "m68k_dasm.h"

#include "../imgui/imgui_memory_editor.h"
#include "../imgui/ImGuiFileDialog.h"

#include <iostream>
#include <sstream>
#include <fstream>
#include <iterator>
#include <string>
#include <iomanip>
#include <vector>
#include <algorithm>
using namespace std;

// stb_image_write for PNG screenshots
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "sim/stb_image_write.h"

// Simulation control
// ------------------
int initialReset = 48;
bool run_enable = 1;
int batchSize = 150000;
bool single_step = 0;
bool multi_step = 0;
int multi_step_amount = 1024;

// Machine configuration
// ---------------------
// Mac II only (uses TG68K 68030)
// cfg_cpuType=2  -> cpu="11" (68030 - required for Mac II)
int cfg_cpuType = 2;       // 68030 mode via TG68K (required)
int cfg_memSize = 0;       // 0=1MB, 1=4MB

// CPU trace
// ---------
bool cpu_trace_enable = true;   // Enabled by default; toggle in GUI
bool cpu_trace_started = false;  // Wait for ROM load and reset
FILE* cpu_trace_file = nullptr;
const char* cpu_trace_filename = "cpu_trace.log";
int cpu_trace_count = 0;
const int cpu_trace_max = 0;  // 0 = unlimited
int post_download_delay = 0;  // Delay after ROM load before tracing
uint32_t cpu_trace_last_pc = 0xFFFFFFFF;  // For edge detection (new instruction)

// RAM debug
// ---------
bool ram_debug_enable = false;  // Disable for speed
FILE* ram_debug_file = nullptr;
const char* ram_debug_filename = "ram_debug.log";
int ram_debug_count = 0;
const int ram_debug_max = 5000;  // Stop after this many RAM accesses

// Peripheral debug
// ----------------
bool periph_debug_enable = false;  // Disable for speed
FILE* periph_debug_file = nullptr;
const char* periph_debug_filename = "periph_debug.log";
int periph_debug_count = 0;
const int periph_debug_max = 5000;  // Stop after this many peripheral accesses
bool periph_debug_prev_bus_control = false;  // For edge detection

// VIA debug - captures at VMA-synchronized timing
// ------------------------------------------------
bool via_debug_enable = true;
FILE* via_debug_file = nullptr;
const char* via_debug_filename = "via_debug.log";
int via_debug_count = 0;
const int via_debug_max = 50000;
bool via_debug_prev_rd = false;
bool via_debug_prev_wr = false;

// Screenshot functionality
// ------------------------
std::vector<int> screenshot_frames;
bool screenshot_mode = false;

// Stop at frame functionality
// ---------------------------
int stop_at_frame = -1;
bool stop_at_frame_enabled = false;

// Headless mode (no GUI)
// ----------------------
bool headless = false;

// Debug GUI
// ---------
const char* windowTitle = "Verilator Sim: Macintosh II";
const char* windowTitle_Control = "Simulation control";
const char* windowTitle_DebugLog = "Debug log";
const char* windowTitle_Video = "VGA output";
const char* windowTitle_Audio = "Audio output";
bool showDebugLog = true;
DebugConsole console;
MemoryEditor mem_edit;

// HPS emulator
// ------------
SimBus bus(console);
SimBlockDevice blockdevice(console);

// Input handling
// --------------
SimInput input(13, console);
const int input_right = 0;
const int input_left = 1;
const int input_down = 2;
const int input_up = 3;
const int input_a = 4;
const int input_b = 5;
const int input_x = 6;
const int input_y = 7;
const int input_l = 8;
const int input_r = 9;
const int input_select = 10;
const int input_start = 11;
const int input_menu = 12;

// Video
// -----
// Mac LC VGA mode (monitor_id=6) is 640x480
#define VGA_WIDTH 640
#define VGA_HEIGHT 480
#define VGA_ROTATE 0
#define VGA_SCALE_X vga_scale
#define VGA_SCALE_Y vga_scale
SimVideo video(VGA_WIDTH, VGA_HEIGHT, VGA_ROTATE);
float vga_scale = 1.5;

// Verilog module
// --------------
Vemu* top = NULL;

vluint64_t main_time = 0;	// Current simulation time.
double sc_time_stamp() {	// Called by $time in Verilog.
	return main_time;
}

// 32.5 MHz system clock (matches FPGA PLL; CPU runs at 16 MHz via clock enables)
int clk_sys_freq = 32500000;
SimClock clk_sys(1);

// Audio
// -----
#ifndef DISABLE_AUDIO
SimAudio audio(clk_sys_freq, false);
#endif

// Reset simulation variables and clocks
void resetSim() {
	main_time = 0;
	VERTOPINTERN->reset = 1;
	clk_sys.Reset();
}

int verilate() {

	if (!Verilated::gotFinish()) {

		// Assert reset during startup
		if (main_time < initialReset) { VERTOPINTERN->reset = 1; }
		// Deassert reset after startup
		if (main_time == initialReset) { VERTOPINTERN->reset = 0; }

		// Clock dividers
		clk_sys.Tick();

		// Set system clock in core
		VERTOPINTERN->clk_sys = clk_sys.clk;

		// Set machine configuration (Mac LC only)
		VERTOPINTERN->cfg_cpuType = cfg_cpuType;
		VERTOPINTERN->cfg_memSize = cfg_memSize;

		// Simulate both edges of system clock
		if (clk_sys.clk != clk_sys.old) {
			if (clk_sys.IsRising() && *bus.ioctl_download != 1) {
				blockdevice.BeforeEval(main_time);
			}
			if (clk_sys.clk) {
				input.BeforeEval();
				bus.BeforeEval();
			}
			top->eval();
			if (clk_sys.clk) { bus.AfterEval(); blockdevice.AfterEval(); }

			// Vector table write watchpoint - log any write to $0-$3FF
			if (VERTOPINTERN->debug_write_valid && !*bus.ioctl_download && cpu_trace_file) {
				uint32_t waddr = VERTOPINTERN->debug_write_addr;
				if (waddr < 0x400) {
					uint16_t wdata = VERTOPINTERN->debug_write_data;
					fprintf(cpu_trace_file, "** VECWR %08X <= %04X\n", waddr, wdata);
				}
			}

			// CPU trace output - skip while ROM is downloading
			if (cpu_trace_enable && VERTOPINTERN->debug_fetch_valid && !*bus.ioctl_download) {
				// Use the debug signals from sim.v that capture actual bus transactions
				uint32_t pc = VERTOPINTERN->debug_pc;
				uint16_t opcode = VERTOPINTERN->debug_opcode;
				uint8_t fc = VERTOPINTERN->debug_fc;

				// Debug: show first 20 fetches with detailed memory info
				static int fetch_count = 0;
				if (fetch_count < 20) {
					fprintf(stderr, "FETCH[%d]: PC=%08X Op=%04X cpuAddr=%08X AS=%d ram_addr=%06X ram_dout=%04X selROM=%d selRAM=%d overlay=%d\n",
						fetch_count, pc, opcode,
						VERTOPINTERN->debug_cpuAddr,
						0, // _cpuAS not directly accessible
						VERTOPINTERN->debug_ram_addr,
						VERTOPINTERN->debug_ram_dout,
						VERTOPINTERN->debug_selectROM,
						VERTOPINTERN->debug_selectRAM,
						VERTOPINTERN->debug_memoryOverlayOn);
					fetch_count++;
				}

				// Only log when PC changes (new instruction) to avoid duplicates
				if (pc != cpu_trace_last_pc) {
					cpu_trace_last_pc = pc;

					// Disassemble - for now just use single opcode word
					unsigned short opwords[2] = { opcode, 0 };
					const char* disasm = disassemble_68k_ext(pc, opwords, 2);

					// Output to debug console
					console.AddLog("%08X: %04X  %s", pc, opcode, disasm);

					// Also write to trace file if open
					if (cpu_trace_file) {
						const char* fc_name = (fc == 6) ? "SP" : (fc == 5) ? "SD" : (fc == 2) ? "UP" : (fc == 1) ? "UD" : "??";
					fprintf(cpu_trace_file, "%s %08X: %04X  %s\n", fc_name, pc, opcode, disasm);
						cpu_trace_count++;
						if (cpu_trace_max > 0 && cpu_trace_count >= cpu_trace_max) {
							fprintf(stderr, "CPU trace limit reached (%d instructions)\n", cpu_trace_max);
							fclose(cpu_trace_file);
							cpu_trace_file = nullptr;
						}
					}
				}
			}

			// RAM debug output - skip while ROM is downloading
			if (ram_debug_enable && !*bus.ioctl_download && ram_debug_file) {
				bool we = VERTOPINTERN->debug_ram_we;
				bool oe = VERTOPINTERN->debug_ram_oe;
				bool selectRAM = VERTOPINTERN->debug_selectRAM;
				bool selectROM = VERTOPINTERN->debug_selectROM;
				bool cpu_write = !VERTOPINTERN->debug_cpuRW;  // RW=0 means write
				bool bus_control = VERTOPINTERN->debug_cpuBusControl;

				// Log actual RAM/ROM accesses, or attempted writes during overlay (selectROM but CPU write)
				bool is_access = (we || oe) && (selectRAM || selectROM);
				bool is_failed_write = selectROM && cpu_write && bus_control && !selectRAM;  // Write to overlay ROM area

				if ((is_access || is_failed_write) && ram_debug_count < ram_debug_max) {
					uint32_t addr = VERTOPINTERN->debug_ram_addr;
					uint32_t cpuAddr = VERTOPINTERN->debug_cpuAddr;
					uint16_t din = VERTOPINTERN->debug_ram_din;
					uint16_t dout = VERTOPINTERN->debug_ram_dout;
					uint8_t ds = VERTOPINTERN->debug_ram_ds;

					const char* op = we ? "WR" : (is_failed_write ? "WR-FAIL" : "RD");
					fprintf(ram_debug_file, "%s cpuAddr=%06X ramAddr=%07X din=%04X dout=%04X ds=%d%d selRAM=%d selROM=%d\n",
						op,
						cpuAddr, addr, din, dout,
						(ds >> 1) & 1, ds & 1,
						selectRAM ? 1 : 0,
						selectROM ? 1 : 0);
					ram_debug_count++;
					if (ram_debug_count >= ram_debug_max) {
						fprintf(stderr, "RAM debug limit reached (%d accesses)\n", ram_debug_max);
						fclose(ram_debug_file);
						ram_debug_file = nullptr;
					}
				}
			}

			// Peripheral debug output - log on falling edge of cpuBusControl
			if (periph_debug_enable && !*bus.ioctl_download && periph_debug_file) {
				bool bus_control = VERTOPINTERN->debug_cpuBusControl;
				// Log on rising edge of bus control (start of CPU cycle) when a peripheral is selected
				if (bus_control && !periph_debug_prev_bus_control) {
					bool selectVIA = VERTOPINTERN->debug_selectVIA;
					bool selectSCSI = VERTOPINTERN->debug_selectSCSI;
					bool selectSCC = VERTOPINTERN->debug_selectSCC;
					bool selectIWM = VERTOPINTERN->debug_selectIWM;

					if ((selectVIA || selectSCSI || selectSCC || selectIWM)
					    && periph_debug_count < periph_debug_max) {
						uint32_t addr = VERTOPINTERN->debug_cpuAddr;
						uint16_t data_in = VERTOPINTERN->debug_cpuDataIn;
						uint16_t data_out = VERTOPINTERN->debug_cpuDataOut;
						bool rw = VERTOPINTERN->debug_cpuRW;

						const char* periph_name = selectVIA ? "VIA" :
						                          selectSCSI ? "SCSI" :
						                          selectSCC ? "SCC" :
						                          selectIWM ? "IWM" : "???";

						fprintf(periph_debug_file, "%s %s addr=%06X data_in=%04X data_out=%04X\n",
							rw ? "RD" : "WR",
							periph_name,
							addr,
							data_in,
							data_out);
						periph_debug_count++;
						if (periph_debug_count >= periph_debug_max) {
							fprintf(stderr, "Peripheral debug limit reached (%d accesses)\n", periph_debug_max);
							fclose(periph_debug_file);
							periph_debug_file = nullptr;
						}
					}
				}
				periph_debug_prev_bus_control = bus_control;
			}

			// VIA debug - captures at VMA-synchronized timing (when VIA actually reads/writes)
			if (via_debug_enable && !*bus.ioctl_download && via_debug_file) {
				bool via_rd = VERTOPINTERN->debug_viaRd;
				bool via_wr = VERTOPINTERN->debug_viaWr;

				// Log on rising edge of VIA read or write enable
				if ((via_rd && !via_debug_prev_rd) || (via_wr && !via_debug_prev_wr)) {
					uint32_t addr = VERTOPINTERN->debug_cpuAddr;
					uint16_t data_out = VERTOPINTERN->debug_cpuDataOut;  // data from VIA to CPU
					uint16_t data_in = VERTOPINTERN->debug_cpuDataIn;   // data from CPU to VIA
					uint32_t pc = VERTOPINTERN->debug_pc;
					bool rw = VERTOPINTERN->debug_cpuRW;
					bool vma = !VERTOPINTERN->debug_cpuVMA;  // active low
					bool via2 = VERTOPINTERN->debug_selectVIA2;
					int reg_num = (addr >> 9) & 0xF;  // VIA register from A12-A9

					const char* via_name = via2 ? "VIA2" : "VIA1";
					const char* reg_names[] = {
						"ORB", "ORA", "DDRB", "DDRA",
						"T1CL", "T1CH", "T1LL", "T1LH",
						"T2CL", "T2CH", "SR", "ACR",
						"PCR", "IFR", "IER", "ORA-NH"
					};

					fprintf(via_debug_file, "%s %s reg=%d(%s) addr=%08X data_out=%04X data_in=%04X VMA=%d PC=%08X\n",
						rw ? "RD" : "WR",
						via_name,
						reg_num, reg_names[reg_num & 0xF],
						addr, data_out, data_in, vma, pc);
					fflush(via_debug_file);
					via_debug_count++;
					if (via_debug_count >= via_debug_max) {
						fprintf(stderr, "VIA debug limit reached (%d accesses)\n", via_debug_max);
						fclose(via_debug_file);
						via_debug_file = nullptr;
					}
				}
				via_debug_prev_rd = via_rd;
				via_debug_prev_wr = via_wr;
			}
		}

#ifndef DISABLE_AUDIO
		if (clk_sys.IsRising())
		{
			audio.Clock(VERTOPINTERN->AUDIO_L, VERTOPINTERN->AUDIO_R);
		}
#endif

		// Output pixels on rising edge of pixel clock
		if (clk_sys.IsRising() && VERTOPINTERN->CE_PIXEL) {
			uint32_t colour = 0xFF000000 | VERTOPINTERN->VGA_B << 16 | VERTOPINTERN->VGA_G << 8 | VERTOPINTERN->VGA_R;
			video.Clock(VERTOPINTERN->VGA_HB, VERTOPINTERN->VGA_VB, VERTOPINTERN->VGA_HS, VERTOPINTERN->VGA_VS, colour);
		}

		if (clk_sys.IsRising()) {
			main_time++;
			// Print progress every 10 million cycles (~308ms of simulated time at 32.5MHz)
			if ((main_time % 10000000) == 0) {
				fprintf(stderr, "Cycle %llu: PC=%08X Op=%04X RW=%d overlay=%d selROM=%d selRAM=%d VBR=%08X\n",
					(unsigned long long)main_time,
					VERTOPINTERN->debug_pc,
					VERTOPINTERN->debug_opcode,
					VERTOPINTERN->debug_cpuRW,
					VERTOPINTERN->debug_memoryOverlayOn,
					VERTOPINTERN->debug_selectROM,
					VERTOPINTERN->debug_selectRAM,
					VERTOPINTERN->debug_vbr);
			}
			// Log IPL changes (interrupt level)
			{
				static uint8_t last_ipl = 7;
				uint8_t cur_ipl = VERTOPINTERN->debug_cpuIPL;
				if (cur_ipl != last_ipl) {
					fprintf(stderr, "IPL %d->%d at cycle %llu: PC=%08X addr=%08X FC=%d VBR=%08X\n",
						last_ipl, cur_ipl, (unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						VERTOPINTERN->debug_cpuAddr,
						VERTOPINTERN->debug_fc,
						VERTOPINTERN->debug_vbr);
					last_ipl = cur_ipl;
				}
			}
			// Log SCC state changes and chip select activity
			{
				static uint8_t last_wr9 = 0xFF, last_wr5a = 0xFF, last_wr1a = 0xFF;
				static uint8_t last_txip = 0xFF;
				static uint8_t last_wreg_a = 0, wreg_a_count = 0;
				uint8_t wr9 = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr9;
				uint8_t wr5a = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr5_a;
				uint8_t wr1a = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr1_a;
				uint8_t txip = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__tx_ip;
				uint8_t wreg_a = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wreg_a;
				uint8_t selSCC = VERTOPINTERN->emu__DOT__selectSCC;
				if (wr9 != last_wr9 || wr5a != last_wr5a || wr1a != last_wr1a || txip != last_txip) {
					fprintf(stderr, "SCC @%llu: WR9=%02X(MIE=%d) WR5a=%02X(TxEn=%d) WR1a=%02X(TxIE=%d) tx_ip=%d\n",
						(unsigned long long)main_time,
						wr9, (wr9>>3)&1, wr5a, (wr5a>>3)&1, wr1a, (wr1a>>1)&1, txip);
					last_wr9 = wr9; last_wr5a = wr5a; last_wr1a = wr1a; last_txip = txip;
				}
				// Log SCC write events (wreg_a or wreg_b rising edge)
				uint8_t wreg_b = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wreg_b;
				if ((wreg_a && !last_wreg_a) || (wreg_b && !last_wreg_a && wreg_a_count < 100)) {
					uint8_t rindex_v = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__rindex;
					fprintf(stderr, "SCC_WR @%llu: ch=%c rindex=%d PC=%08X addr=%08X\n",
						(unsigned long long)main_time,
						wreg_a ? 'A' : 'B', rindex_v,
						VERTOPINTERN->debug_pc,
						VERTOPINTERN->debug_cpuAddr);
					wreg_a_count++;
				}
				last_wreg_a = wreg_a;
				// Log rx_wr_a_latch changes and startup counter
				{
					static uint8_t last_rxlatch = 0xFF;
					uint8_t rxlatch = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__rx_wr_a_latch;
					uint8_t rr0a = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__rr0_a;
					if (rxlatch != last_rxlatch) {
						fprintf(stderr, "SCC_RX @%llu: rx_wr_a_latch=%d rr0_a=%02X\n",
							(unsigned long long)main_time, rxlatch, rr0a);
						last_rxlatch = rxlatch;
					}
				}
			}
			// Log BERR events
			if (VERTOPINTERN->debug_berr) {
				fprintf(stderr, "*** BERR at cycle %llu: PC=%08X addr=%08X FC=%d\n",
					(unsigned long long)main_time,
					VERTOPINTERN->debug_pc,
					VERTOPINTERN->debug_cpuAddr,
					VERTOPINTERN->debug_fc);
			}
			// Log ALL NuBus accesses after cycle 310M (post-RAM-test)
			static bool nubus_log_prev = false;
			if (main_time >= 310000000 && main_time < 350000000) {
				bool nubus_now = VERTOPINTERN->debug_selectNuBus;
				if (nubus_now && !nubus_log_prev) {
					fprintf(stderr, "NUBUS_ACCESS cycle=%llu: PC=%08X addr=%08X RW=%d FC=%d\n",
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						VERTOPINTERN->debug_cpuAddr,
						VERTOPINTERN->debug_cpuRW,
						VERTOPINTERN->debug_fc);
				}
				nubus_log_prev = nubus_now;
			}
			// CPU trace window around crash point (344M)
			// Log every bus cycle with PC, address, data, RW
			if (main_time >= 344000000 && main_time < 344500000) {
				static uint32_t last_trace_addr = 0;
				uint32_t cur_addr = VERTOPINTERN->debug_cpuAddr;
				if (cur_addr != last_trace_addr || VERTOPINTERN->debug_berr) {
					fprintf(stderr, "TRACE %llu: PC=%08X addr=%08X RW=%d FC=%d AS=%d BERR=%d selRAM=%d selROM=%d selNuBus=%d\n",
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						cur_addr,
						VERTOPINTERN->debug_cpuRW,
						VERTOPINTERN->debug_fc,
						0, // AS not easily available
						VERTOPINTERN->debug_berr ? 1 : 0,
						VERTOPINTERN->debug_selectRAM ? 1 : 0,
						VERTOPINTERN->debug_selectROM ? 1 : 0,
						VERTOPINTERN->debug_selectNuBus ? 1 : 0);
					last_trace_addr = cur_addr;
				}
			}
			// Boot decision watchpoints - log key PC values to stderr
			if (VERTOPINTERN->debug_fetch_valid && !*bus.ioctl_download) {
				uint32_t pc = VERTOPINTERN->debug_pc;

				// VIA1 Port A state at critical decision points
				uint8_t via_pra = VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__pio_i_pra;
				uint8_t via_ddra = VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__pio_i_ddra;
				uint8_t via_pac = VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__port_a_c;
				uint8_t via_ira = VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__ira;

				// Dongle detection: read PA, test bit 1 at $2A8C and $2A9E
				if (pc == 0x40802A7C || pc == 0x40802A84 || pc == 0x40802A88 ||
				    pc == 0x40802A8C || pc == 0x40802A90 ||
				    pc == 0x40802A92 || pc == 0x40802A96 ||
				    pc == 0x40802A9A || pc == 0x40802A9E || pc == 0x40802AA2) {
					uint16_t dbus = VERTOPINTERN->debug_cpuDataOut;
					uint32_t addr = VERTOPINTERN->debug_cpuAddr;
					fprintf(stderr, "*** DONGLE @%08X cycle %llu: PRA=%02X DDRA=%02X PAC=%02X IRA=%02X bus=%04X addr=%08X ***\n",
						pc, (unsigned long long)main_time, via_pra, via_ddra, via_pac, via_ira, dbus, addr);
				}


				// Debug dongle detection: bset #26,D7 means dongle detected
				if (pc == 0x40802AA4)
					fprintf(stderr, "*** DONGLE DETECTED (bset #26,D7) at cycle %llu: PRA=%02X DDRA=%02X PAC=%02X IRA=%02X ***\n",
						(unsigned long long)main_time, via_pra, via_ddra, via_pac, via_ira);
				// ROM checksum test: tst.l D6 — if D6!=0, enters debug monitor
				if (pc == 0x40802AB4)
					fprintf(stderr, "*** ROM CHECKSUM TEST (tst.l D6) at cycle %llu ***\n", (unsigned long long)main_time);
				// bne after checksum test — if we see $2ABA next, checksum passed; $2C3C = failed
				if (pc == 0x40802AB6)
					fprintf(stderr, "*** ROM CHECKSUM BNE at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x40802ABA)
					fprintf(stderr, "*** ROM CHECKSUM PASSED (clr.w D7) at cycle %llu ***\n", (unsigned long long)main_time);
				// Debug monitor entry
				if (pc == 0x40802C3C)
					fprintf(stderr, "*** DEBUG MONITOR ENTRY at cycle %llu ***\n", (unsigned long long)main_time);
				// SCC polling loop
				if (pc == 0x40803296)
					fprintf(stderr, "*** SCC POLL LOOP ENTRY at cycle %llu ***\n", (unsigned long long)main_time);
				// Bus error handler at $2906
				if (pc == 0x40802906)
					fprintf(stderr, "*** BUS ERROR HANDLER at cycle %llu ***\n", (unsigned long long)main_time);
			}

			// After ROM download completes, verify ROM data in sim_ram
			{
				static bool rom_verified = false;
				if (!*bus.ioctl_download && !rom_verified && main_time > 5000000) {
					rom_verified = true;
					// Read first 8 words of ROM from sim_ram
					// ROM is at sim_ram address 0x200000+ (word addresses)
					// Access via ram: addr input -> dout
					fprintf(stderr, "ROM VERIFY: Checking ROM in sim_ram at word addr 0x200000+\n");
					// We can't directly access sim_ram memory from here easily,
					// but we can check what debug_ram_dout returns.
					// Instead, let's compute expected checksum from ROM file
					fprintf(stderr, "ROM VERIFY: ROM file checksum should be $9779D2C4\n");
					fprintf(stderr, "ROM VERIFY: If checksum fails, ROM data in sim_ram may be corrupt\n");
				}
			}

			// Enable CPU trace after checksum passes → debug monitor entry
			// Programmatic trace window removed - use GUI checkbox or default-on instead
		}
		return 1;
	}

	// Stop verilating and cleanup
	top->final();
	delete top;
	exit(0);
	return 0;
}

void show_help() {
	printf("Mac II Hardware Simulator\n");
	printf("Usage: ./Vemu [options]\n\n");
	printf("Options:\n");
	printf("  -h, --help                    Show this help message\n");
	printf("  --headless, --no-gui          Run without SDL/ImGui (CI/headless)\n");
	printf("  --screenshot <frames>         Take screenshots at specified frame numbers\n");
	printf("                                (comma-separated list, e.g., 100,200,300)\n");
	printf("  --stop-at-frame <frame>       Exit simulation after specified frame\n");
	printf("\n");
	printf("Examples:\n");
	printf("  ./Vemu                        Run simulator in windowed mode\n");
	printf("  ./Vemu --screenshot 245       Take screenshot at frame 245\n");
	printf("  ./Vemu --stop-at-frame 300    Stop simulation after frame 300\n");
	printf("  ./Vemu --headless --screenshot 50 --stop-at-frame 100\n");
	printf("                                Headless, take screenshot at frame 50, stop at 100\n");
}

void save_screenshot(int frame_number) {
	if (!output_ptr) {
		printf("Error: output_ptr is null, cannot save screenshot\n");
		return;
	}

	char filename[256];
	snprintf(filename, sizeof(filename), "screenshot_frame_%04d.png", frame_number);

	// Read from the video output buffer that video.Clock() writes to
	// The colour format is: 0xFF000000 | B << 16 | G << 8 | R (ABGR)
	// Mac LC screen dimensions come from the video module

	int width = video.output_width;
	int height = video.output_height;

	uint8_t* rgb_data = (uint8_t*)malloc(width * height * 3);
	if (!rgb_data) {
		printf("Error: Could not allocate memory for screenshot\n");
		return;
	}

	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			uint32_t pixel = output_ptr[y * width + x];
			int dst_index = (y * width + x) * 3;

			// Format: 0xFF000000 | B << 16 | G << 8 | R (ABGR)
			uint8_t b = (pixel >> 16) & 0xFF;
			uint8_t g = (pixel >> 8) & 0xFF;
			uint8_t r = (pixel >> 0) & 0xFF;

			rgb_data[dst_index + 0] = r;
			rgb_data[dst_index + 1] = g;
			rgb_data[dst_index + 2] = b;
		}
	}

	// Save as PNG using stb_image_write
	int result = stbi_write_png(filename, width, height, 3, rgb_data, width * 3);

	free(rgb_data);

	if (result) {
		printf("Screenshot saved: %s (%dx%d)\n", filename, width, height);
	} else {
		printf("Error: Failed to save screenshot %s\n", filename);
	}
}

unsigned char mouse_clock = 0;
unsigned char mouse_buttons = 0;
unsigned char mouse_x = 0;
unsigned char mouse_y = 0;

int main(int argc, char** argv, char** env) {

	// Parse command-line arguments
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
			show_help();
			return 0;
		} else if (strcmp(argv[i], "--headless") == 0 || strcmp(argv[i], "--no-gui") == 0) {
			headless = true;
		} else if (strcmp(argv[i], "--screenshot") == 0 && i + 1 < argc) {
			screenshot_mode = true;
			std::string frames_str = argv[i + 1];
			std::stringstream ss(frames_str);
			std::string frame_num;
			while (std::getline(ss, frame_num, ',')) {
				screenshot_frames.push_back(std::stoi(frame_num));
			}
			printf("Screenshot mode enabled for frames: %s\n", frames_str.c_str());
			i++;
		} else if (strcmp(argv[i], "--stop-at-frame") == 0 && i + 1 < argc) {
			stop_at_frame = std::stoi(argv[i + 1]);
			stop_at_frame_enabled = true;
			printf("Will stop at frame %d\n", stop_at_frame);
			i++;
		}
	}

	// Create core and initialise
	top = new Vemu();
	Verilated::commandArgs(argc, argv);
	Verilated::traceEverOn(true);

	// Attach bus - using 16-bit ioctl_dout for MacLC
	bus.ioctl_addr = &VERTOPINTERN->ioctl_addr;
	bus.ioctl_index = &VERTOPINTERN->ioctl_index;
	bus.ioctl_wait = &VERTOPINTERN->ioctl_wait;
	bus.ioctl_download = &VERTOPINTERN->ioctl_download;
	bus.ioctl_wr = &VERTOPINTERN->ioctl_wr;
	bus.ioctl_dout = &VERTOPINTERN->ioctl_dout;  // 16-bit for MacLC
	input.ps2_key = &VERTOPINTERN->ps2_key;

	// Hookup block device for SCSI (2 devices for MacLC)
	blockdevice.sd_lba[0] = &VERTOPINTERN->sd_lba[0];
	blockdevice.sd_lba[1] = &VERTOPINTERN->sd_lba[1];
	blockdevice.sd_rd = &VERTOPINTERN->sd_rd;
	blockdevice.sd_wr = &VERTOPINTERN->sd_wr;
	blockdevice.sd_ack = &VERTOPINTERN->sd_ack;
	blockdevice.sd_buff_addr = &VERTOPINTERN->sd_buff_addr;
	blockdevice.sd_buff_dout = &VERTOPINTERN->sd_buff_dout;
	blockdevice.sd_buff_din[0] = &VERTOPINTERN->sd_buff_din[0];
	blockdevice.sd_buff_din[1] = &VERTOPINTERN->sd_buff_din[1];
	blockdevice.sd_buff_wr = &VERTOPINTERN->sd_buff_wr;
	blockdevice.img_mounted = &VERTOPINTERN->img_mounted;
	blockdevice.img_size = &VERTOPINTERN->img_size;

#ifndef DISABLE_AUDIO
	audio.Initialise();
#endif

	// Set up input module
	input.Initialise();
#ifdef WIN32
	input.SetMapping(input_up, DIK_UP);
	input.SetMapping(input_right, DIK_RIGHT);
	input.SetMapping(input_down, DIK_DOWN);
	input.SetMapping(input_left, DIK_LEFT);
	input.SetMapping(input_a, DIK_Z);
	input.SetMapping(input_b, DIK_X);
	input.SetMapping(input_x, DIK_A);
	input.SetMapping(input_y, DIK_S);
	input.SetMapping(input_l, DIK_Q);
	input.SetMapping(input_r, DIK_W);
	input.SetMapping(input_select, DIK_1);
	input.SetMapping(input_start, DIK_2);
	input.SetMapping(input_menu, DIK_M);
#else
	input.SetMapping(input_up, SDL_SCANCODE_UP);
	input.SetMapping(input_right, SDL_SCANCODE_RIGHT);
	input.SetMapping(input_down, SDL_SCANCODE_DOWN);
	input.SetMapping(input_left, SDL_SCANCODE_LEFT);
	input.SetMapping(input_a, SDL_SCANCODE_A);
	input.SetMapping(input_b, SDL_SCANCODE_B);
	input.SetMapping(input_x, SDL_SCANCODE_X);
	input.SetMapping(input_y, SDL_SCANCODE_Y);
	input.SetMapping(input_l, SDL_SCANCODE_L);
	input.SetMapping(input_r, SDL_SCANCODE_E);
	input.SetMapping(input_start, SDL_SCANCODE_1);
	input.SetMapping(input_select, SDL_SCANCODE_2);
	input.SetMapping(input_menu, SDL_SCANCODE_M);
#endif

	// Setup video output
	if (video.Initialise(windowTitle) == 1) { return 1; }

	// Open CPU trace file
	if (cpu_trace_enable) {
		cpu_trace_file = fopen(cpu_trace_filename, "w");
		if (cpu_trace_file) {
			fprintf(stderr, "CPU trace enabled, writing to %s\n", cpu_trace_filename);
		} else {
			fprintf(stderr, "Failed to open trace file %s\n", cpu_trace_filename);
			cpu_trace_enable = false;
		}
	}

	// Open RAM debug file
	if (ram_debug_enable) {
		ram_debug_file = fopen(ram_debug_filename, "w");
		if (ram_debug_file) {
			fprintf(stderr, "RAM debug enabled, writing to %s\n", ram_debug_filename);
		} else {
			fprintf(stderr, "Failed to open RAM debug file %s\n", ram_debug_filename);
			ram_debug_enable = false;
		}
	}

	// Open peripheral debug file
	if (periph_debug_enable) {
		periph_debug_file = fopen(periph_debug_filename, "w");
		if (periph_debug_file) {
			fprintf(stderr, "Peripheral debug enabled, writing to %s\n", periph_debug_filename);
		} else {
			fprintf(stderr, "Failed to open peripheral debug file %s\n", periph_debug_filename);
			periph_debug_enable = false;
		}
	}

	// Open VIA debug file
	if (via_debug_enable) {
		via_debug_file = fopen(via_debug_filename, "w");
		if (via_debug_file) {
			fprintf(stderr, "VIA debug enabled, writing to %s\n", via_debug_filename);
		} else {
			fprintf(stderr, "Failed to open VIA debug file %s\n", via_debug_filename);
			via_debug_enable = false;
		}
	}

	// Auto-load Mac II ROM at startup
	const char* rom_file = "../releases/boot0.rom";  // Mac II 256K ROM
	bus.QueueDownload(rom_file, 0, 1);  // index 0 for ROM
	fprintf(stderr, "Machine type: Mac II, loading ROM: %s\n", rom_file);

	// Auto-load NuBus High-Res video card declaration ROM
	const char* nubus_rom_file = "../releases/boot1.rom";  // Hi-Res 341-0660
	bus.QueueDownload(nubus_rom_file, 1, 1);  // index 1 for NuBus ROM
	fprintf(stderr, "Loading NuBus video ROM: %s\n", nubus_rom_file);

	// Initial eval() to establish clock state for Verilator
	// This is needed for correct rising edge detection on the first cycle
	VERTOPINTERN->clk_sys = 0;
	VERTOPINTERN->reset = 1;
	top->eval();

#ifdef WIN32
	MSG msg;
	ZeroMemory(&msg, sizeof(msg));
	while (msg.message != WM_QUIT)
	{
		if (PeekMessage(&msg, NULL, 0U, 0U, PM_REMOVE))
		{
			TranslateMessage(&msg);
			DispatchMessage(&msg);
			continue;
		}
#else
	bool done = false;
	while (!done)
	{
		SDL_Event event;
		while (SDL_PollEvent(&event))
		{
			ImGui_ImplSDL2_ProcessEvent(&event);
			if (event.type == SDL_QUIT)
				done = true;
		}
#endif
		video.StartFrame();

		input.Read();

		// Draw GUI
		// --------
		ImGui::NewFrame();

		// Simulation control window
		ImGui::Begin(windowTitle_Control);
		ImGui::SetWindowPos(windowTitle_Control, ImVec2(0, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Control, ImVec2(500, 200), ImGuiCond_Once);
		if (ImGui::Button("Reset simulation")) { resetSim(); } ImGui::SameLine();
		if (ImGui::Button("Start running")) { run_enable = 1; } ImGui::SameLine();
		if (ImGui::Button("Stop running")) { run_enable = 0; } ImGui::SameLine();
		ImGui::Checkbox("RUN", &run_enable);
		ImGui::SliderInt("Run batch size", &batchSize, 1, 250000);
		if (single_step == 1) { single_step = 0; }
		if (ImGui::Button("Single Step")) { run_enable = 0; single_step = 1; }
		ImGui::SameLine();
		if (multi_step == 1) { multi_step = 0; }
		if (ImGui::Button("Multi Step")) { run_enable = 0; multi_step = 1; }
		ImGui::SliderInt("Multi step amount", &multi_step_amount, 8, 1024);

		if (ImGui::Button("Load ROM"))
			ImGuiFileDialog::Instance()->OpenDialog("ChooseFileDlgKey", "Choose ROM File", ".rom,.bin", ".");

		// CPU trace controls
		ImGui::Separator();
		if (ImGui::Checkbox("CPU Trace", &cpu_trace_enable)) {
			if (cpu_trace_enable && !cpu_trace_file) {
				cpu_trace_file = fopen(cpu_trace_filename, "w");
				cpu_trace_count = 0;
				if (cpu_trace_file)
					fprintf(stderr, "CPU trace enabled via GUI, writing to %s\n", cpu_trace_filename);
			} else if (!cpu_trace_enable && cpu_trace_file) {
				fclose(cpu_trace_file);
				cpu_trace_file = nullptr;
				fprintf(stderr, "CPU trace disabled via GUI\n");
			}
		}
		ImGui::SameLine();
		ImGui::Text("PC: %08X  Op: %04X", VERTOPINTERN->debug_pc, VERTOPINTERN->debug_opcode);

		// Machine configuration (display only - requires restart to change)
		ImGui::Separator();
		ImGui::Text("Machine: Mac II | CPU: TG68K | RAM: %s",
			cfg_memSize ? "4MB" : "1MB");

		ImGui::End();

		// Debug log window
		console.Draw(windowTitle_DebugLog, &showDebugLog, ImVec2(500, 700));
		ImGui::SetWindowPos(windowTitle_DebugLog, ImVec2(0, 210), ImGuiCond_Once);

		// Memory debug - access sim_ram memory
		ImGui::Begin("RAM Editor");
		ImGui::Text("Note: Memory editor requires direct RAM access");
		ImGui::Text("RAM module is sim_ram with 8MB capacity");
		ImGui::End();

		int windowX = 550;
		int windowWidth = (VGA_WIDTH * VGA_SCALE_X) + 24;
		int windowHeight = (VGA_HEIGHT * VGA_SCALE_Y) + 90;

		// Video window
		ImGui::Begin(windowTitle_Video);
		ImGui::SetWindowPos(windowTitle_Video, ImVec2(windowX, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Video, ImVec2(windowWidth, windowHeight), ImGuiCond_Once);

		ImGui::SliderFloat("Zoom", &vga_scale, 1, 4); ImGui::SameLine();
		ImGui::SliderInt("Rotate", &video.output_rotate, -1, 1); ImGui::SameLine();
		ImGui::Checkbox("Flip V", &video.output_vflip);
		ImGui::Text("main_time: %llu frame_count: %d sim FPS: %f", main_time, video.count_frame, video.stats_fps);

		// Draw VGA output
		ImGui::Image(video.texture_id, ImVec2(video.output_width * VGA_SCALE_X, video.output_height * VGA_SCALE_Y));
		ImGui::End();

		if (ImGuiFileDialog::Instance()->Display("ChooseFileDlgKey"))
		{
			if (ImGuiFileDialog::Instance()->IsOk())
			{
				std::string filePathName = ImGuiFileDialog::Instance()->GetFilePathName();
				std::string filePath = ImGuiFileDialog::Instance()->GetCurrentPath();
				fprintf(stderr, "Loading ROM: %s\n", filePathName.c_str());
				bus.QueueDownload(filePathName, 0, 1);  // index 0 for ROM
			}
			ImGuiFileDialog::Instance()->Close();
		}

#ifndef DISABLE_AUDIO
		ImGui::Begin(windowTitle_Audio);
		ImGui::SetWindowPos(windowTitle_Audio, ImVec2(windowX, windowHeight), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Audio, ImVec2(windowWidth, 250), ImGuiCond_Once);

		if (run_enable) {
			audio.CollectDebug((signed short)VERTOPINTERN->AUDIO_L, (signed short)VERTOPINTERN->AUDIO_R);
		}
		int channelWidth = (windowWidth / 2) - 16;
		ImPlot::CreateContext();
		if (ImPlot::BeginPlot("Audio - L", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_l, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImGui::SameLine();
		if (ImPlot::BeginPlot("Audio - R", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_r, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImPlot::DestroyContext();
		ImGui::End();
#endif

		video.UpdateTexture();

		// Handle screenshots at specified frames
		bool took_screenshot_this_frame = false;
		if (screenshot_mode) {
			auto it = std::find(screenshot_frames.begin(), screenshot_frames.end(), video.count_frame);
			if (it != screenshot_frames.end()) {
				save_screenshot(video.count_frame);
				screenshot_frames.erase(it);
				took_screenshot_this_frame = true;
			}
		}

		// Check if we should stop at this frame
		if (stop_at_frame_enabled && video.count_frame >= stop_at_frame) {
			if (took_screenshot_this_frame) {
				printf("Reached stop frame %d after taking screenshot, exiting...\n", stop_at_frame);
			} else {
				printf("Reached stop frame %d, exiting...\n", stop_at_frame);
			}
			break;
		}

		// Pass inputs to sim - PS2 mouse for Mac
		mouse_buttons = 0;
		mouse_x = 0;
		mouse_y = 0;
		if (input.inputs[input_left]) { mouse_x = -2; }
		if (input.inputs[input_right]) { mouse_x = 2; }
		if (input.inputs[input_up]) { mouse_y = 2; }
		if (input.inputs[input_down]) { mouse_y = -2; }

		if (input.inputs[input_a]) { mouse_buttons |= (1UL << 0); }  // Left click
		if (input.inputs[input_b]) { mouse_buttons |= (1UL << 1); }  // Right click

		unsigned long mouse_temp = mouse_buttons;
		mouse_temp += (mouse_x << 8);
		mouse_temp += (mouse_y << 16);
		if (mouse_clock) { mouse_temp |= (1UL << 24); }
		mouse_clock = !mouse_clock;

		VERTOPINTERN->ps2_mouse = mouse_temp;

		// Run simulation
		if (run_enable) {
			for (int step = 0; step < batchSize; step++) { verilate(); }
		}
		else {
			if (single_step) { verilate(); }
			if (multi_step) {
				for (int step = 0; step < multi_step_amount; step++) { verilate(); }
			}
		}
	}

	// Clean up before exit
	// --------------------

#ifndef DISABLE_AUDIO
	audio.CleanUp();
#endif
	video.CleanUp();
	input.CleanUp();

	return 0;
}
