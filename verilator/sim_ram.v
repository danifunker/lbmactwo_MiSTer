//
// sim_ram.v
//
// Simple RAM module for Verilator simulation of MacLC
// Replaces the SDRAM controller with synchronous RAM
//

module sim_ram
(
	// cpu/chipset interface - same as sdram.v
	input               clk,        // system clock
	input               reset,      // reset signal

	input [15:0]        din,        // data input from chipset/cpu
	output [15:0]       dout,       // data output to chipset/cpu (combinational)
	input [24:0]        addr,       // 25 bit word address
	input [1:0]         ds,         // upper/lower data strobe
	input               oe,         // cpu/chipset requests read
	input               we,         // cpu/chipset requests write
	input [31:0]        debug_pc    // CPU PC for watchpoint logging
);

// 8MB of RAM (4M words of 16 bits) + ROM/disk space (8MB-capable map).
// Address map (matches the FPGA SDRAM map):
//   RAM        : addr[22]=0  -> 0x000000-0x3FFFFF (4M words = 8MB)
//   ROM / disk : addr[22]=1  -> 0x400000 + (system ROM, NuBus ROM, disk images)
// Array spans both regions; sized to cover the relocated ROM/disk top.
reg [15:0] mem [0:8388607];  // 8M words: 4M RAM + 4M ROM/disk

