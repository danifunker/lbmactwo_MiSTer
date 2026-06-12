/* PRAM/XPRAM - RTC implementation for Mac II
 *
 * Supports:
 *   - 256-byte XPRAM (Mac II extended parameter RAM)
 *   - Standard commands (1-byte cmd + optional 1-byte data)
 *   - Extended commands (3-byte: cmd1, cmd2, data) for full XPRAM access
 *   - Write protect register
 *   - Seconds counter (32-bit Mac epoch)
 *
 * Based on the protocol documented in Snow emulator (rtc.rs) and
 * Inside Macintosh: Devices, Chapter 7.
 *
 * Command format:
 *   Standard: {R/W, scmd[4:0], 01}
 *     R/W: 1=read, 0=write
 *     scmd: register address (bits [6:2] of command byte)
 *       0x00-0x03: seconds bytes 0-3 (aliases 0x04-0x07)
 *       0x08-0x0B: PRAM group 1
 *       0x0C: test register (ignored)
 *       0x0D: write protect register
 *       0x10-0x1F: PRAM group 2
 *
 *   Extended: first byte has (cmd & 0x78) == 0x38, i.e. cmd[6:3]==0111
 *     Byte 1: {R/W, addr[7:5], 0111, x}
 *     Byte 2: {addr[4:0], xxx}  (address low bits in bits [7:3]... actually [6:2])
 *     Byte 3 (write only): data byte
 *     Address = {cmd0[2:0], cmd1[6:2]}
 */

module rtc (
	input         clk,
	input         reset,

	input  [32:0] timestamp, // unix timestamp
	input         _cs,
	input         ck,
	input         dat_i,
	output reg    dat_o,
	output reg    cko,

	// PRAM persistence: host-side access for the HPS NVRAM image
	// (load/save FSM in LBMacTwo.sv, MacLC-style "Mount PRAM" slot).
	input         pram_load_wr,    // pulse: pram[pram_load_addr] <= pram_load_data
	input   [7:0] pram_load_addr,
	input   [7:0] pram_load_data,
	input   [7:0] pram_save_addr,  // save read port; data REGISTERED, valid 2
	output  [7:0] pram_save_data,  //   clocks after pram_save_addr is set
	output reg    pram_wr_stb      // pulse: the Mac wrote a PRAM byte (image dirty)
);

reg   [2:0] bit_cnt;
reg         ck_d;
reg   [7:0] din;
reg   [7:0] dout;
reg         receiving;
reg  [31:0] secs;
reg  [24:0] clocktoseconds;

// Command state
reg   [7:0] cmd0;       // first command byte
reg   [7:0] cmd1;       // second byte (extended cmd address, or data for standard write)
reg   [1:0] cmd_bytes;  // how many command bytes received so far
reg   [1:0] cmd_len;    // total bytes expected for this command

// Write protect
reg         writeprotect;

// 256-byte XPRAM — true-dual-port BRAM (M10K), NOT fabric registers.
// Port A = the serial protocol engine (single read+write site, one shared
// address). Port B = the host/HPS NVRAM image (load write / save read,
// mutually exclusive FSM phases in LBMacTwo.sv, one shared address).
// Keeping each port in its own always block with a single address is what
// lets Quartus infer one M10K; the previous in-place reads/writes scattered
// through the protocol case fell back to ~2K registers + 256:1 muxes
// (2347 ALUTs / 2145 regs in the 2026-06-12 map) and blew the LAB budget.
(* ramstyle = "no_rw_check" *) reg [7:0] pram[256];

// --- Port A: serial engine ----------------------------------------------
// Reads are ISSUED (ser_raddr + 2-cycle countdown) instead of consumed
// in place; the RTC serial bit period is microseconds, so the 2-clock BRAM
// latency is invisible to the host protocol. Writes pulse ser_we for one
// clock. A command is either a read or a write, never both in flight, so
// the port-A address muxes on ser_we.
reg  [7:0] ser_raddr;
reg  [1:0] ser_rpend;     // 2=addr issued, 1=ser_q valid, commit to dout
reg        ser_we;
reg  [7:0] ser_waddr;
reg  [7:0] ser_wdata;
reg  [7:0] ser_q;

wire [7:0] a_addr = ser_we ? ser_waddr : ser_raddr;
always @(posedge clk) begin
	if (ser_we) pram[a_addr] <= ser_wdata;
	ser_q <= pram[a_addr];
end

// --- Port B: host (HPS NVRAM image) --------------------------------------
reg  [7:0] pram_save_q;
wire [7:0] b_addr = pram_load_wr ? pram_load_addr : pram_save_addr;
always @(posedge clk) begin
	if (pram_load_wr) pram[b_addr] <= pram_load_data;
	pram_save_q <= pram[b_addr];
end
assign pram_save_data = pram_save_q;

