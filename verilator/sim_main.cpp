#include <verilated.h>
#include <verilated_save.h>
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
#include <cstring>
using namespace std;

#ifndef _MSC_VER
extern SDL_Window* window;
#endif

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
// Mac II only (uses TG68K 68020 mode)
// TG68K documents cpu=2'b11 as 68020 mode. The Mac II ROM depends on it.
int cfg_cpuType = 3;
int cfg_memSize = 3;       // RAM size: 0=1MB, 1=2MB, 2=4MB, 3=8MB (set via --ram)
const char* rom_file_override = nullptr;  // --rom <file> overrides the boot0 ROM (e.g. the no-memtest fast-boot ROM)

// CPU trace
// ---------
bool cpu_trace_enable = true;  // Disabled by default for speed; toggle in GUI
bool cpu_trace_started = false;  // Wait for ROM load and reset
FILE* cpu_trace_file = nullptr;
const char* cpu_trace_filename = "cpu_trace.log";
int cpu_trace_count = 0;
const int cpu_trace_max = 0;  // 0 = unlimited
int cpu_trace_min_frame = 0;  // --cpu-trace-min-frame: suppress trace output before this frame
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
bool scsi_debug_enable = false;
bool scsi_timeout_loop_debug_enable = false;
bool scsi_stall_history_enable = false;
uint32_t scsi_stall_dreq_run = 0;
bool scsi_stall_dumped = false;
bool iwm_debug_enable = false;
bool wait_debug_enable = false;
bool calib_debug_enable = false;
bool calib_loop_debug_enable = false;
bool ramtest_debug_enable = false;
bool scc_bus_debug_enable = false;
bool ram_size_cpu_debug_enable = false;
bool iwm_state_debug_enable = false;
bool boot_decision_debug_enable = false;
// Heap-spray watch (2026-07-15, LBMacTwo driver-corruption forensics): log
// completed CPU writes into low RAM [0x2000,0x8000) issued by RAM-resident
// code (PC in the same window) — the Slot Manager's RAM-copied VRAM-sizing
// probe writes AAAA/5555 there on the FPGA, killing the on-disk driver image.
bool heapspray_debug_enable = false;
int heapspray_debug_count = 0;
const int heapspray_debug_max = 6000;
// --watch-range LO:HI[:MINFRAME] — generic RAM write-watch (2026-07-16)
bool watch_range_enable = false;
uint32_t watch_range_lo = 0, watch_range_hi = 0;
int watch_range_min_frame = 0;
int watch_range_count = 0;
const int watch_range_max = 12000;
bool heapspray_prev_write_valid = false;
bool heapspray_asc_prev_write_valid = false;
// Driver-image forensics (2026-07-15e): mirror of Snow's heapwatch. drv_exec
// arms on the first instruction fetch inside the loaded driver image; the
// heapspray write-watch then covers the WHOLE image (healthy baseline from
// Snow: ~7 vector-patch stores at +0x1F7C.. plus one byte at +0x17AC, nothing
// else). --drvtrace additionally logs every driver-window fetch (PC stream)
// for an instruction-level diff against Snow's healthy run.
bool sim_drv_exec = false;
bool drvtrace_enable = false;
long drvtrace_count = 0;
const long drvtrace_max = 6000000;
// Self-adapting driver base: the ROM SCSI boot loader NewPtr,SYS's a block,
// reads the driver into it, checksums it, and enters it with jsr (a3) at ROM
// 0x40807BB0. Capturing A3 at that fetch gives the true base (Snow: 0x4D50,
// HW: 0x522E, sim: varies with heap history) — the fixed 0x522E window arms
// on video-card sExec blocks instead (seen at frame 580: base 0x7360).
uint32_t drv_base = 0;   // 0 = not yet captured
bool bootmask_once_debug_enable = false;
bool bootmask_once_stop_requested = false;
bool scsi_transition_debug_enable = false;
bool scsi_transition_stop_requested = false;
int scsi_transition_debug_min_frame = 430;
bool late_adb_debug_enable = false;
bool late_adb_stop_requested = false;
int late_adb_debug_min_frame = 420;
bool bus_handshake_debug_enable = false;
int scsi_debug_count = 0;
const int scsi_debug_max = 2000;
int scsi_debug_min_frame = 0;
bool scsi_debug_prev_bus_control = false;
uint32_t scsi_debug_prev_t0_data_cnt = 0xFFFFFFFFu;
int scsi_debug_t0_data_count = 0;
const int scsi_debug_t0_data_max = 1600;
int scsi_debug_dma_count = 0;
const int scsi_debug_dma_max = 2200;
int scsi_timeout_loop_debug_count = 0;
const int scsi_timeout_loop_debug_max = 2000;
uint32_t scsi_timeout_loop_last_d5_word = 0xFFFFFFFF;
uint32_t scsi_timeout_loop_last_entry_sp = 0xFFFFFFFF;
uint32_t scsi_timeout_loop_last_entry_ret = 0xFFFFFFFF;
int iwm_debug_count = 0;
const int iwm_debug_max = 2000;
bool iwm_debug_prev_bus_control = false;
int iwm_debug_min_frame = 0;
int scc_bus_debug_count = 0;
const int scc_bus_debug_max = 800;
bool scc_bus_debug_prev_bus_control = false;
int ram_size_cpu_debug_count = 0;
const int ram_size_cpu_debug_max = 500;
uint32_t ram_size_cpu_debug_last_pc = 0xFFFFFFFF;
int iwm_state_debug_count = 0;
const int iwm_state_debug_max = 300;
uint32_t iwm_state_debug_last_pc = 0xFFFFFFFF;
int boot_decision_debug_count = 0;
const int boot_decision_debug_max = 900;
int boot_decision_debug_min_frame = 220;
uint32_t boot_decision_debug_last_key = 0xFFFFFFFF;
const int BOOTMASK_HISTORY_SIZE = 512;
struct BootmaskHistoryEntry {
	uint32_t pc;
	uint16_t op;
	int frame;
	uint32_t tick;
	uint32_t d0;
	uint32_t d1;
	uint32_t d2;
	uint32_t d3;
	uint32_t d4;
	uint32_t d5;
	uint32_t d6;
	uint32_t a0;
	uint32_t a1;
	uint32_t a2;
	uint32_t a3;
	uint32_t a4;
	uint32_t sp;
	uint32_t ret;
};
BootmaskHistoryEntry bootmask_history[BOOTMASK_HISTORY_SIZE];
int bootmask_history_pos = 0;
int bootmask_history_count = 0;
uint32_t bootmask_history_last_pc = 0xFFFFFFFF;
int lowmem_bit_debug_count = 0;
const int lowmem_bit_debug_max = 80;
uint64_t lowmem_bit_debug_last_time = 0;
bool lowmem_bit_debug_prev_write_valid = false;
int bus_handshake_debug_count = 0;
const int bus_handshake_debug_max = 2500;
int bus_handshake_debug_min_frame = 0;
bool bus_handshake_debug_prev_as = true;
bool bus_handshake_debug_prev_vpa = true;
bool bus_handshake_debug_prev_dtack = true;
bool bus_handshake_debug_prev_vma = true;
bool bus_handshake_debug_prev_vpa_non_via = false;
bool nubus_video_debug_enable = false;
bool nubus_video_debug_full = false;
int nubus_video_debug_count = 0;
const int nubus_video_debug_max = 1000;
bool nubus_video_debug_prev_bus_control = false;
bool frame_probe_enable = false;
int frame_probe_interval = 10;
int frame_probe_last_frame = -1;
std::string scsi_disk_files[2];
std::string floppy_disk_files[2];
bool force_calib_enable = false;
uint16_t force_calib_0d00 = 0;
uint16_t force_calib_0da6 = 0;
int force_calib_min_frame = 0;
bool force_calib_reported = false;

// Screenshot functionality
// ------------------------
std::vector<int> screenshot_frames;
bool screenshot_mode = false;

// Stop at frame functionality
// ---------------------------
int stop_at_frame = -1;
bool stop_at_frame_enabled = false;
uint32_t stop_at_tick = 0;
bool stop_at_tick_enabled = false;
uint32_t stop_at_pc = 0;
bool stop_at_pc_enabled = false;
uint64_t unique_fetch_count = 0;
uint32_t unique_fetch_last_pc = 0xFFFFFFFF;
uint64_t profile_irq_assert_count[8] = {0};
uint64_t profile_irq_change_count = 0;
uint64_t profile_scsi_timeout_fetches = 0;
uint64_t profile_tick_wait_fetches = 0;
uint64_t profile_vbl_handler_fetches = 0;
uint64_t profile_lowmem_fetches = 0;
uint32_t profile_last_fetch_pc = 0xFFFFFFFF;
uint8_t profile_last_ipl = 7;
int wait_debug_count = 0;
const int wait_debug_max = 600;
uint32_t wait_debug_last_pc = 0xFFFFFFFF;
uint32_t wait_debug_last_tick = 0xFFFFFFFF;
int wait_debug_min_frame = 0;
int calib_debug_count = 0;
const int calib_debug_max = 1200;
bool calib_debug_prev_via_rd = false;
bool calib_debug_prev_via_wr = false;
bool calib_debug_prev_write_valid = false;
bool calib_debug_prev_via1_t1 = false;
bool calib_debug_prev_via2_t1 = false;
bool calib_debug_prev_via1_t2 = false;
uint32_t calib_debug_last_lowmem_tick = 0xFFFFFFFF;
uint32_t calib_loop_hits[3] = {0, 0, 0};
int calib_loop_debug_count = 0;
const int calib_loop_debug_max = 160;
int ramtest_debug_count = 0;
const int ramtest_debug_max = 260;
uint32_t ramtest_debug_last_pc = 0xFFFFFFFF;

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
extern SimClock clk_sys;

static inline uint16_t ram_word(uint32_t addr) {
	if (addr >= 0x01000000) {
		return 0xFFFF;
	}
	return VERTOPINTERN->emu__DOT__ram__DOT__mem[(addr >> 1) & 0x7FFFFF];
}

static inline void ram_write_word(uint32_t addr, uint16_t data) {
	if (addr >= 0x01000000) {
		return;
	}
	VERTOPINTERN->emu__DOT__ram__DOT__mem[(addr >> 1) & 0x7FFFFF] = data;
}

static inline uint32_t ram_long(uint32_t addr) {
	return ((uint32_t)ram_word(addr) << 16) | ram_word(addr + 2);
}

static inline uint8_t ram_byte(uint32_t addr) {
	uint16_t word = ram_word(addr & ~1U);
	return (addr & 1) ? (word & 0xFF) : (word >> 8);
}

static uint32_t find_ram_bytes(const uint8_t* bytes, size_t len, uint32_t start, uint32_t end) {
	if (!len || end < start || end - start + 1 < len) {
		return 0xFFFFFFFFU;
	}
	for (uint32_t addr = start; addr <= end - len + 1; addr += 2) {
		bool match = true;
		for (size_t i = 0; i < len; i++) {
			if (ram_byte(addr + i) != bytes[i]) {
				match = false;
				break;
			}
		}
		if (match) {
			return addr;
		}
	}
	return 0xFFFFFFFFU;
}

static inline uint32_t tg68_reg(int idx) {
	return ((uint32_t)VERTOPINTERN->emu__DOT__tg68k_inst__DOT__tg68k__DOT__regfile_n2[idx] << 8) |
		VERTOPINTERN->emu__DOT__tg68k_inst__DOT__tg68k__DOT__regfile_n1[idx];
}

static inline uint32_t lowmem_tick_016a() {
	return ((uint32_t)VERTOPINTERN->emu__DOT__ram__DOT__mem[0x00B5] << 16) |
		VERTOPINTERN->emu__DOT__ram__DOT__mem[0x00B6];
}

static inline bool lowmem_tick_reached() {
	uint32_t tick = lowmem_tick_016a();
	if (stop_at_tick <= 0xFFFF && (tick & 0xFFFF0000) != 0) {
		return false;
	}
	return tick >= stop_at_tick;
}

static bool stop_pc_reached() {
	return stop_at_pc_enabled &&
	       !*bus.ioctl_download &&
	       VERTOPINTERN->debug_fetch_valid &&
	       VERTOPINTERN->debug_pc == stop_at_pc;
}


static inline uint8_t scsi_debug_csr() {
	uint8_t mr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__mr;
	uint8_t icr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr;
	uint8_t target_bsy = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_bsy;
	// scsi_empty_cd is no longer instantiated (MacLC SCSI transplant 2026-08-08;
	// the real CD target replaces the stub and is compiled out via CDROM_PRESENT=0).
	bool empty_cd_bsy = false;
	bool scsi_bsy = (icr & 0x08) || target_bsy || empty_cd_bsy || (mr & 0x01);

	return ((icr & 0x80) ? 0x80 : 0x00) |
	       (scsi_bsy ? 0x40 : 0x00) |
	       (VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_req ? 0x20 : 0x00) |
	       (VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_msg ? 0x10 : 0x00) |
	       (VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_cd ? 0x08 : 0x00) |
	       (VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_io ? 0x04 : 0x00) |
	       ((icr & 0x04) ? 0x02 : 0x00);
}

static inline bool scsi_debug_pmatch() {
	uint8_t tcr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__tcr;

	return (((tcr >> 2) & 1) == (VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_msg ? 1 : 0)) &&
	       (((tcr >> 1) & 1) == (VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_cd ? 1 : 0)) &&
	       (((tcr >> 0) & 1) == (VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_io ? 1 : 0));
}

static inline uint8_t scsi_debug_bsr() {
	bool req = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_req;
	bool dma_en = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_en;
	bool pmatch = scsi_debug_pmatch();
	uint8_t icr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr;
	bool ack = (icr & 0x10) || VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_ack;

	return (req && dma_en ? 0x40 : 0x00) |
	       (req && dma_en && !pmatch ? 0x10 : 0x00) |
	       (pmatch ? 0x08 : 0x00) |
	       ((icr & 0x02) ? 0x02 : 0x00) |
	       (ack ? 0x01 : 0x00);
}

static void print_via_timer_state(FILE* out, const char* prefix) {
	fprintf(out,
		"%s via_tick=%u via_acc=%u "
		"VIA1 t1c=%04X t1l=%04X t2c=%04X t2l=%04X acr=%02X prb=%02X ddrb=%02X pb_i=%02X ifr=%02X ier=%02X "
		"t1ev=%u t1reload=%u t1may=%u t2ev=%u t2trig=%u t2to=%u pb7=%u ca1=%u ca2=%u "
		"VIA2 t1c=%04X t1l=%04X acr=%02X prb=%02X ddrb=%02X pb_o=%02X pb_i=%02X ifr=%02X ier=%02X "
		"ev=%u reload=%u may=%u pb7=%u ca1=%u\n",
		prefix,
		VERTOPINTERN->emu__DOT__dc0__DOT__via_timer_tick ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via_timer_acc,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_a_count,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_a_latch,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_b_count,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_b_latch,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__acr,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__pio_i_prb,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__pio_i_ddrb,
		VERTOPINTERN->emu__DOT__dc0__DOT__via_pb_i,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_flags,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_mask,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_a_event ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_a_reload ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_a_may_interrupt ? 1 : 0,
		((VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_events >> 5) & 1) ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_b_oneshot_trig ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_b_timeout ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_a_toggle ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__ca1_c ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__ca2_c ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__timer_a_count,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__timer_a_latch,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__acr,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__pio_i_prb,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__pio_i_ddrb,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2_pb_o,
		0xCF,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__irq_flags,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__irq_mask,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__timer_a_event ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__timer_a_reload ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__timer_a_may_interrupt ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__timer_a_toggle ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__ca1_c ? 1 : 0);
}

static void print_iwm_state_debug(uint32_t pc) {
	uint32_t ptr0134 = ram_long(0x0134);
	uint32_t a1 = tg68_reg(9);
	uint16_t d0w = tg68_reg(0) & 0xFFFF;
	uint16_t d1w = tg68_reg(1) & 0xFFFF;
	uint16_t d3w = tg68_reg(3) & 0xFFFF;

	fprintf(stderr,
		"IWM_STATE_DBG hit=%03d frame=%d tick=%08X time=%llu pc=%08X op=%04X "
		"D0=%08X D1=%08X D2=%08X D3=%08X A0=%08X A1=%08X L0134=%08X "
		"baseW00=%04X b03=%02X b04=%02X b05=%02X b12=%02X b18=%02X b19=%02X w1A=%04X w40=%04X "
		"bA1D0=%02X bA1D1=%02X bA1D3=%02X bA1D1p3=%02X bA1D1p4=%02X\n",
		iwm_state_debug_count,
		video.count_frame,
		lowmem_tick_016a(),
		(unsigned long long)main_time,
		pc,
		VERTOPINTERN->debug_opcode,
		tg68_reg(0),
		tg68_reg(1),
		tg68_reg(2),
		tg68_reg(3),
		tg68_reg(8),
		a1,
		ptr0134,
		ram_word(ptr0134 + 0x00),
		ram_byte(ptr0134 + 0x03),
		ram_byte(ptr0134 + 0x04),
		ram_byte(ptr0134 + 0x05),
		ram_byte(ptr0134 + 0x12),
		ram_byte(ptr0134 + 0x18),
		ram_byte(ptr0134 + 0x19),
		ram_word(ptr0134 + 0x1A),
		ram_word(ptr0134 + 0x40),
		ram_byte(a1 + d0w),
		ram_byte(a1 + d1w),
		ram_byte(a1 + d3w),
		ram_byte(a1 + d1w + 3),
		ram_byte(a1 + d1w + 4));
}

