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

// 8MB of RAM (4M words of 16 bits)
// Address bits [21:0] used, giving 4MW = 8MB
// Upper address bits select ROM vs RAM area
reg [15:0] mem [0:4194303];  // 4M words = 8MB

// Combinational read - no latency, data available immediately when oe is asserted
// This matches the timing expected by the Mac's bus controller
assign dout = mem[addr[21:0]];

// Simple synchronous read/write
// Debug: track writes for verification
reg [21:0] last_wr_addr;
reg [15:0] last_wr_data;
reg        last_wr_valid;
integer    wr_count = 0;
integer    vram_rd_count = 0;

integer vram_wr_count = 0;

always @(posedge clk) begin
	// Writes are allowed even during reset (needed for ROM loading)
	if (we && |ds) begin
		// Write with byte strobes
		if (ds[1]) mem[addr[21:0]][15:8] <= din[15:8];
		if (ds[0]) mem[addr[21:0]][7:0]  <= din[7:0];
		last_wr_addr <= addr[21:0];
		last_wr_data <= din;
		last_wr_valid <= 1;
		wr_count <= wr_count + 1;
		// Debug first 20 writes, then every 100000th
		if (wr_count < 20 || wr_count % 100000 == 0)
			$display("sim_ram WR[%0d]: addr=%h din=%h ds=%b",
				wr_count, addr[21:0], din, ds);
		// Debug VRAM writes (VRAM is at 0x1A0000-0x1DFFFF word address = 0x340000-0x3BFFFF byte)
		if (addr[21:0] >= 22'h1A0000 && addr[21:0] < 22'h1E0000) begin
			if (vram_wr_count < 20 || vram_wr_count % 1000 == 0)
				$display("sim_ram VRAM_WR[%0d]: addr=%h (line %0d) din=%h ds=%b",
					vram_wr_count, addr[21:0], (addr[21:0] - 22'h1A0000) >> 9, din, ds);
			vram_wr_count <= vram_wr_count + 1;
		end
		// Debug all writes in non-ROM area to see where CPU is writing
		if (wr_count >= 20 && wr_count < 50 && addr[21] == 0)
			$display("sim_ram WR[%0d]: addr=%h din=%h ds=%b (after ROM)",
				wr_count, addr[21:0], din, ds);
		// Watchpoint: low memory system globals used by Slot Manager
		// $0A50 (SRsrcTblPtr) = CPU byte addr → word addr $0528
		// $0B9A (flag) = word addr $05CD
		// Bus error vector at $0008 = word addr $0004
		if (addr[21:0] == 22'h000528 || addr[21:0] == 22'h000529)
			$display("WATCH $0A50: WR addr=%h din=%h ds=%b PC=%h (wr#%0d)",
				addr[21:0], din, ds, debug_pc, wr_count);
		if (addr[21:0] == 22'h0005CD)
			$display("WATCH $0B9A: WR addr=%h din=%h ds=%b PC=%h (wr#%0d)",
				addr[21:0], din, ds, debug_pc, wr_count);
		if ((addr[21:0] == 22'h000004 || addr[21:0] == 22'h000005)
		    && (din != 16'hb6db && din != 16'h6db6 && din != 16'hdb6d
		        && din != 16'hffff && din != 16'h0000))
			$display("WATCH BERR_VEC: WR addr=%h din=%h ds=%b PC=%h (wr#%0d)",
				addr[21:0], din, ds, debug_pc, wr_count);
		// sResource table at $2000 (word addr $1000-$1020)
		if (addr[21:0] >= 22'h001000 && addr[21:0] < 22'h001020
		    && din != 16'hb6db && din != 16'h6db6 && din != 16'hdb6d
		    && din != 16'hffff)
			$display("WATCH sRsrc@2000: WR addr=%h din=%h ds=%b PC=%h (wr#%0d)",
				addr[21:0], din, ds, debug_pc, wr_count);
	end

	if (reset) begin
		last_wr_valid <= 0;
		// Don't reset wr_count so we can track all writes
	end else begin
		// Debug video reads (VRAM is at 0x1A0000 = 0x340000 >> 1 in word address)
		if (oe && addr[21:0] >= 22'h1A0000 && addr[21:0] < 22'h1E0000) begin
			if (vram_rd_count < 50)
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
		$display("ROM VERIFY: word[0x200000]=%h (expect 9779)", mem[22'h200000]);
		$display("ROM VERIFY: word[0x200001]=%h (expect D2C4)", mem[22'h200001]);
		$display("ROM VERIFY: word[0x200002]=%h (expect 4080)", mem[22'h200002]);
		$display("ROM VERIFY: word[0x200003]=%h (expect 002A)", mem[22'h200003]);
		$display("ROM VERIFY: word[0x200004]=%h (expect 0178)", mem[22'h200004]);
		$display("ROM VERIFY: word[0x200005]=%h (expect 4EFA)", mem[22'h200005]);
		$display("ROM VERIFY: word[0x200006]=%h (expect 0084)", mem[22'h200006]);
		$display("ROM VERIFY: word[0x200007]=%h (expect 4EFA)", mem[22'h200007]);
	end
end

// Allow ROM/RAM initialization from simulation
// verilator tracing_off
/* verilator lint_off UNUSED */
initial begin
	// Memory will be initialized by the simulation testbench
	// via ioctl_download mechanism
end
/* verilator lint_on UNUSED */
// verilator tracing_on

endmodule