// Initialize PRAM with Mac II defaults
integer i;
initial begin
	for (i = 0; i < 256; i = i + 1)
		pram[i] = 8'h00;

		// Seed the Mac II PRAM/XPRAM image to the same initialized state used by
		// the local MAME no-media baseline (mame/nvram/macii/rtc).  The ROM can
		// rebuild this from blank PRAM, but matching MAME's persistent RTC state
		// keeps the Verilator and MAME boot paths comparable.
		pram[8'h01] = 8'h80;
		pram[8'h02] = 8'h4f;
		pram[8'h03] = 8'h48;
		pram[8'h08] = 8'h03;
		pram[8'h09] = 8'h88;
		pram[8'h0b] = 8'h4c;
		pram[8'h0c] = 8'h4e;
		pram[8'h0d] = 8'h75;
		pram[8'h0e] = 8'h4d;
		pram[8'h0f] = 8'h63;
		pram[8'h10] = 8'ha8;
		pram[8'h14] = 8'hcc;
		pram[8'h15] = 8'h0a;
		pram[8'h16] = 8'hcc;
		pram[8'h17] = 8'h0a;
		pram[8'h1d] = 8'h02;
		pram[8'h1e] = 8'h63;
		pram[8'h6f] = 8'h13;
		pram[8'h70] = 8'h80;
		pram[8'h77] = 8'h01;
		pram[8'h78] = 8'hff;
		pram[8'h79] = 8'hff;
		pram[8'h7a] = 8'hff;
		pram[8'h7b] = 8'hdf;
	end

initial begin
	secs = 0;
	writeprotect = 0;
	clocktoseconds = 0;
	cko = 1;
end

// The full incoming byte (din shift register + current bit)
wire [7:0] byte_in = {din[6:0], dat_i};

// Is the incoming first byte an extended command? (cmd & 0x78) == 0x38
wire byte_is_extended = (byte_in[6:3] == 4'b0111);

// Is the incoming first byte a read? (bit 7 = 1)
wire byte_is_read = byte_in[7];

// Standard command sub-address: scmd = cmd[6:2]
wire [4:0] scmd = cmd0[6:2];

// Extended command address: {cmd0[2:0], cmd1[6:2]}
wire [7:0] ext_addr = {cmd0[2:0], cmd1[6:2]};

always @(posedge clk) begin
	pram_wr_stb <= 1'b0;   // default; pulsed below on Mac-side PRAM writes
	ser_we      <= 1'b0;   // default; pulsed for one clock per PRAM write

	// Port-A read commit pipeline: 2 clocks after a read is issued, ser_q
	// holds pram[ser_raddr]; move it into the response shifter.
	if (ser_rpend != 2'd0) begin
		ser_rpend <= ser_rpend - 2'd1;
		if (ser_rpend == 2'd1)
			dout <= ser_q;
	end

	if (reset) begin
		bit_cnt <= 0;
		receiving <= 1;
		dat_o <= 1;
		cko <= 1;
		cmd_bytes <= 0;
		cmd_len <= 1;
		ck_d <= 0;
		writeprotect <= 0;
		ser_rpend <= 0;
	end
	else begin

		// timestamp is only sent at core load
		if (secs == 0)
			secs <= timestamp[31:0] + 32'd2082844800;

		// RTC CKO toggles every half-second. MAME wires this line to VIA1
		// CA2 and increments the seconds register on the CKO rising edge.
		clocktoseconds <= clocktoseconds + 1'd1;
		if (clocktoseconds == 25'd16249999) begin
			clocktoseconds <= 0;
			cko <= ~cko;
			if (!cko)
				secs <= secs + 1'd1;
		end

		if (_cs) begin
			// Chip select inactive - reset serial state
			bit_cnt <= 0;
			receiving <= 1;
			dat_o <= 1;
			cmd_bytes <= 0;
			cmd_len <= 1;
		end
		else begin
			ck_d <= ck;

			// The 343-0042 shifts both command input and response output on
			// the RTC clock high-to-low transition; host reads data after it.
			if (ck_d & ~ck) begin
				if (!receiving)
					dat_o <= dout[7 - bit_cnt];
				else
					din <= {din[6:0], dat_i};

				if (bit_cnt == 7) begin
					// A complete byte boundary
					if (receiving) begin
						case (cmd_bytes)
							2'd0: begin
								// First byte - command byte
								cmd0 <= byte_in;
								cmd_bytes <= 1;

								// Determine total command length
								if (byte_is_extended) begin
									// Extended: read=2 bytes, write=3 bytes
									cmd_len <= byte_is_read ? 2'd2 : 2'd3;
								end else begin
									// Standard: read=1 byte (done), write=2 bytes
									cmd_len <= byte_is_read ? 2'd1 : 2'd2;
								end

								// Standard read: command complete after 1 byte
								if (byte_is_read && !byte_is_extended) begin
									receiving <= 0;
									// Prepare read response (PRAM cases issue a
									// port-A BRAM read; commit pipeline above
									// lands it in dout 2 clocks later, long
									// before the next serial bit)
									case (byte_in[6:2])
										5'h00, 5'h04: dout <= secs[7:0];
										5'h01, 5'h05: dout <= secs[15:8];
										5'h02, 5'h06: dout <= secs[23:16];
										5'h03, 5'h07: dout <= secs[31:24];
										5'h08, 5'h09, 5'h0A, 5'h0B,
										5'h10, 5'h11, 5'h12, 5'h13,
										5'h14, 5'h15, 5'h16, 5'h17,
										5'h18, 5'h19, 5'h1A, 5'h1B,
										5'h1C, 5'h1D, 5'h1E, 5'h1F: begin
											ser_raddr <= {3'b000, byte_in[6:2]};
											ser_rpend <= 2'd2;
										end
										default: dout <= 8'h00;
									endcase
									`ifdef SIMULATION
									if ($test$plusargs("rtc_debug"))
										$display("[RTC_RD_STD] cmd=%02h scmd=%02h data=%02h",
											byte_in, byte_in[6:2],
											((byte_in[6:2] == 5'h00) || (byte_in[6:2] == 5'h04)) ? secs[7:0] :
											((byte_in[6:2] == 5'h01) || (byte_in[6:2] == 5'h05)) ? secs[15:8] :
											((byte_in[6:2] == 5'h02) || (byte_in[6:2] == 5'h06)) ? secs[23:16] :
											((byte_in[6:2] == 5'h03) || (byte_in[6:2] == 5'h07)) ? secs[31:24] :
											(((byte_in[6:2] >= 5'h08) && (byte_in[6:2] <= 5'h0B)) ||
											 ((byte_in[6:2] >= 5'h10) && (byte_in[6:2] <= 5'h1F))) ? pram[{3'b000, byte_in[6:2]}] :
											8'h00);
								`endif
								end
							end

							2'd1: begin
								// Second byte
								cmd1 <= byte_in;
								cmd_bytes <= 2;

								if (cmd_len == 2'd2) begin
									// Command complete (standard write or extended read)
									if (cmd0[6:3] == 4'b0111) begin
										// Extended read - issue port-A BRAM read
										receiving <= 0;
										ser_raddr <= {cmd0[2:0], byte_in[6:2]};
										ser_rpend <= 2'd2;
`ifdef SIMULATION
										if ($test$plusargs("rtc_debug"))
											$display("[RTC_RD_EXT] cmd0=%02h cmd1=%02h addr=%02h data=%02h",
												cmd0, byte_in, {cmd0[2:0], byte_in[6:2]},
												pram[{cmd0[2:0], byte_in[6:2]}]);
`endif
										end else begin
											// Standard write - execute it
`ifdef SIMULATION
											if ($test$plusargs("rtc_debug"))
												$display("[RTC_WR_STD] cmd=%02h scmd=%02h data=%02h wp=%b",
													cmd0, scmd, byte_in, writeprotect);
`endif
											if (!writeprotect) begin
											case (scmd)
												5'h00, 5'h04: secs[7:0]   <= byte_in;
												5'h01, 5'h05: secs[15:8]  <= byte_in;
												5'h02, 5'h06: secs[23:16] <= byte_in;
												5'h03, 5'h07: secs[31:24] <= byte_in;
												5'h08, 5'h09, 5'h0A, 5'h0B,
												5'h10, 5'h11, 5'h12, 5'h13,
												5'h14, 5'h15, 5'h16, 5'h17,
												5'h18, 5'h19, 5'h1A, 5'h1B,
												5'h1C, 5'h1D, 5'h1E, 5'h1F: begin
													ser_we    <= 1'b1;
													ser_waddr <= {3'b000, scmd};
													ser_wdata <= byte_in;
													pram_wr_stb <= 1'b1;
												end
												default: ;
											endcase
										end
										// Write protect and test registers are always writable
										case (scmd)
											5'h0D: writeprotect <= byte_in[7];
											5'h0C: ; // test register - ignore
											default: ;
										endcase
									end
								end
							end

								2'd2: begin
									// Third byte - extended write data.
									// Write-protect gates XPRAM writes too (MAME
									// macrtc.cpp blocks all i!=13 writes; Snow
									// rtc.rs checks writeprotect on the extended
									// path) - only the WP register itself is
									// always writable.
									cmd_bytes <= 3;
									if (!writeprotect) begin
										ser_we    <= 1'b1;
										ser_waddr <= ext_addr;
										ser_wdata <= byte_in;
										pram_wr_stb <= 1'b1;
									end
`ifdef SIMULATION
									if ($test$plusargs("rtc_debug"))
										$display("[RTC_WR_EXT] cmd0=%02h cmd1=%02h addr=%02h data=%02h wp=%b",
											cmd0, cmd1, ext_addr, byte_in, writeprotect);
`endif
								end

							default: ;
						endcase
					end
				end
				bit_cnt <= bit_cnt + 1'd1;
			end
		end
	end

	// (Host-side PRAM image load/save lives on BRAM port B above — it works
	// even while the system is held in reset, which is exactly when the
	// mounted image streams in.)
end

endmodule