static bool boot_decision_pc(uint32_t pc) {
	switch (pc) {
	case 0x408015EA:
	case 0x40801600:
	case 0x4080174E:
	case 0x408017CC:
	case 0x408061E4:
	case 0x408061EE:
	case 0x408061F2:
	case 0x408061F4:
	case 0x408061F6:
	case 0x408061FA:
	case 0x40806200:
	case 0x40806208:
	case 0x40806218:
	case 0x4080622C:
	case 0x40806260:
	case 0x40806274:
	case 0x40806278:
	case 0x40806282:
	case 0x40806284:
	case 0x40807AD4:
	case 0x40807ADC:
	case 0x40807AE0:
	case 0x40807AE6:
	case 0x40807AE8:
	case 0x40807AEC:
	case 0x40807AF2:
	case 0x40807AF4:
	case 0x40807AF6:
	case 0x40807AF8:
	case 0x40807B08:
	case 0x40807B22:
	case 0x40807B26:
	case 0x40807B76:
	case 0x40807B7A:
	case 0x40807B8A:
	case 0x40807B8E:
	case 0x40807C20:
	case 0x40807C26:
	case 0x40807C28:
	case 0x40807C48:
	case 0x40807C4E:
	case 0x40807C50:
	case 0x40807C78:
	case 0x40807CA2:
	case 0x40807CA4:
	case 0x40807CAE:
	case 0x40807CB0:
	case 0x40807CC0:
	case 0x40807CC2:
	case 0x40807CDC:
	case 0x40807CF2:
	case 0x40807D18:
	case 0x40807D1C:
	case 0x4080DBE8:
	case 0x4080DC00:
	case 0x4080DC20:
	case 0x4080DC84:
	case 0x4080DC88:
	case 0x4080DC8E:
	case 0x408266A4:
	case 0x4082672A:
	case 0x40826756:
	case 0x4082675E:
	case 0x40826762:
	case 0x40826764:
	case 0x40826768:
	case 0x4082682C:
	case 0x40826832:
	case 0x40826850:
	case 0x40826870:
	case 0x40826874:
	case 0x408268CC:
	case 0x40826970:
	case 0x40826976:
	case 0x40826986:
	case 0x40826CB6:
	case 0x40826CD4:
	case 0x0082E80C:
	case 0x0082E950:
	case 0x0082E96E:
		return true;
	default:
		return false;
	}
}

static bool bootmask_once_pc(uint32_t pc) {
	uint32_t ret = ram_long(tg68_reg(15));
	return (pc >= 0x40807AD4 && pc <= 0x40807D20) ||
	       (pc >= 0x408266A4 && pc <= 0x408266CC) ||
	       (pc >= 0x40826756 && pc <= 0x40826990) ||
	       ((pc >= 0x40826CB6 && pc <= 0x40826CD4) && ret == 0x40826976);
}

static bool scsi_transition_pc(uint32_t pc) {
	uint32_t ret = ram_long(tg68_reg(15));
	return video.count_frame >= scsi_transition_debug_min_frame &&
	       ((pc >= 0x408266A4 && pc <= 0x408266CC) ||
	        (pc >= 0x4082682C && pc <= 0x40826990) ||
	        ((pc >= 0x40826CB6 && pc <= 0x40826CD4) && ret == 0x40826976));
}

static bool late_adb_pc(uint32_t pc) {
	return video.count_frame >= late_adb_debug_min_frame &&
	       (pc == 0x4080DD52 || pc == 0x4080DD78 || pc == 0x4080DD82 ||
	        pc == 0x4080DD8E || pc == 0x4080DDD6 || pc == 0x4080DE32);
}

static void record_bootmask_history(uint32_t pc) {
	if (pc == bootmask_history_last_pc) {
		return;
	}
	bootmask_history_last_pc = pc;

	uint32_t sp = tg68_reg(15);
	BootmaskHistoryEntry& entry = bootmask_history[bootmask_history_pos];
	entry.pc = pc;
	entry.op = VERTOPINTERN->debug_opcode;
	entry.frame = video.count_frame;
	entry.tick = lowmem_tick_016a();
	entry.d0 = tg68_reg(0);
	entry.d1 = tg68_reg(1);
	entry.d2 = tg68_reg(2);
	entry.d3 = tg68_reg(3);
	entry.d4 = tg68_reg(4);
	entry.d5 = tg68_reg(5);
	entry.d6 = tg68_reg(6);
	entry.a0 = tg68_reg(8);
	entry.a1 = tg68_reg(9);
	entry.a2 = tg68_reg(10);
	entry.a3 = tg68_reg(11);
	entry.a4 = tg68_reg(12);
	entry.sp = sp;
	entry.ret = ram_long(sp);

	bootmask_history_pos = (bootmask_history_pos + 1) % BOOTMASK_HISTORY_SIZE;
	if (bootmask_history_count < BOOTMASK_HISTORY_SIZE) {
		bootmask_history_count++;
	}
}

static void print_bootmask_once_debug(uint32_t pc) {
	fprintf(stderr,
		"BOOTMASK_ONCE trigger frame=%d tick=%08X time=%llu pc=%08X op=%04X "
		"D0=%08X D1=%08X D2=%08X D3=%08X D4=%08X D5=%08X D6=%08X D7=%08X "
		"A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X A5=%08X A6=%08X A7=%08X RET=%08X "
		"B0B22=%02X B0B2E=%02X B0C2F=%02X W017A=%04X W0D00=%04X W0DA6=%04X "
		"L08EE=%08X L0D10=%08X L0D14=%08X L030A=%08X\n",
		video.count_frame,
		lowmem_tick_016a(),
		(unsigned long long)main_time,
		pc,
		VERTOPINTERN->debug_opcode,
		tg68_reg(0),
		tg68_reg(1),
		tg68_reg(2),
		tg68_reg(3),
		tg68_reg(4),
		tg68_reg(5),
		tg68_reg(6),
		tg68_reg(7),
		tg68_reg(8),
		tg68_reg(9),
		tg68_reg(10),
		tg68_reg(11),
		tg68_reg(12),
		tg68_reg(13),
		tg68_reg(14),
		tg68_reg(15),
		ram_long(tg68_reg(15)),
		ram_byte(0x0B22),
		ram_byte(0x0B2E),
		ram_byte(0x0C2F),
		ram_word(0x017A),
		ram_word(0x0D00),
		ram_word(0x0DA6),
		ram_long(0x08EE),
		ram_long(0x0D10),
		ram_long(0x0D14),
		ram_long(0x030A));

	fprintf(stderr, "BOOTMASK_ONCE history count=%d newest_last=1\n", bootmask_history_count);
	int first = bootmask_history_pos - bootmask_history_count;
	if (first < 0) {
		first += BOOTMASK_HISTORY_SIZE;
	}
	for (int i = 0; i < bootmask_history_count; i++) {
		int idx = (first + i) % BOOTMASK_HISTORY_SIZE;
		const BootmaskHistoryEntry& entry = bootmask_history[idx];
		fprintf(stderr,
			"BOOTMASK_HIST %03d frame=%d tick=%08X pc=%08X op=%04X "
			"D0=%08X D1=%08X D2=%08X D3=%08X D4=%08X D5=%08X D6=%08X "
			"A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X SP=%08X RET=%08X\n",
			i,
			entry.frame,
			entry.tick,
			entry.pc,
			entry.op,
			entry.d0,
			entry.d1,
			entry.d2,
			entry.d3,
			entry.d4,
			entry.d5,
			entry.d6,
			entry.a0,
			entry.a1,
			entry.a2,
			entry.a3,
			entry.a4,
			entry.sp,
			entry.ret);
	}
}

static void print_scsi_transition_debug(uint32_t pc) {
	fprintf(stderr,
		"SCSI_TRANSITION trigger frame=%d tick=%08X time=%llu pc=%08X op=%04X "
		"D0=%08X D1=%08X D2=%08X D3=%08X D4=%08X D5=%08X D6=%08X D7=%08X "
		"A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X A5=%08X A6=%08X A7=%08X RET=%08X "
		"W017A=%04X B0B22=%02X B0B2E=%02X B0C2F=%02X W0D00=%04X W0DA6=%04X "
		"L08EE=%08X L0D10=%08X L0D14=%08X L030A=%08X "
		"Q_00=%08X Q_04=%04X Q_06=%04X Q_08=%04X Q_0A=%04X Q_0C=%08X "
		"SCSI mr=%02X icr=%02X tcr=%02X odr=%02X din=%02X req=%d tbsy=%02X treq=%02X\n",
		video.count_frame,
		lowmem_tick_016a(),
		(unsigned long long)main_time,
		pc,
		VERTOPINTERN->debug_opcode,
		tg68_reg(0),
		tg68_reg(1),
		tg68_reg(2),
		tg68_reg(3),
		tg68_reg(4),
		tg68_reg(5),
		tg68_reg(6),
		tg68_reg(7),
		tg68_reg(8),
		tg68_reg(9),
		tg68_reg(10),
		tg68_reg(11),
		tg68_reg(12),
		tg68_reg(13),
		tg68_reg(14),
		tg68_reg(15),
		ram_long(tg68_reg(15)),
		ram_word(0x017A),
		ram_byte(0x0B22),
		ram_byte(0x0B2E),
		ram_byte(0x0C2F),
		ram_word(0x0D00),
		ram_word(0x0DA6),
		ram_long(0x08EE),
		ram_long(0x0D10),
		ram_long(0x0D14),
		ram_long(0x030A),
		ram_long(ram_long(0x030A)),
		ram_word(ram_long(0x030A) + 0x04),
		ram_word(ram_long(0x030A) + 0x06),
		ram_word(ram_long(0x030A) + 0x08),
		ram_word(ram_long(0x030A) + 0x0A),
		ram_long(ram_long(0x030A) + 0x0C),
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__mr,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__tcr,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dout,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_req ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_bsy,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_req);

	fprintf(stderr, "SCSI_TRANSITION history count=%d newest_last=1\n", bootmask_history_count);
	int first = bootmask_history_pos - bootmask_history_count;
	if (first < 0) {
		first += BOOTMASK_HISTORY_SIZE;
	}
	for (int i = 0; i < bootmask_history_count; i++) {
		int idx = (first + i) % BOOTMASK_HISTORY_SIZE;
		const BootmaskHistoryEntry& entry = bootmask_history[idx];
		fprintf(stderr,
			"SCSI_TRANSITION_HIST %03d frame=%d tick=%08X pc=%08X op=%04X "
			"D0=%08X D1=%08X D2=%08X D3=%08X D4=%08X D5=%08X D6=%08X "
			"A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X SP=%08X RET=%08X\n",
			i,
			entry.frame,
			entry.tick,
			entry.pc,
			entry.op,
			entry.d0,
			entry.d1,
			entry.d2,
			entry.d3,
			entry.d4,
			entry.d5,
			entry.d6,
			entry.a0,
			entry.a1,
			entry.a2,
			entry.a3,
			entry.a4,
			entry.sp,
			entry.ret);
	}
}

static void print_late_adb_debug(uint32_t pc) {
	uint32_t sp = tg68_reg(15);
	fprintf(stderr,
		"LATE_ADB trigger frame=%d tick=%08X time=%llu pc=%08X op=%04X "
		"D0=%08X D1=%08X D2=%08X D3=%08X D4=%08X D5=%08X D6=%08X D7=%08X "
		"A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X A5=%08X A6=%08X A7=%08X "
		"RET=%08X SP00=%04X SP02=%04X SP04=%04X SP06=%04X "
		"L054C=%08X B0B22=%02X B0B2E=%02X B0C2F=%02X W017A=%04X "
		"L030A=%08X L0D10=%08X L0D14=%08X "
		"VIA1_PRB=%02X VIA1_DDRB=%02X VIA1_IFR=%02X VIA1_IER=%02X "
		"VIA1_ACR=%02X VIA1_PCR=%02X VIA1_SR=%02X\n",
		video.count_frame,
		lowmem_tick_016a(),
		(unsigned long long)main_time,
		pc,
		VERTOPINTERN->debug_opcode,
		tg68_reg(0),
		tg68_reg(1),
		tg68_reg(2),
		tg68_reg(3),
		tg68_reg(4),
		tg68_reg(5),
		tg68_reg(6),
		tg68_reg(7),
		tg68_reg(8),
		tg68_reg(9),
		tg68_reg(10),
		tg68_reg(11),
		tg68_reg(12),
		tg68_reg(13),
		tg68_reg(14),
		sp,
		ram_long(sp),
		ram_word(sp + 0x00),
		ram_word(sp + 0x02),
		ram_word(sp + 0x04),
		ram_word(sp + 0x06),
		ram_long(0x054C),
		ram_byte(0x0B22),
		ram_byte(0x0B2E),
		ram_byte(0x0C2F),
		ram_word(0x017A),
		ram_long(0x030A),
		ram_long(0x0D10),
		ram_long(0x0D14),
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__pio_i_prb,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__pio_i_ddrb,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_flags,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_mask,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__acr,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__pcr,
		VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__shift_reg);

	fprintf(stderr, "LATE_ADB history count=%d newest_last=1\n", bootmask_history_count);
	int first = bootmask_history_pos - bootmask_history_count;
	if (first < 0) {
		first += BOOTMASK_HISTORY_SIZE;
	}
	for (int i = 0; i < bootmask_history_count; i++) {
		int idx = (first + i) % BOOTMASK_HISTORY_SIZE;
		const BootmaskHistoryEntry& entry = bootmask_history[idx];
		fprintf(stderr,
			"LATE_ADB_HIST %03d frame=%d tick=%08X pc=%08X op=%04X "
			"D0=%08X D1=%08X D2=%08X D3=%08X D4=%08X D5=%08X D6=%08X "
			"A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X SP=%08X RET=%08X\n",
			i,
			entry.frame,
			entry.tick,
			entry.pc,
			entry.op,
			entry.d0,
			entry.d1,
			entry.d2,
			entry.d3,
			entry.d4,
			entry.d5,
			entry.d6,
			entry.a0,
			entry.a1,
			entry.a2,
			entry.a3,
			entry.a4,
			entry.sp,
			entry.ret);
	}
}

static void print_boot_decision_debug(uint32_t pc) {
	uint32_t a6 = tg68_reg(14);
	uint32_t a7 = tg68_reg(15);
	uint32_t a1 = tg68_reg(9);
	uint32_t a3 = tg68_reg(11);
	uint32_t a4 = tg68_reg(12);
	uint32_t a2 = tg68_reg(10);
	uint32_t d6 = tg68_reg(6);
	uint32_t drive_queue = ram_long(0x030A);

	fprintf(stderr,
		"BOOT_DECISION hit=%03d frame=%d tick=%08X time=%llu pc=%08X op=%04X "
		"D0=%08X D1=%08X D2=%08X D3=%08X D4=%08X D5=%08X D6=%08X D7=%08X "
		"A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X A5=%08X A6=%08X A7=%08X RET=%08X "
		"EXCPC=%08X SP00=%04X SP02=%04X SP04=%04X SP06=%04X "
		"SP08=%04X SP0A=%04X SP0C=%04X SP0E=%04X SP10=%04X SP12=%04X SP14=%04X SP16=%04X "
		"FP08=%04X FP0A=%04X FP0C=%04X FP0E=%04X FP14=%04X "
		"A1_00=%04X A1_02=%04X A1_04=%08X A1_08=%08X A1_0C=%04X A1_0E=%04X A1_10=%08X A1_14=%08X "
		"D6W00=%04X D6W02=%04X D6W04=%04X D6W06=%04X D6W08=%04X D6W0A=%04X "
		"W09FA=%04X W09FC=%04X W09FE=%04X W0A00=%04X W0A02=%04X "
		"L0134=%08X W017A=%04X B0B22=%02X B0B2E=%02X B0C2F=%02X W0D00=%04X W0DA6=%04X "
		"L08EE=%08X L0D10=%08X L0D14=%08X L030A=%08X "
		"Q_00=%08X Q_04=%04X Q_06=%04X Q_08=%04X Q_0A=%04X Q_0C=%08X "
		"A2_00=%08X A2_04=%04X A2_06=%04X A2_08=%04X A2_0A=%04X "
		"A4_00=%08X A4_04=%04X A4_06=%04X A4_08=%04X A4_0A=%04X "
		"A4_10=%08X A4_14=%04X A4_18=%08X A4_1C=%04X A4_20=%08X A4_60=%04X A4_61=%02X "
		"SCSI csr=%02X bsr=%02X pmatch=%d dmaen=%d dack=%d mr=%02X icr=%02X tcr=%02X odr=%02X busdin=%02X req=%d tbsy=%02X treq=%02X "
		"cdph=%u cdcnt=%u cdcmd0=%02X cdstat=%02X "
		"IWM q6=%d q7=%d en=%d enn=%d eni=%d ene=%d mode=%02X intRegs=%04X extRegs=%04X a4b61=%02X\n",
		boot_decision_debug_count,
		video.count_frame,
		lowmem_tick_016a(),
		(unsigned long long)main_time,
		pc,
		VERTOPINTERN->debug_opcode,
		tg68_reg(0),
		tg68_reg(1),
		tg68_reg(2),
		tg68_reg(3),
		tg68_reg(4),
		tg68_reg(5),
		tg68_reg(6),
		tg68_reg(7),
		tg68_reg(8),
		a1,
		a2,
		a3,
		a4,
		tg68_reg(13),
		a6,
		a7,
		ram_long(a7),
		ram_long(a7 + 0x02),
		ram_word(a7 + 0x00),
		ram_word(a7 + 0x02),
		ram_word(a7 + 0x04),
		ram_word(a7 + 0x06),
		ram_word(a7 + 0x08),
		ram_word(a7 + 0x0A),
		ram_word(a7 + 0x0C),
		ram_word(a7 + 0x0E),
		ram_word(a7 + 0x10),
		ram_word(a7 + 0x12),
		ram_word(a7 + 0x14),
		ram_word(a7 + 0x16),
		ram_word(a6 + 0x08),
		ram_word(a6 + 0x0A),
		ram_word(a6 + 0x0C),
		ram_word(a6 + 0x0E),
		ram_word(a6 + 0x14),
		ram_word(a1),
		ram_word(a1 + 0x02),
		ram_long(a1 + 0x04),
		ram_long(a1 + 0x08),
		ram_word(a1 + 0x0C),
		ram_word(a1 + 0x0E),
		ram_long(a1 + 0x10),
		ram_long(a1 + 0x14),
		ram_word(d6 + 0x00),
		ram_word(d6 + 0x02),
		ram_word(d6 + 0x04),
		ram_word(d6 + 0x06),
		ram_word(d6 + 0x08),
		ram_word(d6 + 0x0A),
		ram_word(0x09FA),
		ram_word(0x09FC),
		ram_word(0x09FE),
		ram_word(0x0A00),
		ram_word(0x0A02),
		ram_long(0x0134),
		ram_word(0x017A),
		ram_byte(0x0B22),
		ram_byte(0x0B2E),
		ram_byte(0x0C2F),
		ram_word(0x0D00),
		ram_word(0x0DA6),
		ram_long(0x08EE),
		ram_long(0x0D10),
		ram_long(0x0D14),
		drive_queue,
		ram_long(drive_queue),
		ram_word(drive_queue + 0x04),
		ram_word(drive_queue + 0x06),
		ram_word(drive_queue + 0x08),
		ram_word(drive_queue + 0x0A),
		ram_long(drive_queue + 0x0C),
		ram_long(a2),
		ram_word(a2 + 0x04),
		ram_word(a2 + 0x06),
		ram_word(a2 + 0x08),
		ram_word(a2 + 0x0A),
		ram_long(a4),
		ram_word(a4 + 0x04),
		ram_word(a4 + 0x06),
		ram_word(a4 + 0x08),
		ram_word(a4 + 0x0A),
		ram_long(a4 + 0x10),
		ram_word(a4 + 0x14),
		ram_long(a4 + 0x18),
		ram_word(a4 + 0x1C),
		ram_long(a4 + 0x20),
		ram_word(a4 + 0x60),
		ram_byte((a4 + 0x61) & 0x1FFFFF),
		scsi_debug_csr(),
		scsi_debug_bsr(),
		scsi_debug_pmatch() ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_en ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_ack ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__mr,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__tcr,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dout,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_req ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_bsy,
		VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_req,
		0, 0, 0, 0,  // empty_cd gone (MacLC transplant; stub not instantiated)
		VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__q6 ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__q7 ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__anyDiskEnable ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__anyDiskEnableD ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__diskEnableInt ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__diskEnableExt ? 1 : 0,
		VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__iwmMode,
		0 /*swim-port: HUD tap retired*/,
		0 /*swim-port: HUD tap retired*/,
		ram_byte((a4 + 0x61) & 0x1FFFFF));
}

