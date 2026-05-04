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
#include "sim_serial.h"
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
bool cpu_trace_enable = true;  // Disabled by default for speed; toggle in GUI
bool cpu_trace_started = false;  // Wait for ROM load and reset
FILE* cpu_trace_file = nullptr;
const char* cpu_trace_filename = "cpu_trace.log";
int cpu_trace_count = 0;
const int cpu_trace_max = 0;  // 0 = unlimited
int post_download_delay = 0;  // Delay after ROM load before tracing
uint32_t cpu_trace_last_pc = 0xFFFFFFFF;  // For edge detection (new instruction)

// Fetch buffer: sliding window of recent code-space fetches (PC -> word).
// TG68 fetches opcode then extension words sequentially; buffer up to
// FETCH_BUF_SIZE consecutive fetches and emit the oldest when we have enough
// context to disassemble the full instruction.
struct FetchEntry { uint32_t pc; uint16_t word; uint8_t fc; };
const int FETCH_BUF_SIZE = 8;
FetchEntry fetch_buf[FETCH_BUF_SIZE];
int fetch_buf_len = 0;

static inline const char* fc_name_for(uint8_t fc) {
    return (fc == 6) ? "SP" : (fc == 5) ? "SD" : (fc == 2) ? "UP" : (fc == 1) ? "UD" : "??";
}

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

// Ad-hoc boot diagnostics are useful when chasing a specific failure, but
// they produce very large logs on long headless runs.
bool verbose_debug_enable = false;
bool poll268_debug_enable = false;
std::string scsi_disk_files[2];
std::string floppy_disk_files[2];

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
SimSerialTerminal serialTerminal;
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

static inline uint32_t tg68_reg(int idx) {
	return ((uint32_t)VERTOPINTERN->emu__DOT__tg68k_inst__DOT__tg68k__DOT__regfile_n2[idx] << 8) |
		VERTOPINTERN->emu__DOT__tg68k_inst__DOT__tg68k__DOT__regfile_n1[idx];
}

