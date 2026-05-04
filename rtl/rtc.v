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
	output reg    dat_o
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

// 256-byte XPRAM
reg   [7:0] pram[256];

// Initialize PRAM with Mac II defaults
integer i;
initial begin
	for (i = 0; i < 256; i = i + 1)
		pram[i] = 8'h00;

	// Standard PRAM locations (0x00-0x1F) - Mac Plus compatible subset
	pram[8'h00] = 8'hA8;  // Validity byte
	pram[8'h01] = 8'h00;
	pram[8'h02] = 8'h00;
	pram[8'h03] = 8'h22;
	pram[8'h04] = 8'hCC;
	pram[8'h05] = 8'h0A;
	pram[8'h06] = 8'hCC;
	pram[8'h07] = 8'h0A;
	pram[8'h08] = 8'h00;
	pram[8'h09] = 8'h00;
	pram[8'h0A] = 8'h00;
	pram[8'h0B] = 8'h00;
	pram[8'h0C] = 8'h00;
	pram[8'h0D] = 8'h02;
	pram[8'h0E] = 8'h4D;  // Extended PRAM validity 'M'
	pram[8'h0F] = 8'h63;  // Extended PRAM validity 'c'
	pram[8'h10] = 8'hA8;  // SPValid: marks SPConfig bytes as valid
	pram[8'h11] = 8'h88;
	pram[8'h12] = 8'h00;
	pram[8'h13] = 8'h22;  // SPConfig: both ports useAsync
	                       // → SPConfig & 0x0F != 0 → emAppleTalkInactiveOnBoot
	                       // Prevents LocalTalk self-test hang at $408032AC
	                       // (see ../MacLC_MiSTer commit 83c226c6)
end

initial begin
	secs = 0;
	writeprotect = 1;
	clocktoseconds = 0;
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
	if (reset) begin
		bit_cnt <= 0;
		receiving <= 1;
		dat_o <= 1;
		cmd_bytes <= 0;
		cmd_len <= 1;
		ck_d <= 0;
	end
	else begin

		// timestamp is only sent at core load
		if (secs == 0)
			secs <= timestamp[31:0] + 32'd2082844800;

		// Seconds counter: increment every second at 32.5 MHz
		clocktoseconds <= clocktoseconds + 1'd1;
		if (clocktoseconds == 25'd32499999) begin
			clocktoseconds <= 0;
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
									// Prepare read response
									case (byte_in[6:2])
										5'h00, 5'h04: dout <= secs[7:0];
										5'h01, 5'h05: dout <= secs[15:8];
										5'h02, 5'h06: dout <= secs[23:16];
										5'h03, 5'h07: dout <= secs[31:24];
										5'h08, 5'h09, 5'h0A, 5'h0B: dout <= pram[{3'b000, byte_in[6:2]}];
										5'h10, 5'h11, 5'h12, 5'h13,
										5'h14, 5'h15, 5'h16, 5'h17,
										5'h18, 5'h19, 5'h1A, 5'h1B,
										5'h1C, 5'h1D, 5'h1E, 5'h1F: dout <= pram[{3'b000, byte_in[6:2]}];
										default: dout <= 8'h00;
									endcase
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
								end
							end

							2'd1: begin
								// Second byte
								cmd1 <= byte_in;
								cmd_bytes <= 2;

								if (cmd_len == 2'd2) begin
									// Command complete (standard write or extended read)
									if (cmd0[6:3] == 4'b0111) begin
										// Extended read - prepare response
										receiving <= 0;
										dout <= pram[{cmd0[2:0], byte_in[6:2]}];
										if ($test$plusargs("rtc_debug"))
											$display("[RTC_RD_EXT] cmd0=%02h cmd1=%02h addr=%02h data=%02h",
												cmd0, byte_in, {cmd0[2:0], byte_in[6:2]},
												pram[{cmd0[2:0], byte_in[6:2]}]);
									end else begin
										// Standard write - execute it
										if (!writeprotect) begin
											case (scmd)
												5'h00, 5'h04: secs[7:0]   <= byte_in;
												5'h01, 5'h05: secs[15:8]  <= byte_in;
												5'h02, 5'h06: secs[23:16] <= byte_in;
												5'h03, 5'h07: secs[31:24] <= byte_in;
												5'h08, 5'h09, 5'h0A, 5'h0B: pram[{3'b000, scmd}] <= byte_in;
												5'h10, 5'h11, 5'h12, 5'h13,
												5'h14, 5'h15, 5'h16, 5'h17,
												5'h18, 5'h19, 5'h1A, 5'h1B,
												5'h1C, 5'h1D, 5'h1E, 5'h1F: pram[{3'b000, scmd}] <= byte_in;
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
								// Third byte - extended write data
								cmd_bytes <= 3;
								if (!writeprotect)
									pram[ext_addr] <= byte_in;
							end

							default: ;
						endcase
					end
				end
				bit_cnt <= bit_cnt + 1'd1;
			end
		end
	end
end

endmodule