static void print_scsi_stop_state() {
	static const uint8_t lba60_sig[] = {0x4C, 0x4B, 0x60, 0x00, 0x00, 0x86, 0x44, 0x18};
	uint32_t lba60_at = find_ram_bytes(lba60_sig, sizeof(lba60_sig), 0x0000, 0x1FFFFF);

	printf("SCSI state: mr=%02X icr=%02X tcr=%02X odr=%02X busdin=%02X req=%d tbsy=%02X treq=%02X "
	       "sd_rd=%02X sd_wr=%02X sd_ack=%02X sd_buf_wr=%d sd_addr=%02X "
	       "t0_phase=%d t0_mnt=%d t0_cnt=%u t0_done=%d t0_ack=%d t0_cmd_cnt=%d t0_din=%02X "
	       "t0_req_rd=%d t0_req_wr=%d "
	       "blk_cur=%d blk_read=%d blk_write=%d blk_ack_delay=%d blk_bytecnt=%d\n",
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__mr,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__tcr,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dout,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_req ? 1 : 0,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_bsy,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_req,
	       VERTOPINTERN->sd_rd,
	       VERTOPINTERN->sd_wr,
	       VERTOPINTERN->sd_ack,
	       VERTOPINTERN->sd_buff_wr ? 1 : 0,
	       VERTOPINTERN->sd_buff_addr,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__phase,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__mounted ? 1 : 0,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_cnt,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_complete ? 1 : 0,
	       ((VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr & 0x10) || VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_ack) ? 1 : 0,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd_cnt,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din,
	       0 /* req_rd inlined by verilator 5.049 */,
	       VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__req_wr ? 1 : 0,
	       blockdevice.current_disk,
	       blockdevice.reading ? 1 : 0,
	       blockdevice.writing ? 1 : 0,
	       blockdevice.ack_delay,
	       blockdevice.bytecnt);
	printf("LowMem: long[$016A]=%04X%04X word[$0D00]=%04X word[$0DA6]=%04X\n",
	       VERTOPINTERN->emu__DOT__ram__DOT__mem[0x00B5],
	       VERTOPINTERN->emu__DOT__ram__DOT__mem[0x00B6],
	       VERTOPINTERN->emu__DOT__ram__DOT__mem[0x0680],
	       VERTOPINTERN->emu__DOT__ram__DOT__mem[0x06D3]);
	printf("LowMem boot: word[$017A]=%04X byte[$0C2F]=%02X word[$0D24]=%04X word[$0D28]=%04X\n",
	       VERTOPINTERN->emu__DOT__ram__DOT__mem[0x00BD],
	       VERTOPINTERN->emu__DOT__ram__DOT__mem[0x0617] & 0x00FF,
	       VERTOPINTERN->emu__DOT__ram__DOT__mem[0x0692],
	       VERTOPINTERN->emu__DOT__ram__DOT__mem[0x0694]);
	printf("Boot RAM: LBA60_sig=%s%06X "
	       "L12000=%08X L12004=%08X L124D0=%08X L124D4=%08X "
	       "L50F06000=%08X L50F06004=%08X\n",
	       lba60_at == 0xFFFFFFFFU ? "notfound/" : "$",
	       lba60_at == 0xFFFFFFFFU ? 0U : lba60_at,
	       ram_long(0x12000), ram_long(0x12004),
	       ram_long(0x124D0), ram_long(0x124D4),
	       ram_long(0x50F06000), ram_long(0x50F06004));
	printf("TM nodes: L0D10=%08X L0D14=%08X L030A=%08X "
	       "N2748=%08X/%04X/%04X/%04X/%08X "
	       "N33C4=%08X/%04X/%04X/%04X/%08X "
	       "N47A8=%08X/%04X/%04X/%04X/%08X\n",
	       ram_long(0x0D10), ram_long(0x0D14), ram_long(0x030A),
	       ram_long(0x2748), ram_word(0x274C), ram_word(0x274E),
	       ram_word(0x2750), ram_long(0x2754),
	       ram_long(0x33C4), ram_word(0x33C8), ram_word(0x33CA),
	       ram_word(0x33CC), ram_long(0x33D0),
	       ram_long(0x47A8), ram_word(0x47AC), ram_word(0x47AE),
	       ram_word(0x47B0), ram_long(0x47B4));
	printf("Regs: D0=%08X D1=%08X D2=%08X D3=%08X D4=%08X D5=%08X D6=%08X D7=%08X\n",
	       tg68_reg(0), tg68_reg(1), tg68_reg(2), tg68_reg(3),
	       tg68_reg(4), tg68_reg(5), tg68_reg(6), tg68_reg(7));
	printf("Regs: A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X A5=%08X A6=%08X A7=%08X\n",
	       tg68_reg(8), tg68_reg(9), tg68_reg(10), tg68_reg(11),
	       tg68_reg(12), tg68_reg(13), tg68_reg(14), tg68_reg(15));
	printf("Timing: main_time=%llu frame=%d unique_fetches=%llu\n",
	       (unsigned long long)main_time,
	       video.count_frame,
	       (unsigned long long)unique_fetch_count);
	printf("IRQ: ipl=%u nubus_irq_n=%u vbl_irq=%u vbl_disable=%u "
	       "via1_ifr=%02X via1_ier=%02X via2_ifr=%02X via2_ier=%02X\n",
	       VERTOPINTERN->debug_cpuIPL,
	       VERTOPINTERN->emu__DOT__nubus_irq_n,
	       VERTOPINTERN->emu__DOT__nubus_card__DOT__irq_active,
	       (uint8_t)(!VERTOPINTERN->emu__DOT__nubus_card__DOT__vblank_enable),
	       VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_flags,
	       VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_mask,
	       VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__irq_flags,
	       VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__irq_mask);
	printf("VIA edge counters: rtc_cko=%u via2_pb7=%u via1_ca1=%u via1_ca2=%u\n",
	       VERTOPINTERN->emu__DOT__dc0__DOT__onesec_edges,
	       VERTOPINTERN->emu__DOT__dc0__DOT__pb7_edges,
	       VERTOPINTERN->emu__DOT__dc0__DOT__ca1_edges,
	       VERTOPINTERN->emu__DOT__dc0__DOT__ca2_edges);
	print_via_timer_state(stdout, "VIA timers:");
	printf("Profile: irq_changes=%llu irq1=%llu irq2=%llu irq4=%llu irq7=%llu "
	       "fetch_scsi_timeout=%llu fetch_tick_wait=%llu fetch_vbl=%llu fetch_lowmem=%llu\n",
	       (unsigned long long)profile_irq_change_count,
	       (unsigned long long)profile_irq_assert_count[6],
	       (unsigned long long)profile_irq_assert_count[5],
	       (unsigned long long)profile_irq_assert_count[3],
	       (unsigned long long)profile_irq_assert_count[0],
	       (unsigned long long)profile_scsi_timeout_fetches,
	       (unsigned long long)profile_tick_wait_fetches,
	       (unsigned long long)profile_vbl_handler_fetches,
	       (unsigned long long)profile_lowmem_fetches);
}