static void print_scsi_stop_state() {
	printf("SCSI state: mr=%02X icr=%02X tcr=%02X odr=%02X busdin=%02X req=%d tbsy=%02X treq=%02X "
	       "sd_rd=%02X sd_ack=%02X sd_wr=%d sd_addr=%02X "
	       "t0_phase=%d t0_mnt=%d t0_cnt=%u t0_done=%d t0_ack=%d t0_cmd=%d t0_din=%02X\n",
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__mr,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__tcr,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dout,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_req ? 1 : 0,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_bsy,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_req,
	       VERTOPINTERN->sd_rd,
	       VERTOPINTERN->sd_ack,
	       VERTOPINTERN->sd_buff_wr ? 1 : 0,
	       VERTOPINTERN->sd_buff_addr,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__phase,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__mounted ? 1 : 0,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_cnt,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_complete ? 1 : 0,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__ack ? 1 : 0,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd_cnt,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__din);
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

				// Filter extension words: buffer consecutive sequential fetches
				// and emit the oldest only when Musashi confirms instruction length.
				if (pc != cpu_trace_last_pc) {
					cpu_trace_last_pc = pc;

					// Non-sequential (branch/exception) → flush buffered entries
					// first, walking them as a chain of opcodes+extensions.
					bool sequential = (fetch_buf_len > 0) &&
						(pc == fetch_buf[fetch_buf_len-1].pc + 2);

					if (!sequential && fetch_buf_len > 0) {
						int i = 0;
						while (i < fetch_buf_len) {
							FetchEntry &e = fetch_buf[i];
							unsigned short opwords[5] = {0};
							int avail = fetch_buf_len - i;
							for (int k = 0; k < avail && k < 5; k++)
								opwords[k] = fetch_buf[i+k].word;
							unsigned int len = 2;
							const char* disasm = disassemble_68k_ext_len(e.pc, opwords, avail, &len);
							if (len < 2) len = 2;
							int words = len / 2;
							cpu_trace_count++;
							console.AddLog("%08X: %04X  %s", e.pc, e.word, disasm);
							if (cpu_trace_file) {
								fprintf(cpu_trace_file, "%s %08X: %04X  %s\n", fc_name_for(e.fc), e.pc, e.word, disasm);
							}
							i += words;
						}
						fetch_buf_len = 0;
					}

					// Append this fetch to the buffer.
					if (fetch_buf_len < FETCH_BUF_SIZE) {
						fetch_buf[fetch_buf_len++] = { pc, opcode, fc };
					} else {
						// Buffer full — emit oldest then shift (shouldn't happen:
						// longest 68020 instruction is 11 words, we buffer 8).
						FetchEntry &e = fetch_buf[0];
						unsigned short opwords[5] = {0};
						for (int k = 0; k < 5; k++) opwords[k] = fetch_buf[k].word;
						unsigned int len = 2;
						const char* disasm = disassemble_68k_ext_len(e.pc, opwords, 5, &len);
						if (len < 2) len = 2;
						int words = len / 2;
						if (words > FETCH_BUF_SIZE) words = FETCH_BUF_SIZE;
						cpu_trace_count++;
						console.AddLog("%08X: %04X  %s", e.pc, e.word, disasm);
							if (cpu_trace_file) {
								fprintf(cpu_trace_file, "%s %08X: %04X  %s\n", fc_name_for(e.fc), e.pc, e.word, disasm);
							}
						int keep = fetch_buf_len - words;
						for (int k = 0; k < keep; k++) fetch_buf[k] = fetch_buf[k + words];
						fetch_buf_len = keep;
						fetch_buf[fetch_buf_len++] = { pc, opcode, fc };
					}

					if (cpu_trace_max > 0 && cpu_trace_count >= cpu_trace_max && cpu_trace_file) {
						fprintf(stderr, "CPU trace limit reached (%d instructions)\n", cpu_trace_max);
						fclose(cpu_trace_file);
						cpu_trace_file = nullptr;
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

		// Serial terminal: tick soft UART every rising edge
		if (clk_sys.IsRising()) {
			bool fpga_txd = VERTOPINTERN->serial_txd;
			// Debug: log txd transitions
			static bool last_txd = true;
			if (verbose_debug_enable && fpga_txd != last_txd) {
				fprintf(stderr, "SERIAL_TXD: %d->%d at cycle %llu\n",
						last_txd ? 1 : 0, fpga_txd ? 1 : 0, (unsigned long long)main_time);
			}
			last_txd = fpga_txd;
			bool sim_rxd = serialTerminal.Tick(fpga_txd);
			VERTOPINTERN->serial_rxd = sim_rxd;

			// Auto-update baud config from SCC baud rate divider
			static uint32_t last_baud_div = 0;
			uint32_t baud_div = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__baud_divid_speed_a;
			if (baud_div != last_baud_div) {
				serialTerminal.UpdateConfigDirect(baud_div, 8, 1, false, false);
				last_baud_div = baud_div;
			}
		}

		// Output pixels on rising edge of pixel clock
		if (clk_sys.IsRising() && VERTOPINTERN->CE_PIXEL) {
			uint32_t colour = 0xFF000000 | VERTOPINTERN->VGA_B << 16 | VERTOPINTERN->VGA_G << 8 | VERTOPINTERN->VGA_R;
			video.Clock(VERTOPINTERN->VGA_HB, VERTOPINTERN->VGA_VB, VERTOPINTERN->VGA_HS, VERTOPINTERN->VGA_VS, colour);
		}

		if (clk_sys.IsRising()) {
			main_time++;
			if (poll268_debug_enable && !*bus.ioctl_download) {
				static int poll268_log_count = 0;
				uint32_t pc = VERTOPINTERN->debug_pc;
				bool scsi_cycle = VERTOPINTERN->debug_cpuBusControl && VERTOPINTERN->debug_selectSCSI;
				bool scsi_rom_window = (pc >= 0x408268D0 && pc <= 0x40826990) ||
				                       (pc >= 0x40826CB6 && pc <= 0x40826D1C);
				if (poll268_log_count < 1200 && scsi_rom_window && scsi_cycle) {
					uint32_t d1 = tg68_reg(1);
					uint32_t d5 = tg68_reg(5);
					uint32_t d7 = tg68_reg(7);
					uint32_t a3 = tg68_reg(11);
					uint32_t a4 = tg68_reg(12);
					fprintf(stderr,
						"POLL268 @%llu pc=%08X op=%04X addr=%08X rw=%d fc=%d din=%04X dout=%04X "
						"bc=%d via=%d via2=%d scsi=%d scc=%d iwm=%d nubus=%d ram=%d rom=%d "
						"mr=%02X icr=%02X tcr=%02X odr=%02X busdin=%02X req=%d tbsy=%02X treq=%02X "
						"sd_rd=%02X sd_ack=%02X sd_wr=%d sd_addr=%02X "
						"t0_phase=%d t0_mnt=%d t0_din=%02X t0_ack=%d t0_cmd=%d t0_cnt=%u t0_done=%d t0_sel=%d t0_reqrd=%d "
						"t1_phase=%d t1_mnt=%d t1_cmd=%d "
						"arb=%d arb_count=%02X "
						"d1=%08X d5=%08X d7=%08X a3=%08X a4=%08X a3+10=%08X a3+20=%08X\n",
						(unsigned long long)main_time,
						pc,
						VERTOPINTERN->debug_opcode,
						VERTOPINTERN->debug_cpuAddr,
						VERTOPINTERN->debug_cpuRW,
						VERTOPINTERN->debug_fc,
						VERTOPINTERN->debug_cpuDataIn,
						VERTOPINTERN->debug_cpuDataOut,
						VERTOPINTERN->debug_cpuBusControl ? 1 : 0,
						VERTOPINTERN->debug_selectVIA ? 1 : 0,
						VERTOPINTERN->debug_selectVIA2 ? 1 : 0,
						VERTOPINTERN->debug_selectSCSI ? 1 : 0,
						VERTOPINTERN->debug_selectSCC ? 1 : 0,
						VERTOPINTERN->debug_selectIWM ? 1 : 0,
						VERTOPINTERN->debug_selectNuBus ? 1 : 0,
						VERTOPINTERN->debug_selectRAM ? 1 : 0,
						VERTOPINTERN->debug_selectROM ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__mr,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__tcr,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dout,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_req ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_bsy,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_req,
						VERTOPINTERN->sd_rd,
						VERTOPINTERN->sd_ack,
						VERTOPINTERN->sd_buff_wr ? 1 : 0,
						VERTOPINTERN->sd_buff_addr,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__phase,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__mounted ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__din,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__ack ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_complete ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__sd_buff_sel ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__req_rd ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__1__KET____DOT__target__DOT__phase,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__1__KET____DOT__target__DOT__mounted ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__1__KET____DOT__target__DOT__cmd_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__arb_active ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__arb_count,
						d1, d5, d7, a3, a4, a3 + 0x10, a3 + 0x20);
					poll268_log_count++;
				}
			}
			if (verbose_debug_enable) {
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
			// Dump PC stream in the stuck window: 250M..250M+20K
			{
				static uint32_t last_pc = 0;
				if (main_time >= 250000000ULL && main_time < 250020000ULL) {
					uint32_t pc = VERTOPINTERN->debug_pc;
					if (pc != last_pc && VERTOPINTERN->debug_fetch_valid) {
						fprintf(stderr, "PC_TRACE @%llu: PC=%08X op=%04X\n",
							(unsigned long long)main_time, pc,
							VERTOPINTERN->debug_opcode);
						last_pc = pc;
					}
				}
			}
			// PC histogram for the stuck 40802Exx/2Fxx/32xx window (active after cycle 200M)
			{
				static int pc_hits[0x400] = {0};
				static uint64_t last_dump = 0;
				if (main_time > 200000000ULL) {
					uint32_t pc = VERTOPINTERN->debug_pc;
					if (pc >= 0x40802E00 && pc < 0x40803200) {
						pc_hits[(pc - 0x40802E00) >> 1]++;
					}
					if (main_time - last_dump >= 50000000ULL) {
						last_dump = main_time;
						fprintf(stderr, "PC_HIST @%llu: top10:\n", (unsigned long long)main_time);
						for (int k = 0; k < 10; k++) {
							int best = -1, best_v = 0;
							for (int i = 0; i < 0x400; i++) {
								if (pc_hits[i] > best_v) { best_v = pc_hits[i]; best = i; }
							}
							if (best < 0 || best_v == 0) break;
							fprintf(stderr, "  PC=%08X hits=%d\n", 0x40802E00 + (best<<1), best_v);
							pc_hits[best] = -1;
						}
						for (int i = 0; i < 0x400; i++) if (pc_hits[i] < 0) pc_hits[i] = 0;
					}
				}
			}
			// BTST #5 polling loop trace
			{
				static uint32_t btst_ea = 0xFFFFFFFF;
				static int btst_log = 0;
				static int btst_wlog = 0;
				uint32_t pc = VERTOPINTERN->debug_pc;
				if ((pc == 0x40806DD8 || pc == 0x40806DDA || pc == 0x40806DDC) && VERTOPINTERN->debug_cpuRW) {
					uint32_t ea = VERTOPINTERN->debug_cpuAddr;
					// Non-ROM address = operand effective address
					if ((ea & 0xFF000000) != 0x40000000 && ea < 0x40000000) {
						if (btst_log < 6 || ea != btst_ea) {
							fprintf(stderr, "BTST_LOOP @%llu: PC=%08X read EA=%08X data=%04X fc=%d\n",
								(unsigned long long)main_time, pc, ea,
								VERTOPINTERN->debug_cpuDataOut,
								VERTOPINTERN->debug_fc);
							btst_ea = ea;
						}
						btst_log++;
					}
				}
				if (btst_ea != 0xFFFFFFFF && VERTOPINTERN->debug_write_valid) {
					uint32_t wa = VERTOPINTERN->debug_write_addr;
					if ((wa & ~1u) == (btst_ea & ~1u) && btst_wlog < 20) {
						fprintf(stderr, "BTST_LOOP_WR @%llu: write addr=%08X data=%04X PC=%08X\n",
							(unsigned long long)main_time, wa,
							VERTOPINTERN->debug_write_data, pc);
						btst_wlog++;
					}
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
				uint8_t txip = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__tx_irq_pend_a;
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
					uint8_t rxlatch = VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__rx_wr_a_r;
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
			// PC trace window 70M-182M: log unique PC values to find failure path
			if (main_time >= 14170000 && main_time < 14300000) {
				static uint32_t last_trace_pc = 0;
				uint32_t cur_pc = VERTOPINTERN->debug_pc;
				if (cur_pc != last_trace_pc && VERTOPINTERN->debug_fetch_valid && !*bus.ioctl_download) {
					fprintf(stderr, "PCTRACE %llu: PC=%08X addr=%08X RW=%d BERR=%d\n",
						(unsigned long long)main_time,
						cur_pc,
						VERTOPINTERN->debug_cpuAddr,
						VERTOPINTERN->debug_cpuRW,
						VERTOPINTERN->debug_berr ? 1 : 0);
					last_trace_pc = cur_pc;
				}
			}
			// Boot decision watchpoints - log key PC values to stderr
			if (VERTOPINTERN->debug_fetch_valid && !*bus.ioctl_download) {
				uint32_t pc = VERTOPINTERN->debug_pc;

				// Key startup path watchpoints
				if (pc == 0x40800694)
					fprintf(stderr, "*** EXCEPTION HANDLER at cycle %llu addr=%08X ***\n",
						(unsigned long long)main_time, VERTOPINTERN->debug_cpuAddr);
				if (pc == 0x4080009A)
					fprintf(stderr, "*** STARTINIT1 ENTRY at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x40802B82)
					fprintf(stderr, "*** BTST #26,D7 (loopback decision) at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x40802BAA)
					fprintf(stderr, "*** NORMAL BOOT JUMP (jmp 0x9A) at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x40802E96)
					fprintf(stderr, "*** TMENTRY1 at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x40802C3C)
					fprintf(stderr, "*** ERROR1HANDLER ENTRY at cycle %llu ***\n", (unsigned long long)main_time);
				// RAM test entry: $2BBC = ROM offset, full PC = $40802BBC
				if (pc == 0x40802BBC)
					fprintf(stderr, "*** RAM_TEST ENTRY at cycle %llu addr=%08X ***\n",
						(unsigned long long)main_time, VERTOPINTERN->debug_cpuAddr);
				// RAM test return (after MOVEM restore): watch for d6!=0
				if (pc == 0x40802C28)
					fprintf(stderr, "*** RAM_TEST EXIT at cycle %llu ***\n",
						(unsigned long long)main_time);
				// Log non-ROM, non-video data bus reads/writes during RAM test window
				static bool in_ramtest = false;
				if (pc == 0x40802BBC) in_ramtest = true;
				if (pc == 0x40802C28 || pc == 0x40802C3C) in_ramtest = false;
				if (in_ramtest && main_time > 14182000 && (main_time % 128 < 8)) {
					uint32_t addr = VERTOPINTERN->debug_cpuAddr;
					bool rw = VERTOPINTERN->debug_cpuRW;
					bool selram = VERTOPINTERN->debug_selectRAM;
					if (selram)
						fprintf(stderr, "RAMTEST_BUS cycle=%llu: addr=%08X %s selRAM=%d\n",
							(unsigned long long)main_time, addr, rw ? "RD" : "WR", selram);
				}

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
				// (Error1Handler watchpoint moved above)
				// SCC polling loop
				if (pc == 0x40803296)
					fprintf(stderr, "*** SCC POLL LOOP ENTRY at cycle %llu ***\n", (unsigned long long)main_time);
				// bset #17,D7 after SCC init
				if (pc == 0x40803414) {
					static int bset17_count = 0;
					if (bset17_count++ < 5)
						fprintf(stderr, "*** BSET #17,D7 at cycle %llu ***\n", (unsigned long long)main_time);
				}
				// btst #17,D7 in SCC poll
				if (pc == 0x4080329A) {
					static int btst17_count = 0;
					if (btst17_count++ < 5)
						fprintf(stderr, "*** BTST #17,D7 (SCC poll) at cycle %llu ***\n", (unsigned long long)main_time);
				}
				// Bus error handler at $2906
				if (pc == 0x40802906)
					fprintf(stderr, "*** BUS ERROR HANDLER at cycle %llu ***\n", (unsigned long long)main_time);

				// --- Exception-into-debug-shell investigation ---
				// Track the previous "normal" PC so we can identify the faulting
				// instruction when the CPU jumps to the POST exception chain
				// at $408020F8-$40802114.
				static uint32_t prev_pc = 0;
				static int excpt_log_count = 0;
				bool in_excpt_entry = (pc >= 0x408020F8 && pc <= 0x40802114);
				if (in_excpt_entry && excpt_log_count < 16) {
					fprintf(stderr, "*** EXCPT_ENTRY pc=%08X (offset=%d) prev_pc=%08X cycle=%llu cpuAddr=%08X dataIn=%04X dataOut=%04X RW=%d FC=%d ***\n",
						pc, (int)(pc - 0x408020F8), prev_pc,
						(unsigned long long)main_time,
						VERTOPINTERN->debug_cpuAddr,
						VERTOPINTERN->debug_cpuDataIn,
						VERTOPINTERN->debug_cpuDataOut,
						VERTOPINTERN->debug_cpuRW,
						VERTOPINTERN->debug_fc);
					excpt_log_count++;
				}
				// Update prev_pc only with non-exception-handler PCs so the
				// log shows the faulting code, not the handler trampoline.
				if (!in_excpt_entry && pc != 0)
					prev_pc = pc;

				// Log boot-init checkpoints between InitZone and the magic check
				// so we know which trap/instruction precedes the exception.
				if (pc == 0x408001B8)
					fprintf(stderr, "*** BOOT $1B8 _InitZone trap at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x408001C2)
					fprintf(stderr, "*** BOOT $1C2 jsr NewPtrSysClear at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x408001C8)
					fprintf(stderr, "*** BOOT $1C8 bsr 40800D9E (magic-setter chain) at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x40800D9E)
					fprintf(stderr, "*** BOOT $D9E reached (magic-setter outer) at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x408008AE)
					fprintf(stderr, "*** BOOT $8AE reached (writes 5A932BC7 magic) at cycle %llu ***\n", (unsigned long long)main_time);
				if (pc == 0x40801E1C)
					fprintf(stderr, "*** BOOT $1E1C magic check at cycle %llu ***\n", (unsigned long long)main_time);
			}

			// Watch CPU writes to $0AF0 (exception code), $0C70 (saved PC),
			// $0C74 (saved SR) — these record what the POST handler captured.
			if (VERTOPINTERN->debug_cpuBusControl && !VERTOPINTERN->debug_cpuRW &&
			    !*bus.ioctl_download) {
				uint32_t addr = VERTOPINTERN->debug_cpuAddr & 0x00FFFFFF;
				if (addr == 0x000AF0 || addr == 0x000AF1 ||
				    addr == 0x000C70 || addr == 0x000C71 ||
				    addr == 0x000C72 || addr == 0x000C73 ||
				    addr == 0x000C74 || addr == 0x000C75) {
					static int wr_log_count = 0;
					if (wr_log_count < 32) {
						fprintf(stderr, "*** EXCPT_SAVE wr addr=%08X data=%04X cycle=%llu pc=%08X ***\n",
							addr, VERTOPINTERN->debug_cpuDataIn,
							(unsigned long long)main_time,
							VERTOPINTERN->debug_pc);
						wr_log_count++;
					}
				}
				// Vector 2 (Bus Error) at $00000008..$0000000B - track every
				// write so we can see whether Slot Manager's catcher is installed
				// at the time the BERR fires (vs POST handler).
				if (addr >= 0x000008 && addr <= 0x00000B) {
					static int vec2_log_count = 0;
					if (vec2_log_count < 4096) {
						fprintf(stderr, "*** VEC2_WR addr=%08X data=%04X cycle=%llu pc=%08X ***\n",
							addr, VERTOPINTERN->debug_cpuDataIn,
							(unsigned long long)main_time,
							VERTOPINTERN->debug_pc);
						vec2_log_count++;
					}
				}
			}

			// BERR rising-edge log: which PC, address, FC asserted bus error.
			{
				static int last_berr = 0;
				static int berr_log_count = 0;
				int berr_now = VERTOPINTERN->debug_berr ? 1 : 0;
				if (berr_now && !last_berr && berr_log_count < 32) {
					fprintf(stderr, "*** BERR_EDGE cycle=%llu pc=%08X cpuAddr=%08X FC=%d ***\n",
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						VERTOPINTERN->debug_cpuAddr,
						VERTOPINTERN->debug_fc);
					berr_log_count++;
				}
				last_berr = berr_now;
			}

			// ===================================================================
			// KMAP pointer corruption watchpoint (added 2026-04-20)
			// Per docs/bootproblems.md: $40807880 calls _GetResource('KMAP'),
			// $40807888 stores master pointer via `move.l (A0),(A2)`, and later
			// $4080757A reads (A2) and finds it corrupted. Find what writes to
			// (A2)'s target address between store and read.
			// ===================================================================
			{
				static uint32_t kmap_mptr_addr = 0;     // address written at $40807888
				static uint32_t kmap_mptr_value = 0;    // original master ptr
				static uint64_t kmap_store_cycle = 0;
				static bool kmap_armed = false;
				static int kmap_hi_latch_valid = 0;
				static uint32_t kmap_hi_latch_val = 0;

				// Capture the store at $40807888. The RTL writes each word twice
				// (we see duplicates in VEC2_WR), so de-dup by cycle+pc.
				if (VERTOPINTERN->debug_cpuBusControl && !VERTOPINTERN->debug_cpuRW &&
				    !*bus.ioctl_download) {
					uint32_t pc = VERTOPINTERN->debug_pc;
					uint32_t waddr = VERTOPINTERN->debug_cpuAddr;
					uint16_t wdata = VERTOPINTERN->debug_cpuDataIn;
					// The store instruction is at $40807888 — next fetch PC
					// after this instruction will be seen as debug_pc.
					// Cover likely surrounding PCs.
					if (pc >= 0x40807880 && pc <= 0x40807890) {
						static uint64_t last_log_cycle = 0;
						if (main_time - last_log_cycle > 4) {
							fprintf(stderr, "[KMAP] write @ pc=%08X waddr=%08X wdata=%04X cycle=%llu\n",
								pc, waddr, wdata, (unsigned long long)main_time);
							last_log_cycle = main_time;
						}
						// Longword write = two word writes to addr and addr+2
						// Capture both halves and reconstruct the longword.
						if (!kmap_armed) {
							// Heuristic: first write is high word, second is low word.
							if (!kmap_hi_latch_valid) {
								kmap_hi_latch_val = ((uint32_t)wdata) << 16;
								kmap_mptr_addr = waddr;
								kmap_hi_latch_valid = 1;
							} else {
								kmap_mptr_value = kmap_hi_latch_val | wdata;
								kmap_store_cycle = main_time;
								kmap_armed = true;
								kmap_hi_latch_valid = 0;
								fprintf(stderr, "[KMAP] STORE complete: (A2)=%08X <- %08X cycle=%llu\n",
									kmap_mptr_addr, kmap_mptr_value,
									(unsigned long long)kmap_store_cycle);
							}
						}
					}

					// Once armed, watch every write to the target address (and ±2)
					if (kmap_armed) {
						if (waddr >= kmap_mptr_addr && waddr <= kmap_mptr_addr + 3) {
							static int kmap_hit = 0;
							if (kmap_hit < 200) {
								fprintf(stderr, "[KMAP] TGT_WR waddr=%08X wdata=%04X cycle=%llu pc=%08X\n",
									waddr, wdata,
									(unsigned long long)main_time, pc);
								kmap_hit++;
							}
						}
					}
				}

				// Log the read at $4080757A / $4080757C area
				if (VERTOPINTERN->debug_fetch_valid && !*bus.ioctl_download) {
					uint32_t pc = VERTOPINTERN->debug_pc;
					if (pc == 0x4080757A || pc == 0x4080757C) {
						static uint64_t last_rd_log = 0;
						if (main_time - last_rd_log > 4) {
							fprintf(stderr, "[KMAP] READ_FETCH pc=%08X cycle=%llu (A2_mptr was %08X at cycle %llu, stored at (A2)=%08X)\n",
								pc, (unsigned long long)main_time,
								kmap_mptr_value, (unsigned long long)kmap_store_cycle,
								kmap_mptr_addr);
							last_rd_log = main_time;
						}
					}
				}
			}

			// ===================================================================
			// BERR/RTE frame instrumentation (added 2026-04-20)
			// Captures exception frame pushes after BERR and frame pops on RTE.
			// Goal: verify format $B push count vs RTE pop count, detect
			// POST-handler SP+=6 leaving residue on stack.
			// ===================================================================
			{
				enum Phase { IDLE, PUSHING, RUNNING, POPPING };
				static Phase phase = IDLE;
				static int last_berr2 = 0;
				static int push_count = 0;
				static int pop_count = 0;
				static uint32_t fault_pc = 0;
				static uint32_t fault_addr = 0;
				static int fault_fc = 0;
				static uint64_t fault_cycle = 0;
				static int session_id = 0;
				static int last_fetch_valid = 0;
				bool bi_active = true;
				int berr_now = VERTOPINTERN->debug_berr ? 1 : 0;

				if (bi_active) {
					// Rising BERR: snapshot fault info, enter PUSHING
					if (berr_now && !last_berr2) {
						fault_pc    = VERTOPINTERN->debug_pc;
						fault_addr  = VERTOPINTERN->debug_cpuAddr;
						fault_fc    = VERTOPINTERN->debug_fc;
						fault_cycle = main_time;
						push_count  = 0;
						pop_count   = 0;
						session_id++;
						phase = PUSHING;
						fprintf(stderr, "[BI#%d] BERR cycle=%llu pc=%08X addr=%08X FC=%d\n",
							session_id, (unsigned long long)fault_cycle,
							fault_pc, fault_addr, fault_fc);
					}
					last_berr2 = berr_now;

					// In PUSHING phase: count all writes (frame pushes).
					// debug_fc reflects the last instruction fetch only, so we can't
					// filter by FC here. Assume writes during this window are pushes.
					if (phase == PUSHING && VERTOPINTERN->debug_write_valid) {
						uint32_t waddr = VERTOPINTERN->debug_write_addr;
						uint16_t wdata = VERTOPINTERN->debug_write_data;
						if (push_count < 60) {
							fprintf(stderr, "[BI#%d] push#%02d @%08X = %04X\n",
								session_id, push_count, waddr, wdata);
						}
						push_count++;
					}

					// After PUSHING, look for handler starting: instruction fetch
					// at new PC means we're running the handler now.
					if (phase == PUSHING && VERTOPINTERN->debug_fetch_valid && !last_fetch_valid) {
						uint32_t pc = VERTOPINTERN->debug_pc;
						if (pc != fault_pc && push_count >= 4) {
							fprintf(stderr, "[BI#%d] HANDLER_ENTRY pc=%08X pushes=%d (expect 23 for fmt$B)\n",
								session_id, pc, push_count);
							phase = RUNNING;
						}
					}

					// In RUNNING phase: log each new PC (up to N), watch for RTE
					if (phase == RUNNING && VERTOPINTERN->debug_fetch_valid && !last_fetch_valid) {
						uint16_t op = VERTOPINTERN->debug_opcode;
						uint32_t pc = VERTOPINTERN->debug_pc;
						static uint32_t last_hpc = 0;
						static int hpc_count = 0;
						if (pc != last_hpc) {
							if (hpc_count < 120) {
								fprintf(stderr, "[BI#%d] handler_pc=%08X op=%04X\n",
									session_id, pc, op);
							}
							hpc_count++;
							last_hpc = pc;
						}
						if (op == 0x4E73) {
							fprintf(stderr, "[BI#%d] RTE_FETCH pc=%08X\n",
								session_id, VERTOPINTERN->debug_pc);
							pop_count = 0;
							phase = POPPING;
						}
					}

					// In POPPING phase: timeout after N cycles or on first instruction
					// fetch from new PC (meaning RTE completed). We don't have a
					// clean per-cycle read strobe, so rely on fetch boundary.
					if (phase == POPPING) {
						static uint64_t pop_start_cycle = 0;
						if (pop_start_cycle == 0) pop_start_cycle = main_time;
						if (VERTOPINTERN->debug_fetch_valid && !last_fetch_valid) {
							uint32_t pc = VERTOPINTERN->debug_pc;
							fprintf(stderr, "[BI#%d] POST_RTE_FETCH pc=%08X (pushes=%d)\n",
								session_id, pc, push_count);
							phase = IDLE;
							pop_start_cycle = 0;
						} else if (main_time - pop_start_cycle > 5000) {
							fprintf(stderr, "[BI#%d] POP_TIMEOUT no fetch seen (pushes=%d)\n",
								session_id, push_count);
							phase = IDLE;
							pop_start_cycle = 0;
						}
					}

					last_fetch_valid = VERTOPINTERN->debug_fetch_valid ? 1 : 0;
				}
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
	printf("  --no-cpu-trace                Disable CPU trace logging\n");
	printf("  --no-via-debug                Disable VIA debug logging\n");
	printf("  --verbose-debug               Enable ad-hoc boot diagnostics on stderr\n");
	printf("  +poll268_debug, --poll268-debug\n");
	printf("                                Trace the ROM wait loop around PC 408268F8\n");
	printf("  --scsi0 <file>                Mount a SCSI disk image on target 0 (ID 6)\n");
	printf("  --scsi1 <file>                Mount a SCSI disk image on target 1 (ID 5)\n");
	printf("  --floppy0 <file>              Insert a raw .dsk image in the internal floppy drive\n");
	printf("  --floppy1 <file>              Insert a raw .dsk image in the external floppy drive\n");
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
		} else if (strcmp(argv[i], "--no-cpu-trace") == 0) {
			cpu_trace_enable = false;
		} else if (strcmp(argv[i], "--no-via-debug") == 0) {
			via_debug_enable = false;
		} else if (strcmp(argv[i], "--verbose-debug") == 0) {
			verbose_debug_enable = true;
		} else if (strcmp(argv[i], "+poll268_debug") == 0 || strcmp(argv[i], "--poll268-debug") == 0) {
			poll268_debug_enable = true;
		} else if (strcmp(argv[i], "--scsi0") == 0 && i + 1 < argc) {
			scsi_disk_files[0] = argv[i + 1];
			i++;
		} else if (strcmp(argv[i], "--scsi1") == 0 && i + 1 < argc) {
			scsi_disk_files[1] = argv[i + 1];
			i++;
		} else if (strcmp(argv[i], "--floppy0") == 0 && i + 1 < argc) {
			floppy_disk_files[0] = argv[i + 1];
			i++;
		} else if (strcmp(argv[i], "--floppy1") == 0 && i + 1 < argc) {
			floppy_disk_files[1] = argv[i + 1];
			i++;
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
	for (int disk_index = 0; disk_index < 2; disk_index++) {
		if (!scsi_disk_files[disk_index].empty()) {
			blockdevice.MountDisk(scsi_disk_files[disk_index], disk_index);
		}
	}

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

	// Setup video output. Headless mode still needs the framebuffer because
	// video.Clock() writes pixels and frame counters into SimVideo state.
	if (headless) {
		if (video.InitialiseHeadless() == 1) { return 1; }
	} else if (video.Initialise(windowTitle) == 1) {
		return 1;
	}

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
	for (int disk_index = 0; disk_index < 2; disk_index++) {
		if (!floppy_disk_files[disk_index].empty()) {
			int ioctl_index = disk_index == 0 ? 2 : 3;
			bus.QueueDownload(floppy_disk_files[disk_index], ioctl_index, 1);
			fprintf(stderr, "Loading floppy%d image: %s\n", disk_index, floppy_disk_files[disk_index].c_str());
		}
	}

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
		if (headless) {
			unsigned long mouse_temp = mouse_clock ? (1UL << 24) : 0;
			mouse_clock = !mouse_clock;
			VERTOPINTERN->ps2_mouse = mouse_temp;

			if (run_enable) {
				for (int step = 0; step < batchSize; step++) { verilate(); }
			}
			else {
				if (single_step) { verilate(); }
				if (multi_step) {
					for (int step = 0; step < multi_step_amount; step++) { verilate(); }
				}
			}

			bool took_screenshot_this_frame = false;
			if (screenshot_mode) {
				auto it = std::find(screenshot_frames.begin(), screenshot_frames.end(), video.count_frame);
				if (it != screenshot_frames.end()) {
					save_screenshot(video.count_frame);
					screenshot_frames.erase(it);
					took_screenshot_this_frame = true;
				}
			}

			if (stop_at_frame_enabled && video.count_frame >= stop_at_frame) {
				if (took_screenshot_this_frame) {
					printf("Reached stop frame %d after taking screenshot, exiting... PC=%08X Op=%04X VBR=%08X\n",
						stop_at_frame,
						VERTOPINTERN->debug_pc,
						VERTOPINTERN->debug_opcode,
						VERTOPINTERN->debug_vbr);
				} else {
					printf("Reached stop frame %d, exiting... PC=%08X Op=%04X VBR=%08X\n",
						stop_at_frame,
						VERTOPINTERN->debug_pc,
						VERTOPINTERN->debug_opcode,
						VERTOPINTERN->debug_vbr);
				}
				print_scsi_stop_state();
				break;
			}

			continue;
		}

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

		// Serial terminal window — update SCC status for init indicator
		serialTerminal.UpdateSCCStatus(
			VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr3_a,
			VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr5_a,
			VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr9,
			VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr14_a);
		static bool showSerial = true;
		serialTerminal.Draw("Serial Terminal A", &showSerial);

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
				printf("Reached stop frame %d after taking screenshot, exiting... PC=%08X Op=%04X VBR=%08X\n",
					stop_at_frame,
					VERTOPINTERN->debug_pc,
					VERTOPINTERN->debug_opcode,
					VERTOPINTERN->debug_vbr);
			} else {
				printf("Reached stop frame %d, exiting... PC=%08X Op=%04X VBR=%08X\n",
					stop_at_frame,
					VERTOPINTERN->debug_pc,
					VERTOPINTERN->debug_opcode,
					VERTOPINTERN->debug_vbr);
			}
			print_scsi_stop_state();
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
	if (headless) {
		video.CleanUpHeadless();
	} else {
		video.CleanUp();
	}
	input.CleanUp();

	return 0;
}