// RAM range check: addr[22]==0 means within 8MB RAM space (4M words)
// ROM/other: addr[22] set (ROM downloads, ROM reads, disk reads)
wire ram_in_range = (addr[22] == 1'b0);
wire is_rom = addr[22];

// Combinational read - no latency, data available immediately when oe is asserted
wire [22:0] effective_addr = is_rom ? addr[22:0] : {1'b0, addr[21:0]};
assign dout = (ram_in_range || is_rom) ? mem[effective_addr] : 16'h0000;

// Simple synchronous read/write
// Debug: track writes for verification
reg [21:0] last_wr_addr;
reg [15:0] last_wr_data;
reg        last_wr_valid;
integer    wr_count = 0;
integer    lowram_writes = 0;
integer    vram_rd_count = 0;

integer vram_wr_count = 0;
integer testrd_count = 0;
integer ram_size_dbg_count = 0;

always @(posedge clk) begin
	// Writes are allowed even during reset (needed for ROM loading)
	if (we && |ds && (ram_in_range || is_rom)) begin
		// Write with byte strobes (only to valid RAM or ROM range)
		if (ds[1]) mem[effective_addr][15:8] <= din[15:8];
		if (ds[0]) mem[effective_addr][7:0]  <= din[7:0];
		last_wr_addr <= addr[21:0];
		last_wr_data <= din;
		last_wr_valid <= 1;
		wr_count <= wr_count + 1;
		// Debug first 20 writes, then every 100000th
		if ($test$plusargs("ram_debug") && (wr_count < 20 || wr_count % 100000 == 0))
			$display("sim_ram WR[%0d]: addr=%h din=%h ds=%b",
				wr_count, addr[21:0], din, ds);
		// Debug VRAM writes (VRAM is at 0x1A0000-0x1DFFFF word address = 0x340000-0x3BFFFF byte)
		if (addr[21:0] >= 22'h1A0000 && addr[21:0] < 22'h1E0000) begin
			if ($test$plusargs("ram_debug") && (vram_wr_count < 20 || vram_wr_count % 1000 == 0))
				$display("sim_ram VRAM_WR[%0d]: addr=%h (line %0d) din=%h ds=%b",
					vram_wr_count, addr[21:0], (addr[21:0] - 22'h1A0000) >> 9, din, ds);
			vram_wr_count <= vram_wr_count + 1;
		end
		// Debug all writes in non-ROM area to see where CPU is writing
		if ($test$plusargs("ram_debug") && wr_count >= 20 && wr_count < 50 && addr[21] == 0)
			$display("sim_ram WR[%0d]: addr=%h din=%h ds=%b (after ROM)",
				wr_count, addr[21:0], din, ds);
		// Trace first 60 writes made by the RAM-test pattern instruction at $40803744
		if ($test$plusargs("ram_debug") && debug_pc == 32'h40803744 && addr[21] == 0
		    && addr[21:0] >= 22'h000400 && lowram_writes < 80) begin
			$display("TEST_WR[%0d]: addr=%h din=%h ds=%b wr_count=%0d",
				lowram_writes, addr[21:0], din, ds, wr_count);
			lowram_writes <= lowram_writes + 1;
		end
		// Watchpoint: low memory system globals used by Slot Manager
		// $0A50 (SRsrcTblPtr) = CPU byte addr → word addr $0528
		// $0B9A (flag) = word addr $05CD
		// Bus error vector at $0008 = word addr $0004
		if ($test$plusargs("ram_debug") && (addr[21:0] == 22'h000528 || addr[21:0] == 22'h000529))
			$display("WATCH $0A50: WR addr=%h din=%h ds=%b PC=%h (wr#%0d)",
				addr[21:0], din, ds, debug_pc, wr_count);
		if ($test$plusargs("ram_debug") && addr[21:0] == 22'h0005CD)
			$display("WATCH $0B9A: WR addr=%h din=%h ds=%b PC=%h (wr#%0d)",
				addr[21:0], din, ds, debug_pc, wr_count);
		if ($test$plusargs("ram_debug") && (addr[21:0] == 22'h000004 || addr[21:0] == 22'h000005)
		    && (din != 16'hb6db && din != 16'h6db6 && din != 16'hdb6d
		        && din != 16'hffff && din != 16'h0000))
			$display("WATCH BERR_VEC: WR addr=%h din=%h ds=%b PC=%h (wr#%0d)",
				addr[21:0], din, ds, debug_pc, wr_count);
		if ($test$plusargs("ram_size_debug") && debug_pc >= 32'h408039aa && debug_pc <= 32'h408039fc
		    && addr[21:0] < 22'h002000 && ram_size_dbg_count < 120) begin
			$display("RAM_SIZE_WR[%0d]: PC=%h addr=%h eff=%h din=%h ds=%b",
				ram_size_dbg_count, debug_pc, addr[21:0], effective_addr, din, ds);
			ram_size_dbg_count <= ram_size_dbg_count + 1;
		end
		// WLCS marker at byte $0CFC = word addr $067E/$067F
			if ($test$plusargs("ram_debug") && (addr[21:0] == 22'h00067E || addr[21:0] == 22'h00067F))
				$display("WATCH WLCS: WR addr=%h din=%h ds=%b PC=%h (wr#%0d)",
					addr[21:0], din, ds, debug_pc, wr_count);
			// sResource table at $2000 (word addr $1000-$1020)
		if ($test$plusargs("ram_debug") && addr[21:0] >= 22'h001000 && addr[21:0] < 22'h001020
		    && din != 16'hb6db && din != 16'h6db6 && din != 16'hdb6d
		    && din != 16'hffff)
			$display("WATCH sRsrc@2000: WR addr=%h din=%h ds=%b PC=%h (wr#%0d)",
				addr[21:0], din, ds, debug_pc, wr_count);
	end

	if (reset) begin
		last_wr_valid <= 0;
		// Don't reset wr_count so we can track all writes
	end else begin
		// Watch WLCS reads at byte $0CFC = word addr $067E/$067F
		if ($test$plusargs("ram_debug") && oe && (addr[21:0] == 22'h00067E || addr[21:0] == 22'h00067F))
			$display("WATCH WLCS: RD addr=%h dout=%h PC=%h",
				addr[21:0], mem[{3'b0, addr[18:0]}], debug_pc);
		// RAM-test readback probe: PC inside $40803xxx test routine and
		// addr in top-of-4MB tested range ($1FFE80..$1FFFFF word)
		if ($test$plusargs("ram_debug") && oe && debug_pc >= 32'h4080378E && debug_pc <= 32'h408037AA
		    && testrd_count < 200) begin
			$display("TEST_RD[%0d]: PC=%h addr=%h dout=%h",
				testrd_count, debug_pc, addr[21:0], mem[effective_addr]);
			testrd_count <= testrd_count + 1;
		end
		if ($test$plusargs("ram_size_debug") && oe && debug_pc >= 32'h408039aa && debug_pc <= 32'h408039fc
		    && addr[21:0] < 22'h002000 && ram_size_dbg_count < 120) begin
			$display("RAM_SIZE_RD[%0d]: PC=%h addr=%h eff=%h dout=%h",
				ram_size_dbg_count, debug_pc, addr[21:0], effective_addr, mem[effective_addr]);
			ram_size_dbg_count <= ram_size_dbg_count + 1;
		end
		// Debug video reads (VRAM is at 0x1A0000 = 0x340000 >> 1 in word address)
		if (oe && addr[21:0] >= 22'h1A0000 && addr[21:0] < 22'h1E0000) begin
			if ($test$plusargs("ram_debug") && vram_rd_count < 50)
				$display("sim_ram VRAM_RD[%0d]: addr=%h (line %0d) dout=%h",
					vram_rd_count, addr[21:0], (addr[21:0] - 22'h1A0000) >> 9, mem[addr[21:0]]);
			vram_rd_count <= vram_rd_count + 1;
		end
	end
end

// ROM verification: dump first 8 words and compute checksum after download
reg rom_verified = 0;
always @(posedge clk) begin
	if (!reset && !rom_verified && wr_count > 100000) begin
		rom_verified <= 1;
		// The ROM/disk region moved from A21 (0x200000) to A22 (0x400000) when the
		// map was reworked for the 8MB RAM window (see sim.v ~line 992). The old
		// verify still read 0x200000 (always 0 now) and falsely read as "ROM not
		// loaded". Dump BOTH the stale and the live ROM base so the location is
		// unambiguous. Expect the 9779/D2C4/4080/002A signature at 0x400000.
		$display("ROM VERIFY (stale A21 base 0x200000): %h %h %h %h",
			mem[23'h200000], mem[23'h200001], mem[23'h200002], mem[23'h200003]);
		$display("ROM VERIFY (live A22 base 0x400000, expect 9779 D2C4 4080 002A): %h %h %h %h",
			mem[23'h400000], mem[23'h400001], mem[23'h400002], mem[23'h400003]);
		$display("ROM VERIFY (0x400004.. expect 0178 4EFA 0084 4EFA): %h %h %h %h",
			mem[23'h400004], mem[23'h400005], mem[23'h400006], mem[23'h400007]);
	end
end

// Allow ROM/RAM initialization from simulation
// verilator tracing_off
/* verilator lint_off UNUSED */
// Cold-boot RAM pre-clear (sim parity with LBMacTwo.sv's clear FSM).
// On the FPGA, all configured RAM is zeroed after boot0.rom loads and before
// the CPU is released, so every cold boot sees the clean low memory a warm
// restart would have. Verilator's --x-initial flag does not guarantee a 0000
// fill across the array, so we zero the RAM region (addr[22]=0 -> word indices
// 0x000000..0x3FFFFF) explicitly here. The ROM/disk region (0x400000..) is
// loaded later via the ioctl download path, so we leave it untouched.
integer ram_clr_i;
initial begin
	for (ram_clr_i = 0; ram_clr_i <= 'h3FFFFF; ram_clr_i = ram_clr_i + 1)
		mem[ram_clr_i] = 16'h0000;
end
/* verilator lint_on UNUSED */
// verilator tracing_on

endmodule