// 31.3344 MHz system clock (= 2 × C15M; matches FPGA PLL).
// CPU runs at C15M = 15.6672 MHz via clk16_en; SCC/IWM at C7M = 7.8336 MHz via clk8_en.
int clk_sys_freq = 31334400;
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
			if (force_calib_enable && !*bus.ioctl_download &&
			    video.count_frame >= force_calib_min_frame) {
				ram_write_word(0x0D00, force_calib_0d00);
				ram_write_word(0x0DA6, force_calib_0da6);
				if (!force_calib_reported) {
					fprintf(stderr, "FORCE_CALIB frame=%d W0D00=%04X W0DA6=%04X\n",
					        video.count_frame, force_calib_0d00, force_calib_0da6);
					force_calib_reported = true;
				}
			}

			// Heap-spray watch (2026-07-15, relocated): must run EVERY tick —
			// write_valid pulses on WRITE AS-rises, which never coincide with
			// fetch ticks, so inside the fetch_valid gate it can never fire.
			if (heapspray_debug_enable && !*bus.ioctl_download &&
			    heapspray_debug_count < heapspray_debug_max) {
				bool completed_write = VERTOPINTERN->debug_write_valid &&
				                       !heapspray_prev_write_valid;
				// debug_write_addr = RAW pre-hmmu tg68_a; mask to 24-bit
				// significance (flagged MM pointers carry high bytes).
				// Slot writes (0xFsxx_xxxx) alias into the masked window — only
				// accept top bytes that are pure MM flag bits (bits 28..24 clear:
				// 0x00/0x20/0x40/.../0xE0), which excludes 0xF1-0xFE slot space.
				uint32_t waddr = VERTOPINTERN->debug_write_addr & 0xFFFFFF;
				bool ram_topbyte = ((VERTOPINTERN->debug_write_addr >> 24) & 0x1F) == 0;
				if (completed_write && sim_drv_exec && ram_topbyte &&
				    drv_base != 0 && waddr >= drv_base && waddr < drv_base + 0x2600) {
					fprintf(stderr,
						"HEAPSPRAY frame=%d pc=%08X addr=%08X raw=%08X data=%04X "
						"SP=%08X RET=%08X A4=%08X A5=%08X D6=%08X\n",
						video.count_frame, VERTOPINTERN->debug_pc, waddr,
						VERTOPINTERN->debug_write_addr,
						VERTOPINTERN->debug_write_data,
						tg68_reg(15), ram_long(tg68_reg(15) & 0x7FFFFF),
						tg68_reg(12), tg68_reg(13), tg68_reg(6));
					heapspray_debug_count++;
					if (heapspray_debug_count == heapspray_debug_max)
						fprintf(stderr, "HEAPSPRAY cap reached\n");
				}
			}
			// Generic RAM write-watch (2026-07-16): --watch-range LO:HI[:MINFRAME]
			// logs every completed CPU write landing in [LO,HI) from MINFRAME on.
			// Same edge/alias filtering as the heapspray watch. Used to catch the
			// in-RAM System resource-map smash during the LoadResource window.
			if (watch_range_enable && !*bus.ioctl_download &&
			    video.count_frame >= watch_range_min_frame &&
			    watch_range_count < watch_range_max) {
				bool completed_write = VERTOPINTERN->debug_write_valid &&
				                       !heapspray_prev_write_valid;
				uint32_t waddr = VERTOPINTERN->debug_write_addr & 0xFFFFFF;
				bool ram_topbyte = ((VERTOPINTERN->debug_write_addr >> 24) & 0x1F) == 0;
				if (completed_write && ram_topbyte &&
				    waddr >= watch_range_lo && waddr < watch_range_hi) {
					fprintf(stderr,
						"WATCHWR frame=%d pc=%08X addr=%06X data=%04X "
						"SP=%08X A0=%08X A1=%08X D0=%08X D1=%08X\n",
						video.count_frame, VERTOPINTERN->debug_pc, waddr,
						VERTOPINTERN->debug_write_data,
						tg68_reg(15), tg68_reg(8), tg68_reg(9),
						tg68_reg(0), tg68_reg(1));
					watch_range_count++;
					if (watch_range_count == watch_range_max)
						fprintf(stderr, "WATCHWR cap reached\n");
				}
			}
			// ASC-mode tracer (2026-07-15): log CPU writes to the ASC mode
			// register ($50F14801) so we can tell FIFO(1) vs wavetable(2) for
			// the boot chime. Gated under heapspray_debug to reuse the flag.
			if (heapspray_debug_enable && !*bus.ioctl_download) {
				bool cw = VERTOPINTERN->debug_write_valid &&
				          !heapspray_asc_prev_write_valid;
				uint32_t wa = VERTOPINTERN->debug_write_addr & 0x1FFFFF;
				if (cw && (wa == 0x114801 || wa == 0x114803 ||
				           (wa >= 0x114000 && wa <= 0x1147FF && (wa & 0x7F) == 0))) {
					fprintf(stderr, "ASCWR frame=%d pc=%08X addr=%08X data=%04X\n",
						video.count_frame, VERTOPINTERN->debug_pc,
						VERTOPINTERN->debug_write_addr,
						VERTOPINTERN->debug_write_data);
				}
			}
			heapspray_asc_prev_write_valid = VERTOPINTERN->debug_write_valid;

			heapspray_prev_write_valid = VERTOPINTERN->debug_write_valid;

			if (VERTOPINTERN->debug_fetch_valid && !*bus.ioctl_download) {
				uint32_t pc = VERTOPINTERN->debug_pc;
				// Capture the disk-driver base at the loader's jsr (a3)
				// (ROM 0x40807BB0); A3 = the NewPtr'd, checksummed image.
				if (pc == 0x40807BB0 && drv_base == 0) {
					drv_base = tg68_reg(11) & 0xFFFFFF;
					fprintf(stderr, "DRVBASE frame=%d loader jsr (a3): base=%06X\n",
						video.count_frame, drv_base);
				}
				// driver-exec arm + optional driver-window PC-stream trace
				if (drv_base != 0 && (pc & 0xFF000000) == 0 &&
				    (pc & 0xFFFFFF) >= drv_base && (pc & 0xFFFFFF) < drv_base + 0x2600) {
					if (!sim_drv_exec) {
						sim_drv_exec = true;
						fprintf(stderr, "DRVEXEC frame=%d first driver fetch pc=%08X\n",
							video.count_frame, pc);
					}
					if (drvtrace_enable && drvtrace_count < drvtrace_max) {
						fprintf(stderr, "DT %d %06X %04X %08X %08X %08X %08X %08X\n",
							video.count_frame, pc & 0xFFFFFF,
							VERTOPINTERN->debug_opcode,
							tg68_reg(0), tg68_reg(1),
							tg68_reg(8), tg68_reg(9),
							tg68_reg(15));
						if (++drvtrace_count == drvtrace_max)
							fprintf(stderr, "DT cap reached\n");
					}
				}
				if (scsi_stall_history_enable && !scsi_stall_dumped) {
					record_bootmask_history(pc);
					// DREQ asserted but CPU not draining it -> count consecutive
					// fetches; once it's clearly wedged, dump the PC ring buffer
					// (the outer loop that abandoned the data transfer) and stop.
					if (VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dreq_r) {
						if (++scsi_stall_dreq_run >= 400000) {
							fprintf(stderr, "SCSI_STALL_HISTORY trigger frame=%d pc=%08X dreq stuck\n",
							        video.count_frame, pc);
							int first = bootmask_history_pos - bootmask_history_count;
							if (first < 0) first += BOOTMASK_HISTORY_SIZE;
							for (int i = 0; i < bootmask_history_count; i++) {
								int idx = (first + i) % BOOTMASK_HISTORY_SIZE;
								const BootmaskHistoryEntry& e = bootmask_history[idx];
								fprintf(stderr, "STALLHIST %03d frame=%d pc=%08X op=%04X "
								        "D0=%08X D1=%08X D5=%08X A2=%08X A3=%08X A4=%08X SP=%08X RET=%08X\n",
								        i, e.frame, e.pc, e.op, e.d0, e.d1, e.d5, e.a2, e.a3, e.a4, e.sp, e.ret);
							}
							scsi_stall_dumped = true;
						}
					} else {
						scsi_stall_dreq_run = 0;
					}
				}
				if (bootmask_once_debug_enable && !bootmask_once_stop_requested) {
					record_bootmask_history(pc);
					if (bootmask_once_pc(pc)) {
						print_bootmask_once_debug(pc);
						bootmask_once_stop_requested = true;
					}
				}
				if (scsi_transition_debug_enable && !scsi_transition_stop_requested) {
					record_bootmask_history(pc);
					if (scsi_transition_pc(pc)) {
						print_scsi_transition_debug(pc);
						scsi_transition_stop_requested = true;
					}
				}
				if (late_adb_debug_enable && !late_adb_stop_requested) {
					record_bootmask_history(pc);
					if (late_adb_pc(pc)) {
						print_late_adb_debug(pc);
						late_adb_stop_requested = true;
					}
				}
				if (pc != unique_fetch_last_pc) {
					unique_fetch_last_pc = pc;
					unique_fetch_count++;
				}
				if (pc != profile_last_fetch_pc) {
					if (pc >= 0x40826CB6 && pc <= 0x40826CD4) {
						profile_scsi_timeout_fetches++;
					}
					if (pc >= 0x40801500 && pc <= 0x40801658) {
						profile_tick_wait_fetches++;
					}
					if (pc >= 0x4080612E && pc <= 0x408061F2) {
						profile_vbl_handler_fetches++;
					}
					if (pc >= 0x00800000 && pc <= 0x008FFFFF) {
						profile_lowmem_fetches++;
					}
					profile_last_fetch_pc = pc;
				}
				if (boot_decision_debug_enable &&
				    VERTOPINTERN->debug_fetch_valid &&
				    video.count_frame >= boot_decision_debug_min_frame &&
				    boot_decision_pc(pc) &&
				    boot_decision_debug_count < boot_decision_debug_max) {
					uint32_t key = (pc & 0xFFFFFFFEU) ^
					               (lowmem_tick_016a() << 1) ^
					               (tg68_reg(5) & 0xFFFFU) ^
					               ((tg68_reg(15) & 0xFFFFU) << 16);
					if (key != boot_decision_debug_last_key) {
						print_boot_decision_debug(pc);
						boot_decision_debug_count++;
						boot_decision_debug_last_key = key;
					}
				}

				if (boot_decision_debug_enable &&
				    lowmem_bit_debug_count < lowmem_bit_debug_max &&
				    main_time != lowmem_bit_debug_last_time) {
					bool active_bus = !VERTOPINTERN->debug_cpuAS;
					bool active_write = active_bus && !VERTOPINTERN->debug_cpuRW;
					bool completed_write = VERTOPINTERN->debug_write_valid && !lowmem_bit_debug_prev_write_valid;
					uint32_t addr = (completed_write ? VERTOPINTERN->debug_write_addr : VERTOPINTERN->debug_cpuAddr) & 0x1FFFFF;
					uint32_t ram_byte_addr = ((uint32_t)VERTOPINTERN->debug_ram_addr & 0x1FFFFF) << 1;
					bool watched_cpu_addr = (addr >= 0x09F8 && addr <= 0x0A07) ||
					                        (addr >= 0x0B20 && addr <= 0x0B2F);
					bool watched_ram_write = VERTOPINTERN->debug_ram_we &&
					                         (ram_byte_addr >= 0x09F8 && ram_byte_addr <= 0x0A07);
					if (((active_bus || completed_write) && watched_cpu_addr) ||
					    watched_ram_write) {
						lowmem_bit_debug_last_time = main_time;
						fprintf(stderr,
							"LOWMEM_BIT_WR hit=%03d kind=%s frame=%d tick=%08X time=%llu pc=%08X op=%04X "
							"addr=%08X data=%04X UDS=%d LDS=%d selRAM=%d ram_we=%d ram_ds=%d%d ram_addr=%07X ram_din=%04X "
							"RAM_BYTE=%08X W09FA=%04X W09FC=%04X W09FE=%04X W0A00=%04X W0A02=%04X B0B22=%02X B0B2E=%02X\n",
							lowmem_bit_debug_count,
							watched_ram_write ? "ram_we" : (completed_write ? "complete" : (active_write ? "active_wr" : "active_rd")),
							video.count_frame,
							lowmem_tick_016a(),
							(unsigned long long)main_time,
							pc,
							VERTOPINTERN->debug_opcode,
							completed_write ? VERTOPINTERN->debug_write_addr : VERTOPINTERN->debug_cpuAddr,
							completed_write ? VERTOPINTERN->debug_write_data : VERTOPINTERN->debug_cpuDataIn,
							!VERTOPINTERN->debug_cpuUDS ? 1 : 0,
							!VERTOPINTERN->debug_cpuLDS ? 1 : 0,
							VERTOPINTERN->debug_selectRAM ? 1 : 0,
							VERTOPINTERN->debug_ram_we ? 1 : 0,
							(VERTOPINTERN->debug_ram_ds >> 1) & 1,
							VERTOPINTERN->debug_ram_ds & 1,
							VERTOPINTERN->debug_ram_addr,
							VERTOPINTERN->debug_ram_din,
							ram_byte_addr,
							ram_word(0x09FA),
							ram_word(0x09FC),
							ram_word(0x09FE),
							ram_word(0x0A00),
							ram_word(0x0A02),
							ram_byte(0x0B22),
							ram_byte(0x0B2E));
						lowmem_bit_debug_count++;
					}
				}
				lowmem_bit_debug_prev_write_valid = VERTOPINTERN->debug_write_valid;
				if (wait_debug_enable &&
				    video.count_frame >= wait_debug_min_frame &&
				    pc >= 0x40801500 && pc <= 0x408017CC &&
				    wait_debug_count < wait_debug_max) {
					uint32_t tick = lowmem_tick_016a();
					bool spin_pc = (pc >= 0x40801652 && pc <= 0x40801658);
					bool should_log = spin_pc ? (tick != wait_debug_last_tick) : (pc != wait_debug_last_pc);
					if (should_log) {
						uint32_t sp = tg68_reg(15);
						uint32_t a0 = tg68_reg(8);
						uint32_t a2 = tg68_reg(10);
						fprintf(stderr,
							"WAIT_DBG frame=%d tick=%08X time=%llu pc=%08X op=%04X "
							"D0=%08X D1=%08X D2=%08X D5=%08X D7=%08X "
							"A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X A5=%08X A6=%08X SP=%08X RET=%08X "
							"W017A=%04X B0C2F=%02X W0D24=%04X W0D28=%04X A2W8=%04X "
							"PB_REF=%04X PB_BUF=%08X PB_REQ=%08X PB_POSMODE=%04X PB_POS=%08X\n",
							video.count_frame,
							tick,
							(unsigned long long)main_time,
							pc,
							VERTOPINTERN->debug_opcode,
							tg68_reg(0),
							tg68_reg(1),
							tg68_reg(2),
							tg68_reg(5),
							tg68_reg(7),
							a0,
							tg68_reg(9),
							tg68_reg(10),
							tg68_reg(11),
							tg68_reg(12),
							tg68_reg(13),
							tg68_reg(14),
							sp,
							ram_long(sp),
							ram_word(0x017A),
							ram_word(0x0C2E) & 0x00FF,
							ram_word(0x0D24),
							ram_word(0x0D28),
							ram_word(a2 + 8),
							ram_word(a0 + 24),
							ram_long(a0 + 32),
							ram_long(a0 + 36),
							ram_word(a0 + 44),
							ram_long(a0 + 46));
						wait_debug_count++;
						wait_debug_last_pc = pc;
						wait_debug_last_tick = tick;
					}
				}

				if (scsi_timeout_loop_debug_enable &&
				    pc >= 0x40826CB6 && pc <= 0x40826CD4 &&
				    scsi_timeout_loop_debug_count < scsi_timeout_loop_debug_max) {
					uint32_t d1 = tg68_reg(1);
					uint32_t d5 = tg68_reg(5);
					uint16_t d1_word = d1 & 0xffff;
					uint16_t d5_word = d5 & 0xffff;
					uint8_t scsi_mr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__mr;
					uint8_t scsi_icr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr;
					uint8_t scsi_tcr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__tcr;
					bool scsi_bsy = (scsi_icr & 0x08) || VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_bsy || (scsi_mr & 0x01);
					bool scsi_req = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_req;
					bool scsi_msg = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_msg;
					bool scsi_cd = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_cd;
					bool scsi_io = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_io;
					bool phase_match = ((scsi_tcr & 0x07) == ((scsi_msg ? 4 : 0) | (scsi_cd ? 2 : 0) | (scsi_io ? 1 : 0)));
					uint8_t bsr = ((scsi_req && VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_en) ? 0x40 : 0x00) |
					              (phase_match ? 0x08 : 0x00) |
					              ((scsi_icr & 0x02) ? 0x02 : 0x00) |
					              ((scsi_icr & 0x10) ? 0x01 : 0x00);
					uint8_t csr = ((scsi_icr & 0x80) ? 0x80 : 0x00) |
					              (scsi_bsy ? 0x40 : 0x00) |
					              (scsi_req ? 0x20 : 0x00) |
					              (scsi_msg ? 0x10 : 0x00) |
					              (scsi_cd ? 0x08 : 0x00) |
					              (scsi_io ? 0x04 : 0x00) |
					              ((scsi_icr & 0x04) ? 0x02 : 0x00);
					bool d1_near_rollover = d1_word <= 4 || d1_word >= 0xfffc;
					bool d5_changed = d5_word != (scsi_timeout_loop_last_d5_word & 0xffff);
					bool log_loop_state =
						pc == 0x40826CB4 ||
						pc == 0x40826CB6 ||
						pc == 0x40826CD0 ||
						pc == 0x40826CD2 ||
						pc == 0x40826CD4 ||
						(pc == 0x40826CC6 && (d1_near_rollover || (d1_word == 0x8000 && d5_word <= 8))) ||
						(pc == 0x40826CCA && (d1_near_rollover || d5_changed));
					uint32_t sp = tg68_reg(15);
					uint32_t ret = ram_long(sp);
					bool new_entry = (pc == 0x40826CB4 || pc == 0x40826CB6) &&
					                 (sp != scsi_timeout_loop_last_entry_sp ||
					                  ret != scsi_timeout_loop_last_entry_ret);
					log_loop_state = log_loop_state || new_entry;
					if (log_loop_state) {
						fprintf(stderr,
							"SCSI_TIMEOUT_LOOP hit=%04d frame=%d tick=%08X time=%llu pc=%08X op=%04X "
							"D0=%08X D1=%08X D5=%08X D6=%08X A3=%08X SP=%08X RET=%08X "
							"W0D00=%04X W0DA6=%04X bsr=%02X csr=%02X icr=%02X mr=%02X odr=%02X\n",
							scsi_timeout_loop_debug_count,
							video.count_frame,
							lowmem_tick_016a(),
							(unsigned long long)main_time,
							pc,
							VERTOPINTERN->debug_opcode,
							tg68_reg(0),
							d1,
							d5,
							tg68_reg(6),
							tg68_reg(11),
							sp,
							ret,
							ram_word(0x0D00),
							ram_word(0x0DA6),
							bsr,
							csr,
							scsi_icr,
							scsi_mr,
							VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dout);
						scsi_timeout_loop_debug_count++;
						if (new_entry) {
							scsi_timeout_loop_last_entry_sp = sp;
							scsi_timeout_loop_last_entry_ret = ret;
						}
						if (pc == 0x40826CCA) {
							scsi_timeout_loop_last_d5_word = d5_word;
						}
					}
				}

				if (iwm_state_debug_enable &&
				    pc >= 0x0082E220 && pc <= 0x0082E2DF &&
				    iwm_state_debug_count < iwm_state_debug_max &&
				    pc != iwm_state_debug_last_pc) {
					print_iwm_state_debug(pc);
					iwm_state_debug_count++;
					iwm_state_debug_last_pc = pc;
				}
			}

			if (!*bus.ioctl_download) {
				uint8_t cur_ipl = VERTOPINTERN->debug_cpuIPL & 0x07;
				if (cur_ipl != profile_last_ipl) {
					profile_irq_change_count++;
					if (cur_ipl != 7) {
						profile_irq_assert_count[cur_ipl]++;
					}
					profile_last_ipl = cur_ipl;
				}
			}

			if (calib_debug_enable && !*bus.ioctl_download && calib_debug_count < calib_debug_max) {
				uint32_t tick = lowmem_tick_016a();
				bool via1_t1 = VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_a_event;
				bool via1_t2 = ((VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_events >> 5) & 1) != 0;
				bool via2_t1 = VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__timer_a_event;
				bool tick_initialized = ram_word(0x0D28) == 0x4080 && (tick >> 16) == 0;
				if (tick_initialized && tick != calib_debug_last_lowmem_tick) {
					fprintf(stderr,
						"CALIB_TICK frame=%d tick=%08X time=%llu pc=%08X W0D00=%04X W0DA6=%04X\n",
						video.count_frame,
						tick,
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						ram_word(0x0D00),
						ram_word(0x0DA6));
					calib_debug_count++;
					calib_debug_last_lowmem_tick = tick;
				}

				if ((via1_t1 && !calib_debug_prev_via1_t1) ||
				    (via2_t1 && !calib_debug_prev_via2_t1)) {
					char prefix[128];
					snprintf(prefix, sizeof(prefix),
						"CALIB_T1 frame=%d tick=%08X time=%llu pc=%08X",
						video.count_frame,
						tick,
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc);
					print_via_timer_state(stderr, prefix);
					calib_debug_count++;
				}
				calib_debug_prev_via1_t1 = via1_t1;
				calib_debug_prev_via2_t1 = via2_t1;

				if (via1_t2 && !calib_debug_prev_via1_t2) {
					char prefix[128];
					snprintf(prefix, sizeof(prefix),
						"CALIB_T2 frame=%d tick=%08X time=%llu pc=%08X D0=%08X",
						video.count_frame,
						tick,
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						tg68_reg(0));
					print_via_timer_state(stderr, prefix);
					calib_debug_count++;
				}
				calib_debug_prev_via1_t2 = via1_t2;

				if (VERTOPINTERN->debug_write_valid && !calib_debug_prev_write_valid) {
					uint32_t waddr = VERTOPINTERN->debug_write_addr;
					if (waddr == 0x00000D00 || waddr == 0x00000DA6 ||
					    waddr == 0x00000D24 || waddr == 0x00000D28 ||
					    waddr == 0x0000016A || waddr == 0x0000016C) {
						fprintf(stderr,
							"CALIB_LM_WR frame=%d tick=%08X time=%llu pc=%08X addr=%08X data=%04X W0D00=%04X W0DA6=%04X W0D24=%04X W0D28=%04X\n",
							video.count_frame,
							tick,
							(unsigned long long)main_time,
							VERTOPINTERN->debug_pc,
							waddr,
							VERTOPINTERN->debug_write_data,
							ram_word(0x0D00),
							ram_word(0x0DA6),
							ram_word(0x0D24),
							ram_word(0x0D28));
						calib_debug_count++;
					}
				}
				calib_debug_prev_write_valid = VERTOPINTERN->debug_write_valid;

				bool via_rd = VERTOPINTERN->debug_viaRd;
				bool via_wr = VERTOPINTERN->debug_viaWr;
				if (((via_rd && !calib_debug_prev_via_rd) ||
				     (via_wr && !calib_debug_prev_via_wr)) &&
				    (VERTOPINTERN->debug_selectVIA || VERTOPINTERN->debug_selectVIA2)) {
					uint32_t addr = VERTOPINTERN->debug_cpuAddr;
					uint8_t reg = (addr >> 9) & 0x0F;
					bool interesting_reg = (reg >= 4 && reg <= 7) || reg == 0x0B ||
					                       reg == 0x0D || reg == 0x0E;
					if (interesting_reg) {
						fprintf(stderr,
							"CALIB_VIA frame=%d tick=%08X time=%llu pc=%08X %s %s reg=%X addr=%08X din=%04X dout=%04X W0D00=%04X W0DA6=%04X\n",
							video.count_frame,
							tick,
							(unsigned long long)main_time,
							VERTOPINTERN->debug_pc,
							VERTOPINTERN->debug_selectVIA2 ? "VIA2" : "VIA1",
							VERTOPINTERN->debug_cpuRW ? "RD" : "WR",
							reg,
							addr,
							VERTOPINTERN->debug_cpuDataIn,
							VERTOPINTERN->debug_cpuDataOut,
							ram_word(0x0D00),
							ram_word(0x0DA6));
						print_via_timer_state(stderr, "CALIB_VIA_STATE");
						calib_debug_count++;
					}
				}
				calib_debug_prev_via_rd = via_rd;
				calib_debug_prev_via_wr = via_wr;
			}

			if (calib_loop_debug_enable && !*bus.ioctl_download &&
			    VERTOPINTERN->debug_fetch_valid &&
			    calib_loop_debug_count < calib_loop_debug_max) {
				uint32_t pc = VERTOPINTERN->debug_pc;
				int loop_idx = -1;
				if (pc == 0x4080059C) loop_idx = 0;
				else if (pc == 0x408005D6) loop_idx = 1;
				else if (pc == 0x40800612) loop_idx = 2;

				if (loop_idx >= 0) {
					calib_loop_hits[loop_idx]++;
					uint32_t hits = calib_loop_hits[loop_idx];
					if (hits <= 8 || (hits & 0xFF) == 0) {
						fprintf(stderr,
							"CALIB_LOOP[%d] hit=%u frame=%d time=%llu pc=%08X op=%04X "
							"D0=%08X D1=%08X A0=%08X A1=%08X "
							"T2c=%04X T2l=%04X ifr=%02X ier=%02X tick=%u acc=%u\n",
							loop_idx,
							hits,
							video.count_frame,
							(unsigned long long)main_time,
							pc,
							VERTOPINTERN->debug_opcode,
							tg68_reg(0),
							tg68_reg(1),
							tg68_reg(8),
							tg68_reg(9),
							VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_b_count,
							VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_b_latch,
							VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_flags,
							VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_mask,
							VERTOPINTERN->emu__DOT__dc0__DOT__via_timer_tick ? 1 : 0,
							VERTOPINTERN->emu__DOT__dc0__DOT__via_timer_acc);
						calib_loop_debug_count++;
					}
				} else if (pc == 0x408005A4 || pc == 0x408005DE || pc == 0x4080061A) {
					fprintf(stderr,
						"CALIB_LOOP_EXIT frame=%d time=%llu pc=%08X op=%04X "
						"D0=%08X loops=%u/%u/%u T2c=%04X ifr=%02X ier=%02X\n",
						video.count_frame,
						(unsigned long long)main_time,
						pc,
						VERTOPINTERN->debug_opcode,
						tg68_reg(0),
						calib_loop_hits[0],
						calib_loop_hits[1],
						calib_loop_hits[2],
						VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__timer_b_count,
						VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_flags,
						VERTOPINTERN->emu__DOT__dc0__DOT__via__DOT__irq_mask);
					calib_loop_debug_count++;
				}
			}

			if (ramtest_debug_enable && !*bus.ioctl_download &&
			    VERTOPINTERN->debug_fetch_valid &&
			    ramtest_debug_count < ramtest_debug_max) {
				uint32_t pc = VERTOPINTERN->debug_pc;
				bool interesting =
					pc == 0x40802BBC || pc == 0x40802BF0 ||
					pc == 0x40802C10 || pc == 0x40802C28 ||
					pc == 0x40802C3C || pc == 0x40802CDC ||
					pc == 0x40803714 || pc == 0x40803734 ||
					pc == 0x40803760 || pc == 0x40803778 ||
					pc == 0x4080378E || pc == 0x40803794 ||
					pc == 0x4080379A || pc == 0x4080379E ||
					pc == 0x408037A0 || pc == 0x408037A2 ||
					pc == 0x408037A4 || pc == 0x408037A6 ||
					pc == 0x408037A8 || pc == 0x408037AA;
				if (interesting && pc != ramtest_debug_last_pc) {
					uint32_t a0 = tg68_reg(8);
					uint32_t a1 = tg68_reg(9);
					fprintf(stderr,
						"RAMTEST_DBG hit=%03d frame=%d time=%llu pc=%08X op=%04X "
						"D0=%08X D1=%08X D2=%08X D3=%08X D4=%08X D5=%08X D6=%08X D7=%08X "
						"A0=%08X A1=%08X A2=%08X A3=%08X A4=%08X A6=%08X "
						"M0=%04X%04X M8=%04X%04X MSP=%04X%04X MTOP=%04X%04X\n",
						ramtest_debug_count,
						video.count_frame,
						(unsigned long long)main_time,
						pc,
						VERTOPINTERN->debug_opcode,
						tg68_reg(0), tg68_reg(1), tg68_reg(2), tg68_reg(3),
						tg68_reg(4), tg68_reg(5), tg68_reg(6), tg68_reg(7),
						a0, a1, tg68_reg(10), tg68_reg(11), tg68_reg(12), tg68_reg(14),
						ram_word(0), ram_word(2),
						ram_word(8), ram_word(10),
						ram_word(0x1FFD00), ram_word(0x1FFD02),
						ram_word(0x1FFFFC), ram_word(0x1FFFFE));
					ramtest_debug_last_pc = pc;
					ramtest_debug_count++;
				}
			}

			// Vector table write watchpoint - log any write to $0-$3FF
			if (VERTOPINTERN->debug_write_valid && !*bus.ioctl_download && cpu_trace_file &&
			    (int)video.count_frame >= cpu_trace_min_frame) {
				uint32_t waddr = VERTOPINTERN->debug_write_addr;
				if (waddr < 0x400) {
					uint16_t wdata = VERTOPINTERN->debug_write_data;
					fprintf(cpu_trace_file, "** VECWR %08X <= %04X\n", waddr, wdata);
				} else if (waddr >= 0x00022000 && waddr < 0x00022040) {
					// FPU CIR window (CPU-space $0002 2xxx; same A[15:0] as RAM alias)
					uint16_t wdata = VERTOPINTERN->debug_write_data;
					fprintf(cpu_trace_file, "** CIRWR %08X <= %04X\n", waddr, wdata);
				}
			}

			// FPU CIR read watchpoint (FSAVE frame / response reads)
			if (VERTOPINTERN->debug_cirrd_valid && !*bus.ioctl_download && cpu_trace_file &&
			    (int)video.count_frame >= cpu_trace_min_frame) {
				fprintf(cpu_trace_file, "** CIRRD %08X => %04X\n",
				        VERTOPINTERN->debug_cirrd_addr, VERTOPINTERN->debug_cirrd_data);
			}

			// CPU trace output - skip while ROM is downloading
			if (cpu_trace_enable && VERTOPINTERN->debug_fetch_valid && !*bus.ioctl_download &&
			    (int)video.count_frame >= cpu_trace_min_frame) {
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

			if (bus_handshake_debug_enable && !*bus.ioctl_download &&
			    video.count_frame >= bus_handshake_debug_min_frame &&
			    bus_handshake_debug_count < bus_handshake_debug_max) {
				bool as_n = VERTOPINTERN->debug_cpuAS;
				bool vpa_n = VERTOPINTERN->debug_cpuVPA;
				bool dtack_n = VERTOPINTERN->debug_cpuDTACK;
				bool vma_n = VERTOPINTERN->debug_cpuVMA;
				bool active = !as_n;
				bool as_edge = (as_n != bus_handshake_debug_prev_as);
				bool ack_edge = active &&
				                ((vpa_n != bus_handshake_debug_prev_vpa) ||
				                 (dtack_n != bus_handshake_debug_prev_dtack) ||
				                 (vma_n != bus_handshake_debug_prev_vma));
				bool selectVIA = VERTOPINTERN->debug_selectVIA;
				bool selectVIA2 = VERTOPINTERN->debug_selectVIA2;
				bool selectSCSI = VERTOPINTERN->debug_selectSCSI;
				bool selectSCC = VERTOPINTERN->debug_selectSCC;
				bool selectIWM = VERTOPINTERN->debug_selectIWM;
				bool selectASC = VERTOPINTERN->debug_selectASC;
				bool selectNuBus = VERTOPINTERN->debug_selectNuBus;
				bool interesting_select = selectVIA || selectVIA2 || selectSCSI || selectSCC ||
				                          selectIWM || selectASC || selectNuBus;
				bool vpa_non_via = active && !vpa_n && !(selectVIA || selectVIA2) && interesting_select;

				if (interesting_select &&
				    (as_edge || ack_edge || (vpa_non_via && !bus_handshake_debug_prev_vpa_non_via))) {
					const char* dev =
						selectVIA ? "VIA1" :
						selectVIA2 ? "VIA2" :
						selectSCSI ? "SCSI" :
						selectSCC ? "SCC" :
						selectIWM ? "IWM" :
						selectASC ? "ASC" :
						selectNuBus ? "NUBUS" : "IO";
					fprintf(stderr,
						"BUS_HS hit=%d frame=%d tick=%08X time=%llu pc=%08X fc=%u %s %s "
						"addr=%08X din=%04X dout=%04X AS=%d VPA=%d VMA=%d DTACK=%d UDS=%d LDS=%d "
						"BERR=%d bus=%d vpa_non_via=%d\n",
						bus_handshake_debug_count,
						video.count_frame,
						lowmem_tick_016a(),
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						VERTOPINTERN->debug_fc,
						VERTOPINTERN->debug_cpuRW ? "RD" : "WR",
						dev,
						VERTOPINTERN->debug_cpuAddr,
						VERTOPINTERN->debug_cpuDataIn,
						VERTOPINTERN->debug_cpuDataOut,
						!as_n ? 1 : 0,
						!vpa_n ? 1 : 0,
						!vma_n ? 1 : 0,
						!dtack_n ? 1 : 0,
						!VERTOPINTERN->debug_cpuUDS ? 1 : 0,
						!VERTOPINTERN->debug_cpuLDS ? 1 : 0,
						VERTOPINTERN->debug_berr ? 1 : 0,
						VERTOPINTERN->debug_cpuBusControl ? 1 : 0,
						vpa_non_via ? 1 : 0);
					bus_handshake_debug_count++;
				}

				bus_handshake_debug_prev_as = as_n;
				bus_handshake_debug_prev_vpa = vpa_n;
				bus_handshake_debug_prev_dtack = dtack_n;
				bus_handshake_debug_prev_vma = vma_n;
				bus_handshake_debug_prev_vpa_non_via = vpa_non_via;
			}

			if (scsi_debug_enable && !*bus.ioctl_download && video.count_frame >= scsi_debug_min_frame) {
				uint32_t t0_data_cnt =
					VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_cnt;
				uint8_t t0_cmd0 =
					VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd[0];
				uint8_t t0_cmd2 =
					VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd[2];
				uint8_t t0_cmd3 =
					VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd[3];
				uint8_t t0_cmd4 =
					VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd[4];
				uint8_t t0_cmd5 =
					VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd[5];
				uint8_t t0_cmd7 =
					VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd[7];
				uint8_t t0_cmd8 =
					VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd[8];
				bool t0_lba60_read10 =
					t0_cmd0 == 0x28 && t0_cmd2 == 0x00 && t0_cmd3 == 0x00 &&
					t0_cmd4 == 0x00 && t0_cmd5 == 0x60 && t0_cmd7 == 0x00 && t0_cmd8 == 0x02;
				bool t0_interesting_data =
					t0_data_cnt < 96 ||
					(t0_data_cnt >= 496 && t0_data_cnt < 544) ||
					(t0_data_cnt >= 1008 && t0_data_cnt < 1028);

				if (t0_lba60_read10 &&
				    VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__phase == 2 &&
				    t0_data_cnt != scsi_debug_prev_t0_data_cnt &&
				    t0_interesting_data &&
				    scsi_debug_t0_data_count < scsi_debug_t0_data_max) {
					fprintf(stderr,
						"SCSI_T0_DATA frame=%d tick=%08X time=%llu pc=%08X cnt=%u busdin=%02X ack=%d req=%d "
						"sd_rd=%02X sd_ack=%02X sd_wr=%d sd_addr=%02X sel=%d reqrd=%d done=%d\n",
						video.count_frame,
						lowmem_tick_016a(),
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						t0_data_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din,
						((VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr & 0x10) || VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_ack) ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_req,
						VERTOPINTERN->sd_rd,
						VERTOPINTERN->sd_ack,
						VERTOPINTERN->sd_buff_wr ? 1 : 0,
						VERTOPINTERN->sd_buff_addr,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__sd_buff_sel ? 1 : 0,
						0 /* req_rd inlined by verilator 5.049 */,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_complete ? 1 : 0);
					scsi_debug_t0_data_count++;
				}
				scsi_debug_prev_t0_data_cnt = t0_data_cnt;

				bool bus_active = !VERTOPINTERN->debug_cpuAS;
				uint32_t dma_addr = VERTOPINTERN->debug_cpuAddr;
				bool pseudo_dma_cycle =
					bus_active && !scsi_debug_prev_bus_control &&
					((dma_addr >= 0x50F06000u && dma_addr <= 0x50F06FFFu) ||
					 (dma_addr >= 0x50F12000u && dma_addr <= 0x50F13FFFu));
				if (pseudo_dma_cycle && scsi_debug_dma_count < scsi_debug_dma_max) {
					uint16_t cpu_data = VERTOPINTERN->debug_cpuDataOut;
					fprintf(stderr,
						"SCSI_DMA frame=%d tick=%08X time=%llu pc=%08X %s addr=%08X din=%04X dout=%04X "
						"uds=%d lds=%d dtack=%d dreq=%d dmaen=%d pmatch=%d t0_phase=%d t0_cnt=%u t0_done=%d busdin=%02X\n",
						video.count_frame,
						lowmem_tick_016a(),
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						VERTOPINTERN->debug_cpuRW ? "RD" : "WR",
						dma_addr,
						VERTOPINTERN->debug_cpuDataIn,
						cpu_data,
						!VERTOPINTERN->debug_cpuUDS ? 1 : 0,
						!VERTOPINTERN->debug_cpuLDS ? 1 : 0,
						!VERTOPINTERN->debug_cpuDTACK ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dreq_r ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_en ? 1 : 0,
						scsi_debug_pmatch() ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__phase,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_complete ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din);
					scsi_debug_dma_count++;
				}
				if (bus_active && !scsi_debug_prev_bus_control &&
				    VERTOPINTERN->debug_selectSCSI &&
				    scsi_debug_count < scsi_debug_max) {
					uint32_t addr = VERTOPINTERN->debug_cpuAddr;
					uint8_t reg = (addr >> 4) & 0x07;
					bool rw = VERTOPINTERN->debug_cpuRW;
					uint16_t data_in = VERTOPINTERN->debug_cpuDataIn;
					uint16_t data_out = VERTOPINTERN->debug_cpuDataOut;
					uint8_t mr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__mr;
					uint8_t icr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr;
					uint8_t tcr = VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__tcr;

					fprintf(stderr,
						"SCSI_DBG frame=%d tick=%08X time=%llu pc=%08X %s addr=%08X reg=%u din=%04X dout=%04X "
						"csr=%02X bsr=%02X pmatch=%d dmaen=%d dack=%d mr=%02X icr=%02X tcr=%02X odr=%02X busdin=%02X arb=%d arb_count=%02X "
						"req=%d tbsy=%02X treq=%02X tmsg=%02X tcd=%02X tio=%02X "
						"t0_phase=%d t0_mnt=%d t0_ack=%d t0_cmd=%d t0_cnt=%u t0_done=%d "
						"cdph=%u cdcnt=%u cdcmd0=%02X cdstat=%02X\n",
						video.count_frame,
						lowmem_tick_016a(),
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						rw ? "RD" : "WR",
						addr,
						reg,
						data_in,
						data_out,
						scsi_debug_csr(),
						scsi_debug_bsr(),
						scsi_debug_pmatch() ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_en ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_ack ? 1 : 0,
						mr,
						icr,
						tcr,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dout,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__arb_active ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__arb_count,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__scsi_req ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_bsy,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_req,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_msg,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_cd,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target_io,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__phase,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__mounted ? 1 : 0,
						((VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr & 0x10) || VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_ack) ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_complete ? 1 : 0,
						0, 0, 0, 0);  // empty_cd gone (MacLC transplant)
					scsi_debug_count++;
				}
				scsi_debug_prev_bus_control = bus_active;
			}

			if (iwm_debug_enable && !*bus.ioctl_download) {
				bool bus_active = !VERTOPINTERN->debug_cpuAS;
				if (bus_active && !iwm_debug_prev_bus_control &&
				    VERTOPINTERN->debug_selectIWM &&
				    video.count_frame >= iwm_debug_min_frame &&
				    iwm_debug_count < iwm_debug_max) {
					uint32_t addr = VERTOPINTERN->debug_cpuAddr;
					uint8_t reg = (addr >> 9) & 0x0f;
					bool rw = VERTOPINTERN->debug_cpuRW;
					uint16_t data_in = VERTOPINTERN->debug_cpuDataIn;
					uint16_t data_out = VERTOPINTERN->debug_cpuDataOut;
					bool iwm_select_ext = VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__selectExternalDrive;
					bool iwm_select_ext_next = VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__selectExternalDriveNext;
					bool iwm_enable = 0 /*swim-port: HUD tap retired*/;
					bool iwm_enable_next = VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__anyDiskEnableD;

					fprintf(stderr,
						"IWM_DBG frame=%d tick=%08X time=%llu pc=%08X %s addr=%08X reg=%X din=%04X dout=%04X "
						"ca=%d%d%d caN=%d%d%d sel=%d selN=%d enI=%d enIN=%d enE=%d enEN=%d q=%d%d qN=%d%d "
						"SEL=%d senseI=%d senseE=%d ri=%02X re=%02X latch=%02X clr=%X arm=%03X nbI=%d nbE=%d "
						"trkI=%02X sideI=%d imgI=%02X timerI=%02X readyI=%d iregs=%04X eregs=%04X\n",
						video.count_frame,
						lowmem_tick_016a(),
						(unsigned long long)main_time,
						VERTOPINTERN->debug_pc,
						rw ? "RD" : "WR",
						addr,
						reg,
						data_in,
						data_out,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__ca2 ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__ca1 ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__ca0 ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__ca2Next ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__ca1Next ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__ca0Next ? 1 : 0,
						iwm_select_ext ? 1 : 0,
						iwm_select_ext_next ? 1 : 0,
						(iwm_enable && !iwm_select_ext) ? 1 : 0,
						(iwm_enable_next && !iwm_select_ext_next) ? 1 : 0,
						(iwm_enable && iwm_select_ext) ? 1 : 0,
						(iwm_enable_next && iwm_select_ext_next) ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__q7 ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__q6 ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__q7Next ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__q6Next ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__SEL ? 1 : 0,
						(0 /*swim-port: HUD tap retired*/ >> 7) & 1,
						(0 /*swim-port: HUD tap retired*/ >> 7) & 1,
						0 /*swim-port: HUD tap retired*/,
						0 /*swim-port: HUD tap retired*/,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__readDataLatch,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__readLatchClearTimer,
						VERTOPINTERN->emu__DOT__dc0__DOT__sw__DOT__readDataArmDelay,
						0 /*swim-port: HUD tap retired*/ ? 1 : 0,
						0 /*swim-port: HUD tap retired*/ ? 1 : 0,
						0 /*swim-port: HUD tap retired*/,
						0 /*swim-port: HUD tap retired*/ ? 1 : 0,
						0 /*swim-port: HUD tap retired*/,
						0 /*swim-port: HUD tap retired*/,
						0 /*swim-port: HUD tap retired*/ ? 1 : 0,
						0 /*swim-port: HUD tap retired*/,
						0 /*swim-port: HUD tap retired*/);
					iwm_debug_count++;
				}
				iwm_debug_prev_bus_control = bus_active;
			}

			if (nubus_video_debug_enable && !*bus.ioctl_download) {
				bool bus_control = VERTOPINTERN->debug_cpuBusControl;
				static bool nubus_video_debug_prev_ack = false;
				static bool nubus_video_debug_read_pending = false;
				static uint32_t nubus_video_debug_addr = 0;
				static uint32_t nubus_video_debug_local = 0;
				static uint32_t nubus_video_debug_pc = 0;
				static const char* nubus_video_debug_cat = "OTHER";
				static int nubus_video_debug_pending_cat_id = 0;
				static int nubus_video_debug_rom_count = 0;
				static int nubus_video_debug_vram_r_count = 0;
				static int nubus_video_debug_vram_w_count = 0;
				static int nubus_video_debug_reg_w_count = 0;
				static int nubus_video_debug_ramdac_w_count = 0;
				static int nubus_video_debug_vbl_count = 0;
				bool ack_now = !VERTOPINTERN->emu__DOT__nubusAck_card;
				if (bus_control && !nubus_video_debug_prev_bus_control &&
				    VERTOPINTERN->debug_selectNuBus &&
				    nubus_video_debug_count < nubus_video_debug_max) {
					uint32_t addr = VERTOPINTERN->debug_cpuAddr;
					uint32_t local = addr & 0x00FFFFFF;
					uint32_t low = local & 0x0FFFFF;
					bool is_vbl_status = ((local & 0x0F0000) == 0x090000) &&
						((local & 0x0000FF) == 0x10 || (local & 0x0000FF) == 0x12);
					bool is_vbl_control = ((local & 0x0F0000) == 0x0A0000) &&
						((local & 0x0000FF) == 0x00 || (local & 0x0000FF) == 0x04);
					bool is_vram_write = !VERTOPINTERN->debug_cpuRW &&
						(low < 0x080000);
					bool is_vram_read = VERTOPINTERN->debug_cpuRW &&
						(low < 0x080000);
					bool is_reg_write = !VERTOPINTERN->debug_cpuRW &&
						(low >= 0x080000 && low <= 0x08FFFF);
					bool is_ramdac_write = !VERTOPINTERN->debug_cpuRW &&
						(low >= 0x090000 && low <= 0x09FFFF);
					bool is_declrom_read = VERTOPINTERN->debug_cpuRW &&
						!(low < 0x080000 ||
						  (low >= 0x080000 && low <= 0x08FFFF) ||
						  (low >= 0x090000 && low <= 0x09FFFF) ||
						  (low >= 0x0A0000 && low <= 0x0AFFFF));

					if (is_vbl_status || is_vbl_control ||
					    (nubus_video_debug_full &&
					     (is_vram_write || is_vram_read || is_reg_write || is_ramdac_write || is_declrom_read))) {
						const char* cat = is_declrom_read ? "ROM" :
							is_vram_write ? "VRAM_W" :
							is_vram_read ? "VRAM_R" :
							is_reg_write ? "REG_W" :
							is_ramdac_write ? "RAMDAC_W" :
							is_vbl_control ? "VBL_CTL" :
							is_vbl_status ? "VBL_STAT" : "OTHER";
						int cat_id = is_declrom_read ? 1 :
							is_vram_read ? 2 :
							is_vram_write ? 3 :
							is_reg_write ? 4 :
							is_ramdac_write ? 5 :
							(is_vbl_control || is_vbl_status) ? 6 : 0;
						bool can_log_cat =
							(cat_id == 1) ? (nubus_video_debug_rom_count < 160) :
							(cat_id == 2) ? (nubus_video_debug_vram_r_count < 64) :
							(cat_id == 3) ? (nubus_video_debug_vram_w_count < 160) :
							(cat_id == 4) ? (nubus_video_debug_reg_w_count < 128) :
							(cat_id == 5) ? (nubus_video_debug_ramdac_w_count < 256) :
							(cat_id == 6) ? (nubus_video_debug_vbl_count < 160) : true;
						if (can_log_cat && VERTOPINTERN->debug_cpuRW) {
							nubus_video_debug_read_pending = true;
							nubus_video_debug_addr = addr;
							nubus_video_debug_local = local;
							nubus_video_debug_pc = VERTOPINTERN->debug_pc;
							nubus_video_debug_cat = cat;
							nubus_video_debug_pending_cat_id = cat_id;
						} else if (can_log_cat) {
							fprintf(stderr,
								"NUBUS_VIDEO_DBG frame=%d tick=%08X time=%llu pc=%08X ipl=%u nirq=%u vbl_irq=%u vbl_dis=%u via2_ifr=%02X via2_ier=%02X %s WR addr=%08X local=%06X data_in=%04X data_out=%04X\n",
								video.count_frame,
								lowmem_tick_016a(),
								(unsigned long long)main_time,
								VERTOPINTERN->debug_pc,
								VERTOPINTERN->debug_cpuIPL,
								VERTOPINTERN->emu__DOT__nubus_irq_n,
								VERTOPINTERN->emu__DOT__nubus_card__DOT__irq_active,
								(uint8_t)(!VERTOPINTERN->emu__DOT__nubus_card__DOT__vblank_enable),
								VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__irq_flags,
								VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__irq_mask,
								cat,
								addr,
								local,
								VERTOPINTERN->debug_cpuDataIn,
								VERTOPINTERN->debug_cpuDataOut);
							nubus_video_debug_count++;
							if (cat_id == 3) nubus_video_debug_vram_w_count++;
							else if (cat_id == 4) nubus_video_debug_reg_w_count++;
							else if (cat_id == 5) nubus_video_debug_ramdac_w_count++;
							else if (cat_id == 6) nubus_video_debug_vbl_count++;
						}
					}
				}
				if (nubus_video_debug_read_pending && ack_now && !nubus_video_debug_prev_ack &&
				    nubus_video_debug_count < nubus_video_debug_max) {
					fprintf(stderr,
						"NUBUS_VIDEO_DBG frame=%d tick=%08X time=%llu pc=%08X ipl=%u nirq=%u vbl_irq=%u vbl_dis=%u via2_ifr=%02X via2_ier=%02X %s RD addr=%08X local=%06X data_in=%04X data_out=%04X\n",
						video.count_frame,
						lowmem_tick_016a(),
						(unsigned long long)main_time,
						nubus_video_debug_pc,
						VERTOPINTERN->debug_cpuIPL,
						VERTOPINTERN->emu__DOT__nubus_irq_n,
						VERTOPINTERN->emu__DOT__nubus_card__DOT__irq_active,
						(uint8_t)(!VERTOPINTERN->emu__DOT__nubus_card__DOT__vblank_enable),
						VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__irq_flags,
						VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__irq_mask,
						nubus_video_debug_cat,
						nubus_video_debug_addr,
						nubus_video_debug_local,
						VERTOPINTERN->debug_cpuDataIn,
						VERTOPINTERN->debug_cpuDataOut);
					nubus_video_debug_count++;
					if (nubus_video_debug_pending_cat_id == 1) nubus_video_debug_rom_count++;
					else if (nubus_video_debug_pending_cat_id == 2) nubus_video_debug_vram_r_count++;
					else if (nubus_video_debug_pending_cat_id == 6) nubus_video_debug_vbl_count++;
					nubus_video_debug_read_pending = false;
				}
				nubus_video_debug_prev_bus_control = bus_control;
				nubus_video_debug_prev_ack = ack_now;
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
				static uint32_t poll268_last_pc = 0xFFFFFFFF;
				static uint32_t poll268_hist[32] = {0};
				static int poll268_hist_pos = 0;
				static uint32_t poll268_hist_last_pc = 0xFFFFFFFF;
				uint32_t pc = VERTOPINTERN->debug_pc;
				if (VERTOPINTERN->debug_fetch_valid && pc != poll268_hist_last_pc) {
					poll268_hist[poll268_hist_pos & 31] = pc;
					poll268_hist_pos++;
					poll268_hist_last_pc = pc;
				}
				bool scsi_cycle = VERTOPINTERN->debug_cpuBusControl && VERTOPINTERN->debug_selectSCSI;
				bool scsi_rom_window = (pc >= 0x408268D0 && pc <= 0x40826990) ||
				                       (pc >= 0x40826CB6 && pc <= 0x40826D1C);
				bool scsi_dispatch_window = (video.count_frame >= 180 && pc >= 0x408064BA && pc <= 0x40806566) ||
				                            (pc >= 0x40826680 && pc <= 0x408268D8);
				bool log_dispatch_fetch = scsi_dispatch_window &&
				                          VERTOPINTERN->debug_fetch_valid &&
				                          pc != poll268_last_pc &&
				                          pc != 0x40826CA8 &&
				                          pc != 0x40826CAC;
				bool log_scsi_cycle = scsi_rom_window && scsi_cycle;
				if (poll268_log_count < 1600 && (log_scsi_cycle || log_dispatch_fetch)) {
					poll268_last_pc = pc;
					uint32_t d1 = tg68_reg(1);
					uint32_t d5 = tg68_reg(5);
					uint32_t d7 = tg68_reg(7);
					uint32_t a3 = tg68_reg(11);
					uint32_t a4 = tg68_reg(12);
					uint32_t a6 = tg68_reg(14);
					uint32_t a7 = tg68_reg(15);
					if (log_dispatch_fetch &&
					    (pc == 0x408064BA || pc == 0x408266A4 || pc == 0x4082672A)) {
						fprintf(stderr,
							"POLL268_HISTORY frame=%d tick=%08X pc=%08X hist=%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X "
							"%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X "
							"a6=%08X a7=%08X stack=%04X,%04X,%04X,%04X,%04X,%04X,%04X,%04X\n",
							video.count_frame,
							lowmem_tick_016a(),
							pc,
							poll268_hist[(poll268_hist_pos - 32) & 31],
							poll268_hist[(poll268_hist_pos - 31) & 31],
							poll268_hist[(poll268_hist_pos - 30) & 31],
							poll268_hist[(poll268_hist_pos - 29) & 31],
							poll268_hist[(poll268_hist_pos - 28) & 31],
							poll268_hist[(poll268_hist_pos - 27) & 31],
							poll268_hist[(poll268_hist_pos - 26) & 31],
							poll268_hist[(poll268_hist_pos - 25) & 31],
							poll268_hist[(poll268_hist_pos - 24) & 31],
							poll268_hist[(poll268_hist_pos - 23) & 31],
							poll268_hist[(poll268_hist_pos - 22) & 31],
							poll268_hist[(poll268_hist_pos - 21) & 31],
							poll268_hist[(poll268_hist_pos - 20) & 31],
							poll268_hist[(poll268_hist_pos - 19) & 31],
							poll268_hist[(poll268_hist_pos - 18) & 31],
							poll268_hist[(poll268_hist_pos - 17) & 31],
							poll268_hist[(poll268_hist_pos - 16) & 31],
							poll268_hist[(poll268_hist_pos - 15) & 31],
							poll268_hist[(poll268_hist_pos - 14) & 31],
							poll268_hist[(poll268_hist_pos - 13) & 31],
							poll268_hist[(poll268_hist_pos - 12) & 31],
							poll268_hist[(poll268_hist_pos - 11) & 31],
							poll268_hist[(poll268_hist_pos - 10) & 31],
							poll268_hist[(poll268_hist_pos - 9) & 31],
							poll268_hist[(poll268_hist_pos - 8) & 31],
							poll268_hist[(poll268_hist_pos - 7) & 31],
							poll268_hist[(poll268_hist_pos - 6) & 31],
							poll268_hist[(poll268_hist_pos - 5) & 31],
							poll268_hist[(poll268_hist_pos - 4) & 31],
							poll268_hist[(poll268_hist_pos - 3) & 31],
							poll268_hist[(poll268_hist_pos - 2) & 31],
							poll268_hist[(poll268_hist_pos - 1) & 31],
							a6,
							a7,
							ram_word(a7 & 0x1FFFFF),
							ram_word((a7 + 2) & 0x1FFFFF),
							ram_word((a7 + 4) & 0x1FFFFF),
							ram_word((a7 + 6) & 0x1FFFFF),
							ram_word((a7 + 8) & 0x1FFFFF),
							ram_word((a7 + 10) & 0x1FFFFF),
							ram_word((a7 + 12) & 0x1FFFFF),
							ram_word((a7 + 14) & 0x1FFFFF));
					}
					fprintf(stderr,
						"POLL268 %s @%llu frame=%d tick=%08X pc=%08X op=%04X addr=%08X rw=%d fc=%d din=%04X dout=%04X "
						"bc=%d via=%d via2=%d scsi=%d scc=%d iwm=%d nubus=%d ram=%d rom=%d "
						"mr=%02X icr=%02X tcr=%02X odr=%02X busdin=%02X req=%d tbsy=%02X treq=%02X "
						"sd_rd=%02X sd_ack=%02X sd_wr=%d sd_addr=%02X "
						"t0_phase=%d t0_mnt=%d t0_din=%02X t0_ack=%d t0_cmd=%d t0_cnt=%u t0_done=%d t0_sel=%d t0_reqrd=%d "
						"t1_phase=%d t1_mnt=%d t1_cmd=%d "
						"arb=%d arb_count=%02X "
						"d0=%08X d1=%08X d2=%08X d5=%08X d6=%08X d7=%08X "
						"a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a6=%08X a3+10=%08X a3+20=%08X "
						"m_a4_61=%02X m_a6_08=%04X m_a6_0a=%04X m_a6_0c=%04X m_a6_14=%04X\n",
						log_scsi_cycle ? "BUS" : "FETCH",
						(unsigned long long)main_time,
						video.count_frame,
						lowmem_tick_016a(),
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
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__din,
						((VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__icr & 0x10) || VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__dma_ack) ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__cmd_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__data_complete ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__0__KET____DOT__target__DOT__sd_buff_sel ? 1 : 0,
						0 /* req_rd inlined by verilator 5.049 */,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__1__KET____DOT__target__DOT__phase,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__1__KET____DOT__target__DOT__mounted ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__target__BRA__1__KET____DOT__target__DOT__cmd_cnt,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__arb_active ? 1 : 0,
						VERTOPINTERN->emu__DOT__dc0__DOT__scsi__DOT__arb_count,
						tg68_reg(0), d1, tg68_reg(2), d5, tg68_reg(6), d7,
						tg68_reg(8), tg68_reg(9), tg68_reg(10), a3, a4, tg68_reg(14),
						a3 + 0x10, a3 + 0x20,
						ram_byte((a4 + 0x61) & 0x1FFFFF),
						ram_word((tg68_reg(14) + 0x08) & 0x1FFFFF),
						ram_word((tg68_reg(14) + 0x0A) & 0x1FFFFF),
						ram_word((tg68_reg(14) + 0x0C) & 0x1FFFFF),
						ram_word((tg68_reg(14) + 0x14) & 0x1FFFFF));
					poll268_log_count++;
				}
			}
			if (scc_bus_debug_enable && !*bus.ioctl_download) {
				bool bus_control = VERTOPINTERN->debug_cpuBusControl;
				bool select_scc = VERTOPINTERN->debug_selectSCC;
				uint32_t pc = VERTOPINTERN->debug_pc;
				bool focused_pc = (pc >= 0x40800540 && pc <= 0x40800820) ||
				                  (pc >= 0x40803280 && pc <= 0x40803310);
				if (bus_control && !scc_bus_debug_prev_bus_control && select_scc &&
				    (scc_bus_debug_count < 220 || focused_pc) &&
				    scc_bus_debug_count < scc_bus_debug_max) {
					fprintf(stderr,
						"SCC_BUS @%llu pc=%08X op=%04X addr=%08X rw=%d din=%04X dout=%04X "
						"rs=%u rr0a=%02X rr0b=%02X rpa=%X rpb=%X sta=%u stb=%u "
						"wr1a=%02X wr3a=%02X wr5a=%02X wr14a=%02X rxpa=%u txea=%u\n",
						(unsigned long long)main_time,
						pc,
						VERTOPINTERN->debug_opcode,
						VERTOPINTERN->debug_cpuAddr,
						VERTOPINTERN->debug_cpuRW,
						VERTOPINTERN->debug_cpuDataIn,
						VERTOPINTERN->debug_cpuDataOut,
						VERTOPINTERN->debug_cpuAddr & 3,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__rr0_a,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__rr0_b,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__rindex_a,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__rindex_b,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__scc_state_a,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__scc_state_b,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr1_a,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr3_a,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr5_a,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__wr14_a,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__rx_queue_pos_a,
						VERTOPINTERN->emu__DOT__dc0__DOT__s__DOT__tx_empty_latch_a);
					scc_bus_debug_count++;
				}
				scc_bus_debug_prev_bus_control = bus_control;
			}
			if (ram_size_cpu_debug_enable && !*bus.ioctl_download) {
				uint32_t pc = VERTOPINTERN->debug_pc;
				if (VERTOPINTERN->debug_fetch_valid &&
				    pc >= 0x40803944 && pc <= 0x408039ff &&
				    pc != ram_size_cpu_debug_last_pc &&
				    ram_size_cpu_debug_count < ram_size_cpu_debug_max) {
					ram_size_cpu_debug_last_pc = pc;
					fprintf(stderr,
						"RAM_SIZE_CPU[%03d] t=%llu pc=%08X op=%04X addr=%08X rw=%d "
						"D0=%08X D5=%08X D6=%08X A2=%08X A3=%08X "
						"MEM0=%04X%04X MEM200000=%04X%04X VIA2_PRA=%02X DDRA=%02X IRA=%02X\n",
						ram_size_cpu_debug_count,
						(unsigned long long)main_time,
						pc,
						VERTOPINTERN->debug_opcode,
						VERTOPINTERN->debug_cpuAddr,
						VERTOPINTERN->debug_cpuRW,
						tg68_reg(0),
						tg68_reg(5),
						tg68_reg(6),
						tg68_reg(10),
						tg68_reg(11),
						VERTOPINTERN->emu__DOT__ram__DOT__mem[0],
						VERTOPINTERN->emu__DOT__ram__DOT__mem[1],
						VERTOPINTERN->emu__DOT__ram__DOT__mem[0x100000],
						VERTOPINTERN->emu__DOT__ram__DOT__mem[0x100001],
						VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__pio_i_pra,
						VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__pio_i_ddra,
						VERTOPINTERN->emu__DOT__dc0__DOT__via2__DOT__ira);
					ram_size_cpu_debug_count++;
				}
			}
			if (verbose_debug_enable) {
			// Print progress every 10 million cycles (~319ms of simulated time at 31.3344MHz)
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
			// berr-rerun / format-$B RTE incident tracer (2026-07-12)
			// Question under test: after a handler RTEs a format-$B frame, does
			// TG68K's berr_inhibit window (a) fire even when the handler left
			// SSW.DF=1 (DF latch samples the format word, whose bit8 is always 0),
			// (b) feed berr_data_buf into the instruction FETCH after RTE (garbage
			// opcode into the decode stream), (c) hold the right DIB value at all?
			// Per incident: every FC=5 write (frame push descending + handler
			// fixup writes into the frame), every FC=5 read (RTE pops ascending),
			// the inhibit window with berr_data, then the next bus cycles with
			// the word the CPU actually received.
			{
				static int inc_n = 0;
				static bool inc_open = false;
				static int inc_wr = 0, inc_rd = 0, inc_post = 0;
				static uint64_t inc_ev = 0;
				static bool last_inh = false;
				static const int MAX_INC = 14;
				bool inh = VERTOPINTERN->debug_berr_inhibit != 0;
				static int last_berr2 = 0;
				int berr_now2 = VERTOPINTERN->debug_berr ? 1 : 0;
				if (berr_now2 && !last_berr2 && !*bus.ioctl_download && inc_n < MAX_INC) {
					inc_n++; inc_open = true; inc_wr = inc_rd = inc_post = 0; inc_ev = 0;
					fprintf(stderr, "[BINC %d] START cycle=%llu pc=%08X addr=%08X\n",
						inc_n, (unsigned long long)main_time,
						VERTOPINTERN->debug_pc, VERTOPINTERN->debug_cpuAddr);
				}
				last_berr2 = berr_now2;
				if (inc_open && VERTOPINTERN->debug_busev_valid) {
					uint32_t a = VERTOPINTERN->debug_busev_addr;
					uint16_t d = VERTOPINTERN->debug_busev_data;
					int rw = VERTOPINTERN->debug_busev_rw;
					int fc = VERTOPINTERN->debug_busev_fc;
					inc_ev++;
					if (inc_post > 0) {
						fprintf(stderr, "[BINC %d] POST%d %s a=%08X fc=%d d=%04X inh=%d pc=%08X\n",
							inc_n, 13 - inc_post, rw ? "RD" : "WR", a, fc, d, inh ? 1 : 0,
							VERTOPINTERN->debug_pc);
						if (--inc_post == 0) { inc_open = false; fprintf(stderr, "[BINC %d] END\n", inc_n); }
					} else if (fc == 5 && !rw && inc_wr < 120) {
						fprintf(stderr, "[BINC %d] WR %08X = %04X (pc=%08X)\n",
							inc_n, a, d, VERTOPINTERN->debug_pc);
						inc_wr++;
					} else if (fc == 5 && rw && inc_rd < 96) {
						fprintf(stderr, "[BINC %d] RD %08X = %04X\n", inc_n, a, d);
						inc_rd++;
					}
					if (inc_ev > 60000 && inc_post == 0) {
						inc_open = false;
						fprintf(stderr, "[BINC %d] END-TIMEOUT (no inhibit window seen)\n", inc_n);
					}
				}
				if (inh && !last_inh) {
					fprintf(stderr, "[BINC %d] INHIBIT_ON cycle=%llu berr_data=%08X pc=%08X\n",
						inc_n, (unsigned long long)main_time,
						(uint32_t)VERTOPINTERN->debug_berr_data, VERTOPINTERN->debug_pc);
					if (inc_open) inc_post = 12;
				}
				if (!inh && last_inh)
					fprintf(stderr, "[BINC %d] INHIBIT_OFF cycle=%llu\n",
						inc_n, (unsigned long long)main_time);
				last_inh = inh;
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
	printf("  --periph-debug                Enable peripheral access logging to periph_debug.log\n");
	printf("  --verbose-debug               Enable ad-hoc boot diagnostics on stderr\n");
	printf("  +poll268_debug, --poll268-debug\n");
	printf("                                Trace the ROM wait loop around PC 408268F8\n");
	printf("  --scsi-debug                  Trace focused NCR5380 bus transactions\n");
	printf("  --scsi-debug-min-frame <n>    Start SCSI debug logging at frame n\n");
	printf("  --scsi-timeout-loop-debug     Trace ROM SCSI timeout DBNE loop state\n");
	printf("  --iwm-debug                   Trace focused IWM/floppy bus transactions\n");
	printf("  --iwm-debug-min-frame <n>     Delay IWM tracing until frame n\n");
	printf("  --iwm-state-debug             Trace ROM floppy drive queue state near PC 0082E220\n");
	printf("  --boot-decision-debug         Trace SCSI/floppy boot-decision ROM PCs\n");
	printf("  --boot-decision-debug-min-frame <n>\n");
	printf("  --bootmask-once-debug         Stop at the first boot-device scan/SCSI ROM PC and dump PC history\n");
	printf("  --scsi-transition-debug       Stop at the late no-media-to-SCSI transition and dump PC history\n");
	printf("  --scsi-transition-debug-min-frame <n>\n");
	printf("  --late-adb-debug              Stop at the late ADB/VIA bit-bang ROM path and dump PC history\n");
	printf("  --late-adb-debug-min-frame <n>\n");
	printf("  --bus-handshake-debug         Trace CPU AS/VPA/VMA/DTACK handshakes for I/O cycles\n");
	printf("  --bus-handshake-debug-min-frame <n>\n");
	printf("  --wait-debug                  Trace ROM wait helper around PC 40801610\n");
	printf("  --wait-debug-min-frame <n>    Delay wait-helper tracing until frame n\n");
	printf("  --calib-debug                 Trace VIA timers and low-memory delay calibration\n");
	printf("  --calib-loop-debug            Trace delay calibration DBF loop counts and VIA1 T2 state\n");
	printf("  --force-mame-calib            Force MAME delay words $0D00/$0DA6 for timing diagnosis\n");
	printf("  --force-calib <0d00> <0da6>   Force custom delay words for timing diagnosis\n");
	printf("  --force-calib-min-frame <n>   Delay forced calibration writes until frame n\n");
	printf("  --ramtest-debug               Trace ROM RAM-test pass/fail PCs and register state\n");
	printf("  --scc-bus-debug              Trace focused CPU SCC bus transactions\n");
	printf("  --ram-size-cpu-debug          Trace CPU state through ROM RAM sizing\n");
	printf("  --frame-probe                 Print one-line PC/register summaries at frame boundaries\n");
	printf("  --frame-interval <n>          Frame-probe print interval (default 10)\n");
	printf("  --nubus-video-debug           Trace focused NuBus video VBL/control accesses\n");
	printf("  --nubus-video-full-debug      Also include NuBus video VRAM/register/RAMDAC writes\n");
	printf("  --scsi0 <file>                Mount a SCSI disk image on target 0 (ID 6)\n");
	printf("  --scsi1 <file>                Mount a SCSI disk image on target 1 (ID 5)\n");
	printf("  --floppy0 <file>              Insert a raw .dsk image in the internal floppy drive\n");
	printf("  --floppy1 <file>              Insert a raw .dsk image in the external floppy drive\n");
	printf("  --ram <1|2|4|8>               RAM size in MB (default 8)\n");
	printf("  --rom <file>                  Override the boot0 ROM (default ../releases/boot0.rom)\n");
	printf("  --no-memtest                  Fast boot: load ../releases/boot0-nomemtest.rom (skips power-on RAM test)\n");
	printf("  --send-mouse <frame>:<dx>,<dy>[,<btn>[,<dur>]]\n");
	printf("                                Send headless mouse input at specified frame\n");
	printf("  --screenshot <frames>         Take screenshots at specified frame numbers\n");
	printf("                                (comma-separated list, e.g., 100,200,300)\n");
	printf("  --stop-at-frame <frame>       Exit simulation after specified frame\n");
	printf("  --stop-at-tick <hex|dec>      Exit after low-memory tick long $016A reaches value\n");
	printf("  --stop-at-pc <hex|dec>        Exit when debug PC is fetched\n");
	printf("\n");
	printf("Examples:\n");
	printf("  ./Vemu                        Run simulator in windowed mode\n");
	printf("  ./Vemu --screenshot 245       Take screenshot at frame 245\n");
	printf("  ./Vemu --stop-at-frame 300    Stop simulation after frame 300\n");
	printf("  ./Vemu --headless --stop-at-tick 0x75\n");
	printf("  ./Vemu --headless --screenshot 50 --stop-at-frame 100\n");
	printf("                                Headless, take screenshot at frame 50, stop at 100\n");
	printf("  ./Vemu --headless --send-mouse 500:20,0 --stop-at-frame 520\n");
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

static const char* frame_region_for_pc(uint32_t pc) {
	if (pc >= 0x40805e4a && pc <= 0x40805f7c) {
		return "asc_selftest";
	}
	if (pc >= 0x4080dde0 && pc <= 0x4080de70) {
		return "via_adb_rtc";
	}
	if (pc >= 0x40803d00 && pc <= 0x40804400) {
		return "nubus_declrom";
	}
	if (pc >= 0x4080151c && pc <= 0x408017cc) {
		return "wait_helper";
	}
	return "";
}

static void maybe_print_frame_probe() {
	if (!frame_probe_enable || video.count_frame == frame_probe_last_frame) {
		return;
	}

	frame_probe_last_frame = video.count_frame;
	if (video.count_frame != 1 &&
	    frame_probe_interval > 0 &&
	    (video.count_frame % frame_probe_interval) != 0 &&
	    (!stop_at_frame_enabled || video.count_frame < stop_at_frame)) {
		return;
	}

	uint32_t tick = (uint32_t(VERTOPINTERN->emu__DOT__ram__DOT__mem[0x00B5]) << 16) |
	                uint32_t(VERTOPINTERN->emu__DOT__ram__DOT__mem[0x00B6]);
	uint32_t pc = VERTOPINTERN->debug_pc;
	fprintf(stderr, "FRAME_PROBE frame=%d time=%llu tick016A=%08X pc=%08X op=%04X region=%s "
	        "D0=%08X D5=%08X D6=%08X A0=%08X A3=%08X MMUType=%02X MMU32=%02X "
	        "SysZ=%08X ApplZ=%08X ThZ=%08X HpEnd=%08X ApplLim=%08X MemTop=%08X BufPtr=%08X\n",
	        video.count_frame,
	        (unsigned long long)main_time,
	        tick,
	        pc,
	        VERTOPINTERN->debug_opcode,
	        frame_region_for_pc(pc),
	        tg68_reg(0),
	        tg68_reg(5),
	        tg68_reg(6),
	        tg68_reg(8),
	        tg68_reg(11),
	        ram_byte(0x0CB1),   // MMUType — 0 makes _SwapMMUMode a NO-OP
	        ram_byte(0x0CB2),   // MMU32Bit flag
	        ram_long(0x02A6),   // SysZone
	        ram_long(0x02AA),   // ApplZone
	        ram_long(0x0118),   // TheZone
	        ram_long(0x0114),   // HeapEnd
	        ram_long(0x0130),   // ApplLimit
	        ram_long(0x0108),   // MemTop
	        ram_long(0x010C));  // BufPtr
	fflush(stderr);
}

unsigned char mouse_clock = 0;
unsigned char mouse_buttons = 0;
signed char mouse_x = 0;
signed char mouse_y = 0;
int prev_mouse_buttons = 0;
bool mouse_captured = false;

struct MouseInjection {
	int frame;
	int dx;
	int dy;
	int buttons;
	int duration;
};
std::vector<MouseInjection> mouse_injections;
int mouse_injection_frames_remaining = 0;
static signed char injected_mouse_x = 0;
static signed char injected_mouse_y = 0;
static int injected_mouse_buttons = 0;
static bool mouse_injection_active = false;

static unsigned long build_mouse_packet(signed char dx, signed char dy, int buttons) {
	unsigned char status_byte = (buttons & 0x07) | 0x08;
	if (dx < 0) status_byte |= 0x10;
	if (dy < 0) status_byte |= 0x20;

	unsigned long mouse_temp = status_byte;
	mouse_temp |= ((unsigned char)dx << 8);
	mouse_temp |= ((unsigned char)dy << 16);
	if (mouse_clock) mouse_temp |= (1UL << 24);
	return mouse_temp;
}

static void apply_mouse_packet(signed char dx, signed char dy, int buttons) {
	if (dx != 0 || dy != 0 || buttons != prev_mouse_buttons) {
		mouse_clock = !mouse_clock;
	}
	prev_mouse_buttons = buttons;
	VERTOPINTERN->ps2_mouse = build_mouse_packet(dx, dy, buttons);
}

static bool process_mouse_injections(int current_frame) {
	static int last_processed_frame = -1;
	bool new_injection_started = false;

	auto it = mouse_injections.begin();
	while (it != mouse_injections.end()) {
		if (it->frame == current_frame) {
			injected_mouse_x = (signed char)std::max(-127, std::min(127, it->dx));
			injected_mouse_y = (signed char)std::max(-127, std::min(127, it->dy));
			injected_mouse_buttons = it->buttons;
			mouse_injection_frames_remaining = std::max(1, it->duration);
			mouse_injection_active = true;
			new_injection_started = true;
			printf("Injecting mouse at frame %d: dx=%d dy=%d btn=%d dur=%d\n",
			       current_frame, it->dx, it->dy, it->buttons, mouse_injection_frames_remaining);
			it = mouse_injections.erase(it);
		} else {
			++it;
		}
	}

	if (mouse_injection_active && !new_injection_started && current_frame != last_processed_frame) {
		mouse_injection_frames_remaining--;
		if (mouse_injection_frames_remaining <= 0) {
			injected_mouse_x = 0;
			injected_mouse_y = 0;
			injected_mouse_buttons = 0;
			mouse_injection_active = false;
		}
	}

	last_processed_frame = current_frame;
	return new_injection_started;
}

int main(int argc, char** argv, char** env) {
	// Parse command-line arguments
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
			show_help();
			return 0;
		} else if (strcmp(argv[i], "--headless") == 0 || strcmp(argv[i], "--no-gui") == 0) {
			headless = true;
		} else if (strcmp(argv[i], "--cpu-trace-min-frame") == 0 && i + 1 < argc) {
			cpu_trace_min_frame = std::stoi(argv[++i]);
		} else if (strcmp(argv[i], "--no-cpu-trace") == 0) {
			cpu_trace_enable = false;
		} else if (strcmp(argv[i], "--no-via-debug") == 0) {
			via_debug_enable = false;
		} else if (strcmp(argv[i], "--periph-debug") == 0) {
			periph_debug_enable = true;
		} else if (strcmp(argv[i], "--verbose-debug") == 0) {
			verbose_debug_enable = true;
		} else if (strcmp(argv[i], "--scsi-stall-history") == 0) {
			scsi_stall_history_enable = true;
		} else if (strcmp(argv[i], "--scsi-debug") == 0) {
			scsi_debug_enable = true;
		} else if (strcmp(argv[i], "--scsi-timeout-loop-debug") == 0) {
			scsi_timeout_loop_debug_enable = true;
		} else if (strcmp(argv[i], "--scsi-debug-min-frame") == 0 && i + 1 < argc) {
			scsi_debug_min_frame = std::stoi(argv[i + 1]);
			i++;
		} else if (strcmp(argv[i], "--iwm-debug") == 0) {
			iwm_debug_enable = true;
		} else if (strcmp(argv[i], "--iwm-debug-min-frame") == 0 && i + 1 < argc) {
			iwm_debug_min_frame = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--iwm-state-debug") == 0) {
			iwm_state_debug_enable = true;
		} else if (strcmp(argv[i], "--heapspray-debug") == 0) {
			heapspray_debug_enable = true;
		} else if (strcmp(argv[i], "--drvtrace") == 0) {
			drvtrace_enable = true;
		} else if (strcmp(argv[i], "--watch-range") == 0 && i + 1 < argc) {
			unsigned lo = 0, hi = 0; int mf = 0;
			if (sscanf(argv[++i], "%x:%x:%d", &lo, &hi, &mf) >= 2) {
				watch_range_enable = true;
				watch_range_lo = lo; watch_range_hi = hi;
				watch_range_min_frame = mf;
				printf("Write-watch on [%06X,%06X) from frame %d\n", lo, hi, mf);
			} else {
				printf("bad --watch-range (want LO:HI[:MINFRAME] hex:hex[:dec])\n");
			}
		} else if (strcmp(argv[i], "--boot-decision-debug") == 0) {
			boot_decision_debug_enable = true;
		} else if (strcmp(argv[i], "--boot-decision-debug-min-frame") == 0 && i + 1 < argc) {
			boot_decision_debug_min_frame = std::stoi(argv[i + 1]);
			i++;
		} else if (strcmp(argv[i], "--bootmask-once-debug") == 0) {
			bootmask_once_debug_enable = true;
		} else if (strcmp(argv[i], "--scsi-transition-debug") == 0) {
			scsi_transition_debug_enable = true;
		} else if (strcmp(argv[i], "--scsi-transition-debug-min-frame") == 0 && i + 1 < argc) {
			scsi_transition_debug_min_frame = std::stoi(argv[i + 1]);
			i++;
		} else if (strcmp(argv[i], "--late-adb-debug") == 0) {
			late_adb_debug_enable = true;
		} else if (strcmp(argv[i], "--late-adb-debug-min-frame") == 0 && i + 1 < argc) {
			late_adb_debug_min_frame = std::stoi(argv[i + 1]);
			i++;
		} else if (strcmp(argv[i], "--bus-handshake-debug") == 0) {
			bus_handshake_debug_enable = true;
		} else if (strcmp(argv[i], "--bus-handshake-debug-min-frame") == 0 && i + 1 < argc) {
			bus_handshake_debug_min_frame = std::stoi(argv[i + 1]);
			i++;
		} else if (strcmp(argv[i], "--wait-debug") == 0) {
			wait_debug_enable = true;
		} else if (strcmp(argv[i], "--wait-debug-min-frame") == 0 && i + 1 < argc) {
			wait_debug_min_frame = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--calib-debug") == 0) {
			calib_debug_enable = true;
		} else if (strcmp(argv[i], "--calib-loop-debug") == 0) {
			calib_loop_debug_enable = true;
		} else if (strcmp(argv[i], "--force-mame-calib") == 0) {
			force_calib_enable = true;
			force_calib_0d00 = 0x0A3B;
			force_calib_0da6 = 0x0417;
			force_calib_min_frame = 120;
		} else if (strcmp(argv[i], "--force-calib") == 0 && i + 2 < argc) {
			force_calib_enable = true;
			force_calib_0d00 = (uint16_t)strtoul(argv[++i], nullptr, 0);
			force_calib_0da6 = (uint16_t)strtoul(argv[++i], nullptr, 0);
		} else if (strcmp(argv[i], "--force-calib-min-frame") == 0 && i + 1 < argc) {
			force_calib_min_frame = std::stoi(argv[++i]);
		} else if (strcmp(argv[i], "--ramtest-debug") == 0) {
			ramtest_debug_enable = true;
		} else if (strcmp(argv[i], "--nubus-video-debug") == 0) {
			nubus_video_debug_enable = true;
		} else if (strcmp(argv[i], "--nubus-video-full-debug") == 0) {
			nubus_video_debug_enable = true;
			nubus_video_debug_full = true;
		} else if (strcmp(argv[i], "--scc-bus-debug") == 0) {
			scc_bus_debug_enable = true;
		} else if (strcmp(argv[i], "--ram-size-cpu-debug") == 0) {
			ram_size_cpu_debug_enable = true;
		} else if (strcmp(argv[i], "--frame-probe") == 0) {
			frame_probe_enable = true;
		} else if (strcmp(argv[i], "--frame-interval") == 0 && i + 1 < argc) {
			frame_probe_interval = std::stoi(argv[i + 1]);
			i++;
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
		} else if (strcmp(argv[i], "--rom") == 0 && i + 1 < argc) {
			rom_file_override = argv[++i];
			fprintf(stderr, "ROM override: %s\n", rom_file_override);
		} else if (strcmp(argv[i], "--no-memtest") == 0) {
			// Convenience: load the pre-patched ROM that skips the destructive
			// power-on RAM walk (see scripts/patch_rom_nomemtest.sh).
			rom_file_override = "../releases/boot0-nomemtest.rom";
			fprintf(stderr, "Fast boot: using no-memtest ROM %s\n", rom_file_override);
		} else if (strcmp(argv[i], "--ram") == 0 && i + 1 < argc) {
			// RAM size in MB: 1, 2, 4, or 8 -> configRAMSize 0/1/2/3
			int mb = atoi(argv[++i]);
			switch (mb) {
				case 1: cfg_memSize = 0; break;
				case 2: cfg_memSize = 1; break;
				case 4: cfg_memSize = 2; break;
				case 8: cfg_memSize = 3; break;
				default:
					fprintf(stderr, "Error: --ram must be 1, 2, 4, or 8 (got %s)\n", argv[i]);
					return 1;
			}
			printf("RAM size: %d MB (configRAMSize=%d)\n", mb, cfg_memSize);
		} else if (strcmp(argv[i], "--send-mouse") == 0 && i + 1 < argc) {
			std::string arg = argv[++i];
			size_t colon = arg.find(':');
			if (colon == std::string::npos) {
				fprintf(stderr, "Error: --send-mouse requires <frame>:<dx>,<dy>[,<btn>[,<dur>]]\n");
				return 1;
			}

			int frame = std::stoi(arg.substr(0, colon));
			std::string values = arg.substr(colon + 1);
			std::stringstream ss(values);
			std::string part;
			std::vector<int> nums;
			while (std::getline(ss, part, ',')) {
				nums.push_back(std::stoi(part));
			}
			if (nums.size() < 2) {
				fprintf(stderr, "Error: --send-mouse requires at least dx,dy values\n");
				return 1;
			}
			int btn = nums.size() >= 3 ? nums[2] : 0;
			int dur = nums.size() >= 4 ? nums[3] : 1;
			mouse_injections.push_back({frame, nums[0], nums[1], btn, dur});
			printf("Will send mouse at frame %d: dx=%d dy=%d btn=%d dur=%d\n",
			       frame, nums[0], nums[1], btn, dur);
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
			} else if (strcmp(argv[i], "--stop-at-tick") == 0 && i + 1 < argc) {
				stop_at_tick = (uint32_t)strtoul(argv[i + 1], nullptr, 0);
				stop_at_tick_enabled = true;
				printf("Will stop at low-memory tick $016A >= 0x%08X\n", stop_at_tick);
				i++;
			} else if (strcmp(argv[i], "--stop-at-pc") == 0 && i + 1 < argc) {
				stop_at_pc = (uint32_t)strtoul(argv[i + 1], nullptr, 0);
				stop_at_pc_enabled = true;
				printf("Will stop at PC %08X\n", stop_at_pc);
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

	{
		// Auto-load Mac II ROM at startup (--rom / --no-memtest override the default)
		const char* rom_file = rom_file_override ? rom_file_override : "../releases/boot0.rom";  // Mac II 256K ROM
		bus.QueueDownload(rom_file, 0, 1);  // index 0 for ROM
		fprintf(stderr, "Machine type: Mac II, loading ROM: %s\n", rom_file);

		// Auto-load NuBus video card declaration ROM (MDC 8*24, 341-0868)
		const char* nubus_rom_file = "../releases/boot2.rom";  // MDC 8*24 341-0868
		bus.QueueDownload(nubus_rom_file, 1, 1);  // index 1 for NuBus ROM
		fprintf(stderr, "Loading NuBus video ROM: %s\n", nubus_rom_file);
		for (int disk_index = 0; disk_index < 2; disk_index++) {
			if (!floppy_disk_files[disk_index].empty()) {
				int ioctl_index = disk_index == 0 ? 2 : 3;
				bus.QueueDownload(floppy_disk_files[disk_index], ioctl_index, 1);
				fprintf(stderr, "Loading floppy%d image: %s\n", disk_index, floppy_disk_files[disk_index].c_str());
			}
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
			if (run_enable) {
				for (int step = 0; step < batchSize; step++) {
					verilate();
					if (bootmask_once_stop_requested || scsi_transition_stop_requested ||
					    late_adb_stop_requested) {
						break;
					}
						if (stop_pc_reached()) {
							break;
						}
						if (stop_at_tick_enabled && lowmem_tick_reached()) {
							break;
						}
				}
			}
			else {
				if (single_step) { verilate(); }
				if (multi_step) {
					for (int step = 0; step < multi_step_amount; step++) { verilate(); }
				}
			}

			maybe_print_frame_probe();

				if (stop_pc_reached()) {
					printf("Reached stop PC %08X, exiting... frame=%d Op=%04X VBR=%08X\n",
						stop_at_pc,
						video.count_frame,
						VERTOPINTERN->debug_opcode,
						VERTOPINTERN->debug_vbr);
					print_scsi_stop_state();
					break;
				}

			if (bootmask_once_stop_requested) {
				printf("Bootmask one-shot probe complete, exiting... PC=%08X Op=%04X VBR=%08X\n",
					VERTOPINTERN->debug_pc,
					VERTOPINTERN->debug_opcode,
					VERTOPINTERN->debug_vbr);
				print_scsi_stop_state();
				break;
			}

			if (scsi_transition_stop_requested) {
				printf("SCSI transition probe complete, exiting... PC=%08X Op=%04X VBR=%08X\n",
					VERTOPINTERN->debug_pc,
					VERTOPINTERN->debug_opcode,
					VERTOPINTERN->debug_vbr);
				print_scsi_stop_state();
				break;
			}

			if (late_adb_stop_requested) {
				printf("Late ADB probe complete, exiting... PC=%08X Op=%04X VBR=%08X\n",
					VERTOPINTERN->debug_pc,
					VERTOPINTERN->debug_opcode,
					VERTOPINTERN->debug_vbr);
				print_scsi_stop_state();
				break;
			}

			static int headless_mouse_frame = -1;
			if (video.count_frame != headless_mouse_frame) {
				headless_mouse_frame = video.count_frame;
				if (!mouse_injections.empty() || mouse_injection_active) {
					process_mouse_injections(video.count_frame);
				}
				if (mouse_injection_active) {
					apply_mouse_packet(injected_mouse_x, (signed char)-injected_mouse_y, injected_mouse_buttons);
				} else {
					apply_mouse_packet(0, 0, 0);
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
				{
					// LBMacTwo forensics: dump the ROM's RAM-glue region at exit
					// (headless path twin of the GUI-loop dump).
					FILE* gd = fopen("ramglue_1e00_f800.bin", "wb");
					if (gd) {
						for (uint32_t a = 0x1E00; a < 0xF800; a += 2) {
							uint16_t w = ram_word(a);
							uint8_t hi = w >> 8, lo = w & 0xFF;
							fwrite(&hi, 1, 1, gd);
							fwrite(&lo, 1, 1, gd);
						}
						fclose(gd);
						printf("RAM glue dump written: ramglue_1e00_f800.bin\n");
					}
					// Full low-RAM dump: low-mem globals + trap tables + entire
					// system heap, for offline zone walking.
					FILE* ld = fopen("lowram_00000_18000.bin", "wb");
					if (ld) {
						for (uint32_t a = 0x0000; a < 0x18000; a += 2) {
							uint16_t w = ram_word(a);
							uint8_t hi = w >> 8, lo = w & 0xFF;
							fwrite(&hi, 1, 1, ld);
							fwrite(&lo, 1, 1, ld);
						}
						fclose(ld);
						printf("Low RAM dump written: lowram_00000_18000.bin\n");
					}
				}
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

			if (stop_at_tick_enabled && lowmem_tick_reached()) {
				printf("Reached low-memory tick $016A >= 0x%08X, exiting... PC=%08X Op=%04X VBR=%08X\n",
					stop_at_tick,
					VERTOPINTERN->debug_pc,
					VERTOPINTERN->debug_opcode,
					VERTOPINTERN->debug_vbr);
				print_scsi_stop_state();
				break;
			}

			continue;
		}

		mouse_x = 0;
		mouse_y = 0;
		SDL_Event event;
		while (SDL_PollEvent(&event))
		{
			ImGui_ImplSDL2_ProcessEvent(&event);
			if (event.type == SDL_QUIT)
				done = true;
			if (event.type == SDL_MOUSEMOTION && mouse_captured) {
				int win_w, win_h;
				SDL_GetWindowSize(window, &win_w, &win_h);
				int center_x = win_w / 2;
				int center_y = win_h / 2;
				int dx = event.motion.x - center_x;
				int dy = event.motion.y - center_y;

				if (dx != 0 || dy != 0) {
					mouse_x += dx;
					mouse_y -= dy;
					SDL_WarpMouseInWindow(window, center_x, center_y);
				}
			}
			if (mouse_captured) {
				if (event.type == SDL_MOUSEBUTTONDOWN && event.button.button == SDL_BUTTON_LEFT) {
					mouse_buttons |= 0x01;
				}
				if (event.type == SDL_MOUSEBUTTONUP && event.button.button == SDL_BUTTON_LEFT) {
					mouse_buttons &= ~0x01;
				}
			}
			if (event.type == SDL_KEYDOWN && mouse_captured &&
			    (event.key.keysym.sym == SDLK_ESCAPE || event.key.keysym.sym == SDLK_F1)) {
				mouse_captured = false;
			}
		}
		if (mouse_x > 127) mouse_x = 127;
		if (mouse_x < -127) mouse_x = -127;
		if (mouse_y > 127) mouse_y = 127;
		if (mouse_y < -127) mouse_y = -127;
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
		ImGui::Text("Machine: Mac II | CPU: TG68K | RAM: %dMB",
			(1 << cfg_memSize)); // 0->1MB,1->2MB,2->4MB,3->8MB

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

		// Draw VGA output and capture mouse clicks on the display.
		ImVec2 vga_size(video.output_width * VGA_SCALE_X, video.output_height * VGA_SCALE_Y);
		ImVec2 cursor_pos = ImGui::GetCursorPos();
		ImGui::Image(video.texture_id, vga_size);
		ImGui::SetCursorPos(cursor_pos);
		ImGui::InvisibleButton("##vga_capture", vga_size);
		if (ImGui::IsItemClicked(0)) {
			mouse_captured = true;
#ifndef _MSC_VER
			int win_w, win_h;
			SDL_GetWindowSize(window, &win_w, &win_h);
			SDL_WarpMouseInWindow(window, win_w / 2, win_h / 2);
#endif
		}
		ImGui::Text("%s", mouse_captured ? "Mouse captured - press Esc or F1 to release" : "Click display to capture mouse");
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

			if (stop_pc_reached()) {
				printf("Reached stop PC %08X, exiting... frame=%d Op=%04X VBR=%08X\n",
					stop_at_pc,
					video.count_frame,
					VERTOPINTERN->debug_opcode,
					VERTOPINTERN->debug_vbr);
				print_scsi_stop_state();
				break;
			}

		// Check if we should stop at this frame
		if (stop_at_frame_enabled && video.count_frame >= stop_at_frame) {
			{
				// LBMacTwo forensics (2026-07-15): dump the ROM's RAM-resident
				// glue region [0xE000,0xF800) at exit — identifies the code at
				// the real-RAM corruptor PC 0xEA48 seen by the HW snoop.
				FILE* gd = fopen("ramglue_1e00_f800.bin", "wb");
				if (gd) {
					for (uint32_t a = 0x1E00; a < 0xF800; a += 2) {
						uint16_t w = ram_word(a);
						uint8_t hi = w >> 8, lo = w & 0xFF;
						fwrite(&hi, 1, 1, gd);
						fwrite(&lo, 1, 1, gd);
					}
					fclose(gd);
					printf("RAM glue dump written: ramglue_1e00_f800.bin\n");
				}
			}
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

		if (!mouse_injections.empty() || mouse_injection_active) {
			process_mouse_injections(video.count_frame);
		}

		if (mouse_injection_active) {
			mouse_x = injected_mouse_x;
			mouse_y = (signed char)-injected_mouse_y;
			mouse_buttons = injected_mouse_buttons;
		} else if (!mouse_captured) {
			mouse_buttons = 0;
			mouse_x = 0;
			mouse_y = 0;
			if (input.inputs[input_left]) { mouse_x = -2; }
			if (input.inputs[input_right]) { mouse_x = 2; }
			if (input.inputs[input_up]) { mouse_y = 2; }
			if (input.inputs[input_down]) { mouse_y = -2; }
			if (input.inputs[input_a]) { mouse_buttons |= 0x01; }
			if (input.inputs[input_b]) { mouse_buttons |= 0x02; }
		}

		apply_mouse_packet(mouse_x, mouse_y, mouse_buttons);

		// Run simulation
		if (run_enable) {
				for (int step = 0; step < batchSize; step++) {
					verilate();
					if (stop_pc_reached()) {
						break;
					}
				}
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
