//
// sim_vram.v
//
// Simple synchronous RAM for NuBus video VRAM in Verilator simulation.
// Replaces the SDRAM arbiter interface with a 1-cycle latency RAM.
//

module sim_vram #(
	parameter ADDR_BITS = 19  // 19 bits = 512K words = 1MB (matches 512KB VRAM)
)
(
	input               clk,
	input               reset,
	input  [ADDR_BITS-1:0] addr,
	input  [15:0]       din,
	output reg [15:0]   dout,
	input               rd,
	input               wr,
	output reg          ready
);

reg [15:0] mem [0:(1 << ADDR_BITS)-1];
integer init_i;

initial begin
	for (init_i = 0; init_i < (1 << ADDR_BITS); init_i = init_i + 1)
		mem[init_i] = 16'h0000;
end

// 1-cycle latency to match SDRAM arbiter handshake expectations:
// Video card asserts rd/wr → next cycle ready goes high + data available
reg rd_pending;
reg wr_pending;

always @(posedge clk) begin
	if (reset) begin
		ready <= 1'b0;
		rd_pending <= 1'b0;
		wr_pending <= 1'b0;
		dout <= 16'd0;
	end else begin
		ready <= 1'b0;

		if (rd_pending) begin
			dout <= mem[addr[ADDR_BITS-1:0]];
			ready <= 1'b1;
			rd_pending <= 1'b0;
		end

		if (wr_pending) begin
			mem[addr[ADDR_BITS-1:0]] <= din;
			ready <= 1'b1;
			wr_pending <= 1'b0;
		end

		// Capture new requests (only when not already processing)
		if (rd && !rd_pending && !wr_pending && !ready)
			rd_pending <= 1'b1;
		if (wr && !rd_pending && !wr_pending && !ready)
			wr_pending <= 1'b1;
	end
end

endmodule
