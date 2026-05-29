/* ADB Modem PIC transceiver for Mac II
 * Based on Snow emulator's transceiver.rs (Mac II ADB protocol)
 *
 * State machine controlled by VIA1 PB4/PB5 (ST0/ST1):
 *   Command (0,0) - CPU sends command byte via shift register
 *   Data1   (1,0) - Process command, return first response byte
 *   Data2   (0,1) - Return second response byte
 *   Idle    (1,1) - Default state
 *
 * INT line is state-dependent:
 *   Command: always false
 *   Data1:   true when cmd empty AND response empty (no data / device didn't respond)
 *   Data2/Idle: true when any device has SRQ
 */

module adb(
	input            clk,
	input            clk_en,
	input            reset,
	input      [1:0] st,       // {ST1, ST0} from VIA1 PB5/PB4
	output           _int,     // active-low interrupt to VIA1 PB3
	input            viaBusy,
	output reg       listen,
	input      [7:0] adb_din,
	input            adb_din_strobe,
	output reg [7:0] adb_dout,
	output reg       adb_dout_strobe,

	output reg       capslock,

	input     [24:0] ps2_mouse,
	input     [10:0] ps2_key,

	// High while a multi-byte Talk response still has bytes to deliver.
	// Used by the VIA1 SR shim to re-arm a shift-in only for real data.
	output           resp_pending,

	// Debug snapshot for JTAG ISSP (read-only): FSM + command state.
	output    [15:0] dbg_adb,
	output           mouse_has_event_o
);

assign mouse_has_event_o = mouse_has_event;

// ADB bus states (matches Snow's AdbBusState enum)
localparam [1:0] ST_COMMAND = 2'b00;  // ST0=0, ST1=0
localparam [1:0] ST_DATA1   = 2'b01;  // ST0=1, ST1=0  (st = {ST1,ST0} = {0,1})
localparam [1:0] ST_DATA2   = 2'b10;  // ST0=0, ST1=1  (st = {ST1,ST0} = {1,0})
localparam [1:0] ST_IDLE    = 2'b11;  // ST0=1, ST1=1

// Note on st encoding: dataController_top.sv passes .st({ADBST1, ADBST0})
// So st[0] = ST0, st[1] = ST1
// Snow: Command = ST0=0,ST1=0 → st=2'b00
// Snow: Data1   = ST0=1,ST1=0 → st=2'b01
// Snow: Data2   = ST0=0,ST1=1 → st=2'b10
// Snow: Idle    = ST0=1,ST1=1 → st=2'b11

// Device addresses
localparam [3:0] ADDR_KEYBOARD = 4'd2;
localparam [3:0] ADDR_MOUSE    = 4'd3;

// Command byte fields
reg  [7:0] cmd_byte;          // Last received command byte
reg        cmd_valid;         // Command byte has been received
reg        cmd_processed;     // Command has been processed

// Response buffer (max 2 bytes for Talk responses)
reg  [7:0] response [0:7];   // Up to 8 bytes
reg  [3:0] resp_len;          // Number of valid response bytes
reg  [3:0] resp_idx;          // Next byte to return

// Listen data buffer
reg  [7:0] listen_data [0:7];
reg  [3:0] listen_len;

// State tracking
reg  [1:0] st_prev;

// Parsed command fields
wire [3:0] cmd_addr    = cmd_byte[7:4];
wire [1:0] cmd_type    = cmd_byte[3:2];  // 00=Reset, 01=Flush, 10=Listen, 11=Talk
wire [1:0] cmd_reg     = cmd_byte[1:0];

// Read-only debug snapshot: {_int, dout_strobe, din_strobe, listen,
//                            cmd_processed, cmd_valid, st[1:0], cmd_byte[7:0]}
assign dbg_adb = {_int, adb_dout_strobe, adb_din_strobe, listen,
                  cmd_processed, cmd_valid, st, cmd_byte};

// Device register storage
reg  [3:0] kbd_addr;          // Keyboard device address (default 2)
reg  [3:0] mouse_addr;        // Mouse device address (default 3)

// Keyboard state
reg  [15:0] kbdReg0;          // Key data register
reg  [15:0] kbdReg2;          // Modifier/LED register
reg   [7:0] kbdFifo [0:7];
reg   [2:0] kbdFifoRd, kbdFifoWr;
wire        kbdFifoEmpty = (kbdFifoRd == kbdFifoWr);
wire        kbd_has_data = !kbdFifoEmpty;

// Mouse state
reg   [6:0] mouseX, mouseY;
reg         mouseButton;
reg         mouse_has_event;

// SRQ: device has pending data
wire kbd_srq   = kbd_has_data;
wire mouse_srq = mouse_has_event;
wire any_srq   = kbd_srq | mouse_srq;

// Response empty check
wire resp_empty = (resp_idx >= resp_len);
assign resp_pending = ~resp_empty;

// INT line — state-dependent per Snow's get_int()
// Active-low output
reg int_out;
always @(*) begin
	case (st)
		ST_COMMAND: int_out = 1'b0;                              // Never assert during command
		ST_DATA1:   int_out = (!cmd_valid && resp_empty);        // Completion: no cmd and no response
		ST_DATA2:   int_out = any_srq;                           // SRQ pending
		ST_IDLE:    int_out = any_srq;                           // SRQ pending
	endcase
end
assign _int = ~int_out;

// Process command and generate response
// This mirrors Snow's process_cmd()
task process_command;
	input do_finish;  // true when transitioning out of data phase (for Listen)
	begin
		resp_len <= 0;
		resp_idx <= 0;

		if (cmd_type == 2'b00) begin
			// Reset (broadcast to all devices)
			kbd_addr <= ADDR_KEYBOARD;
			mouse_addr <= ADDR_MOUSE;
			kbdReg0 <= 16'hFFFF;
			kbdReg2 <= 16'hFFFF;
			kbdFifoRd <= 0;
			kbdFifoWr <= 0;
			mouseX <= 0;
			mouseY <= 0;
			mouseButton <= 0;
			mouse_has_event <= 0;
			cmd_processed <= 1;
		end
		else if (cmd_addr == kbd_addr) begin
			case (cmd_type)
				2'b01: begin // Flush
					kbdFifoRd <= 0;
					kbdFifoWr <= 0;
					kbdReg0 <= 16'hFFFF;
					cmd_processed <= 1;
				end
				2'b10: begin // Listen
					if (do_finish) begin
						// Deferred execution: apply listen data now
						if (cmd_reg == 2'd2 && listen_len >= 1) begin
							kbdReg2[2:0] <= listen_data[0][2:0]; // LED bits
						end
						else if (cmd_reg == 2'd3 && listen_len >= 2) begin
							// Reg 3 write — check for address reassignment
							if (listen_data[1][7:0] == 8'hFE) begin
								kbd_addr <= listen_data[0][3:0];
							end
						end
						cmd_processed <= 1;
					end
					// else: don't process yet, wait for finish
				end
				2'b11: begin // Talk
					case (cmd_reg)
						2'd0: begin
							// Build kbdReg0 from FIFO
							kbdReg0 <= 16'hFFFF; // Default: no keys
							if (!kbdFifoEmpty) begin
								reg [7:0] key1;
								key1 = kbdFifo[kbdFifoRd];
								kbdFifoRd <= kbdFifoRd + 1'd1;

								if (kbdFifoRd + 1'd1 != kbdFifoWr) begin
									// Two keys available
									response[0] <= key1;
									response[1] <= kbdFifo[kbdFifoRd + 1'd1];
									kbdFifoRd <= kbdFifoRd + 2'd2;
									resp_len <= 2;
								end else begin
									// One key: pad with $FF
									response[0] <= key1;
									response[1] <= 8'hFF;
									resp_len <= 2;
								end
							end
							// else: empty response (no keys pending)
							cmd_processed <= 1;
						end
						2'd2: begin
							response[0] <= kbdReg2[15:8];
							response[1] <= kbdReg2[7:0];
							resp_len <= 2;
							cmd_processed <= 1;
						end
						2'd3: begin
							// Reg3: {reserved=0, exceptional=1, srq_enable=1, reserved=0, addr[3:0], handler_id[7:0]}
							response[0] <= {1'b0, 1'b1, 1'b1, 1'b0, kbd_addr};
							response[1] <= 8'h02; // Handler ID 2 = Apple Extended Keyboard
							resp_len <= 2;
							cmd_processed <= 1;
						end
						default: begin
							cmd_processed <= 1;
						end
					endcase
				end
				default: cmd_processed <= 1;
			endcase
		end
		else if (cmd_addr == mouse_addr) begin
			case (cmd_type)
				2'b01: begin // Flush
					mouseX <= 0;
					mouseY <= 0;
					mouse_has_event <= 0;
					cmd_processed <= 1;
				end
				2'b10: begin // Listen
					if (do_finish) begin
						if (cmd_reg == 2'd3 && listen_len >= 2) begin
							if (listen_data[1][7:0] == 8'hFE) begin
								mouse_addr <= listen_data[0][3:0];
							end
						end
						cmd_processed <= 1;
					end
				end
				2'b11: begin // Talk
					case (cmd_reg)
						2'd0: begin
							if (mouse_has_event) begin
								response[0] <= {~mouseButton, mouseY};
								response[1] <= {1'b1, mouseX};
								resp_len <= 2;
								mouseX <= 0;
								mouseY <= 0;
								mouse_has_event <= 0;
							end
							// else: empty response
							cmd_processed <= 1;
						end
						2'd3: begin
							response[0] <= {1'b0, 1'b1, 1'b1, 1'b0, mouse_addr};
							response[1] <= 8'h01; // Handler ID 1 = Apple Mouse
							resp_len <= 2;
							cmd_processed <= 1;
						end
						default: begin
							cmd_processed <= 1;
						end
					endcase
				end
				default: cmd_processed <= 1;
			endcase
		end
		else begin
			// No device at this address — empty response
			cmd_processed <= 1;
		end
	end
endtask

// Main state machine — mirrors Snow's io() method
always @(posedge clk) begin
	if (reset) begin
		st_prev <= ST_IDLE;
		cmd_valid <= 0;
		cmd_processed <= 0;
		resp_len <= 0;
		resp_idx <= 0;
		listen <= 0;
		listen_len <= 0;
		adb_dout <= 0;
		adb_dout_strobe <= 0;

		kbd_addr <= ADDR_KEYBOARD;
		mouse_addr <= ADDR_MOUSE;
		kbdReg0 <= 16'hFFFF;
		kbdReg2 <= 16'hFFFF;
		kbdFifoRd <= 0;
		kbdFifoWr <= 0;
		mouseX <= 0;
		mouseY <= 0;
		mouseButton <= 0;
		mouse_has_event <= 0;
	end else if (clk_en) begin
		adb_dout_strobe <= 0;
		listen <= 0;

		// Detect state transitions
		if (st != st_prev) begin
			st_prev <= st;

			case (st)
				ST_IDLE: begin
					// Transition to idle — no special processing
				end

				ST_COMMAND: begin
					// Transition to command state
					// If we had a pending multi-byte command (Listen), finish it
					if (cmd_valid && cmd_type == 2'b10 && !cmd_processed) begin
						process_command(1'b1); // finish=true
					end
					// Prepare for new command
					cmd_valid <= 0;
					cmd_processed <= 0;
					resp_len <= 0;
					resp_idx <= 0;
					listen_len <= 0;
				end

				ST_DATA1, ST_DATA2: begin
					// Return next pre-computed response byte
					// (process_command runs on cmd receipt, response ready before data phase)
					if (!resp_empty) begin
						adb_dout <= response[resp_idx];
						adb_dout_strobe <= 1;
						resp_idx <= resp_idx + 1'd1;
					end else begin
						// No data - return 0
						adb_dout <= 8'h00;
						adb_dout_strobe <= 1;
					end
				end
			endcase
		end

		// Receive command byte during Command state
		if (st == ST_COMMAND && adb_din_strobe) begin
			if (!cmd_valid) begin
				// First byte: this is the command byte
				cmd_byte <= adb_din;
				cmd_valid <= 1;
				cmd_processed <= 0;
				listen_len <= 0;
			end else begin
				// Additional bytes: Listen data
				listen_data[listen_len] <= adb_din;
				listen_len <= listen_len + 1'd1;
			end
		end

		// Process command as soon as cmd_byte settles (1 cycle after receipt).
		// This ensures response[] and resp_len are ready before the Data1 transition.
		// Listen commands are excluded — they defer to process_command(finish=true).
		if (cmd_valid && !cmd_processed && st == ST_COMMAND && cmd_type != 2'b10) begin
			process_command(1'b0);
			cmd_valid <= 0;
		end

		// Receive Listen data during Data phases (ROM sends via SR)
		if ((st == ST_DATA1 || st == ST_DATA2) && adb_din_strobe) begin
			if (cmd_valid && cmd_type == 2'b10) begin
				listen_data[listen_len] <= adb_din;
				listen_len <= listen_len + 1'd1;
				listen <= 1; // Signal to VIA bit-bang that we're listening
			end
		end

		// Store keyboard events into FIFO (from PS2 handler)
		if (keyStrobe && keyData[6:0] != 7'h7F) begin
			kbdFifo[kbdFifoWr] <= keyData;
			kbdFifoWr <= kbdFifoWr + 1'd1;
		end

		// PS2 mouse input handling
		if (mouseStrobe && (mouseXraw != 9'd0 || mouseYraw != 9'd0 || mouseBtn != mouseButton)) begin
			// Clamp mouse deltas to 7-bit signed range
			if (~mouseXraw[8] & |mouseXraw[7:6]) mouseX <= 7'h3F;
			else if (mouseXraw[8] & ~mouseXraw[6]) mouseX <= 7'h40;
			else mouseX <= mouseXraw[6:0];

			if (~mouseYraw[8] & |mouseYraw[7:6]) mouseY <= 7'h40;
			else if (mouseYraw[8] & ~mouseYraw[6]) mouseY <= 7'h3F;
			else mouseY <= -mouseYraw[6:0];

			mouseButton <= mouseBtn;
			mouse_has_event <= 1;
		end
	end
end

// PS2 mouse input handling
//
// ps2_mouse[24:0] is driven by the HPS asynchronously to clk. Bit [24] is the
// "new packet" strobe (toggles on each update); [23:0] carry the deltas and
// buttons. The original code edge-detected [24] against a single-FF capture
// while XOR'ing with the still-async raw input — placement-sensitive: at one
// PLL/floorplan the strobe arrived a few ns after the data and sim-style ideal
// sampling worked, but after a placement reshuffle the strobe can arrive
// before [23:0] has settled, so the XOR fires while X/Y/Btn are still
// transitioning, the (X|Y|Btn-change) guard reads zero, the strobe is
// consumed and the real motion event is lost — invisible in verilator.
//
// Fix: proper 2-FF synchronizer on [24], plus a one-cycle delay register so
// edge detection compares two synchronous samples (not sync vs. raw async).
// AND register the data bits in lock-step so the consumer reads from clean
// clk_sys-synchronous flops, never combinational fanout of async HPS pins.
//
// The (* preserve *) + DONT_MERGE_REGISTER attributes are mandatory — Quartus
// optimized the earlier sync chain out of silicon (0 hits in fit.rpt for any
// of the sync FFs) because without them the fitter sees the back-to-back
// flops as logically equivalent and merges them with downstream logic.
// SYNCHRONIZER_IDENTIFICATION FORCED also relaxes TimeQuest on the async
// input and gives an MTBF computation in the metastability report.
//
// Skew note: ps2_mouse[24] (strobe) and ps2_mouse[23:0] (deltas/btn) are a
// 25-bit HPS bus whose bits arrive at the fabric with arbitrary placement-
// dependent routing skew. If [24] leads [23:0] by even ~1 clk on a given
// placement, an "equal-length" 2-stage sync on both lets the strobe-edge
// XOR fire while the data path still holds the *previous* packet's values
// (typically all zeros), so the consumer's (X|Y|Btn != prev) guard discards
// the strobe and the motion event is silently lost. Cure: give the strobe
// path one MORE stage than the data path, so when the strobe edge finally
// propagates to the consumer, the data has had an extra clk to settle.
(* preserve *) (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON" *)
reg mstb_s1;
(* preserve *) (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON" *)
reg mstb_s2;
(* preserve *) reg mstb_s3;  // extra delay: data settles before strobe edge fires
(* preserve *) reg mstb_d;
// 2-stage register chain for data bits. Strobe gets 3 stages, so by the time
// the consumer sees mouseStrobe high, mouseXraw_s2 has been holding the new
// packet's data for one full clk — independent of HPS-side bit-arrival skew.
(* preserve *) reg [8:0] mouseXraw_s1, mouseXraw_s2;
(* preserve *) reg [8:0] mouseYraw_s1, mouseYraw_s2;
(* preserve *) reg       mouseBtn_s1,  mouseBtn_s2;

always @(posedge clk) begin
	if (reset) begin
		mstb_s1 <= ps2_mouse[24];
		mstb_s2 <= ps2_mouse[24];
		mstb_s3 <= ps2_mouse[24];
		mstb_d  <= ps2_mouse[24];
		mouseXraw_s1 <= 9'd0; mouseXraw_s2 <= 9'd0;
		mouseYraw_s1 <= 9'd0; mouseYraw_s2 <= 9'd0;
		mouseBtn_s1  <= 1'b0; mouseBtn_s2  <= 1'b0;
	end else begin
		mstb_s1 <= ps2_mouse[24];  // free-running synchronizer (no clk_en)
		mstb_s2 <= mstb_s1;
		mstb_s3 <= mstb_s2;        // extra stage past the data sync depth
		mouseXraw_s1 <= {ps2_mouse[4], ps2_mouse[15:8]};
		mouseYraw_s1 <= {ps2_mouse[5], ps2_mouse[23:16]};
		mouseBtn_s1  <= ps2_mouse[0];
		mouseXraw_s2 <= mouseXraw_s1;
		mouseYraw_s2 <= mouseYraw_s1;
		mouseBtn_s2  <= mouseBtn_s1;
		if (clk_en) mstb_d <= mstb_s3;
	end
end

wire       mouseStrobe = mstb_d ^ mstb_s3;
wire [8:0] mouseXraw = mouseXraw_s2;
wire [8:0] mouseYraw = mouseYraw_s2;
wire       mouseBtn  = mouseBtn_s2;

// PS2 keyboard input handling
//
// Same async-strobe hazard as the mouse above: ps2_key[10] is a HPS-driven
// toggle indicating "new key event", ps2_key[8:0] carries the scan code, [9]
// carries press/release. Sync [10] with a 2-FF synchronizer and edge-detect
// the synchronized copy so scan code & press bits have settled by the time
// the consumer fires. Also register [9:0] in lock-step so the case() and
// `press` wire read clean clk_sys-synchronous bits.
//
// preserve/DONT_MERGE_REGISTER mandatory — see equivalent comment on the
// mouse synchronizer above; without them Quartus eliminates the chain.
reg       keyStrobe;
reg       kstb;       // delayed (consumer-side) copy of synchronized strobe
(* preserve *) (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON" *)
reg       kstb_s1;
(* preserve *) (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON" *)
reg       kstb_s2;
(* preserve *) reg kstb_s3;   // extra delay: data settles before strobe edge fires
(* preserve *) reg [9:0] keyRaw_s1, keyRaw_s2; // scan code [8:0] + press [9]
reg [7:0] keyData;
wire      press = keyRaw_s2[9];
wire      capslock_key = (keyRaw_s2[8:0] == 'h58);

always @(posedge clk) begin
	if (reset) begin
		kstb_s1 <= ps2_key[10];
		kstb_s2 <= ps2_key[10];
		kstb_s3 <= ps2_key[10];
		kstb    <= ps2_key[10];
		keyRaw_s1 <= 10'h000;
		keyRaw_s2 <= 10'h000;
		keyStrobe <= 1'b0;
		keyData <= 8'h7f;
		capslock <= 1'b0;
	end else begin
		kstb_s1 <= ps2_key[10];
		kstb_s2 <= kstb_s1;
		kstb_s3 <= kstb_s2;   // extra stage past the data sync depth
		keyRaw_s1 <= ps2_key[9:0];
		keyRaw_s2 <= keyRaw_s1;
		if (clk_en) begin
		kstb <= kstb_s3;
		if (kstb ^ kstb_s3) begin
			case(keyRaw_s2[8:0]) // Scan Code Set 2 → ADB scan codes
			  9'h000: keyData[6:0] <= 7'h7F;
			  9'h001: keyData[6:0] <= 7'h65;	//F9
			  9'h002: keyData[6:0] <= 7'h7F;
			  9'h003: keyData[6:0] <= 7'h60;	//F5
			  9'h004: keyData[6:0] <= 7'h63;	//F3
			  9'h005: keyData[6:0] <= 7'h7A;	//F1
			  9'h006: keyData[6:0] <= 7'h78;	//F2
			  9'h007: keyData[6:0] <= 7'h7F;//7'h6F;	//F12 <OSD>
			  9'h008: keyData[6:0] <= 7'h7F;
			  9'h009: keyData[6:0] <= 7'h6D;	//F10
			  9'h00a: keyData[6:0] <= 7'h64;	//F8
			  9'h00b: keyData[6:0] <= 7'h61;	//F6
			  9'h00c: keyData[6:0] <= 7'h7F;
			  9'h00d: keyData[6:0] <= 7'h30;	//TAB
			  9'h00e: keyData[6:0] <= 7'h32;	//~ (`)
			  9'h00f: keyData[6:0] <= 7'h7F;
			  9'h010: keyData[6:0] <= 7'h7F;
			  9'h011: keyData[6:0] <= 7'h37;	//LEFT ALT (command)
			  9'h012: keyData[6:0] <= 7'h38;	//LEFT SHIFT
			  9'h013: keyData[6:0] <= 7'h7F;
			  9'h014: keyData[6:0] <= 7'h36;	//CTRL
			  9'h015: keyData[6:0] <= 7'h0C;	//q
			  9'h016: keyData[6:0] <= 7'h12;	//1
			  9'h017: keyData[6:0] <= 7'h7F;
			  9'h018: keyData[6:0] <= 7'h7F;
			  9'h019: keyData[6:0] <= 7'h7F;
			  9'h01a: keyData[6:0] <= 7'h06;	//z
			  9'h01b: keyData[6:0] <= 7'h01;	//s
			  9'h01c: keyData[6:0] <= 7'h00;	//a
			  9'h01d: keyData[6:0] <= 7'h0D;	//w
			  9'h01e: keyData[6:0] <= 7'h13;	//2
			  9'h01f: keyData[6:0] <= 7'h7F;
			  9'h020: keyData[6:0] <= 7'h7F;
			  9'h021: keyData[6:0] <= 7'h08;	//c
			  9'h022: keyData[6:0] <= 7'h07;	//x
			  9'h023: keyData[6:0] <= 7'h02;	//d
			  9'h024: keyData[6:0] <= 7'h0E;	//e
			  9'h025: keyData[6:0] <= 7'h15;	//4
			  9'h026: keyData[6:0] <= 7'h14;	//3
			  9'h027: keyData[6:0] <= 7'h7F;
			  9'h028: keyData[6:0] <= 7'h7F;
			  9'h029: keyData[6:0] <= 7'h31;	//SPACE
			  9'h02a: keyData[6:0] <= 7'h09;	//v
			  9'h02b: keyData[6:0] <= 7'h03;	//f
			  9'h02c: keyData[6:0] <= 7'h11;	//t
			  9'h02d: keyData[6:0] <= 7'h0F;	//r
			  9'h02e: keyData[6:0] <= 7'h17;	//5
			  9'h02f: keyData[6:0] <= 7'h7F;
			  9'h030: keyData[6:0] <= 7'h7F;
			  9'h031: keyData[6:0] <= 7'h2D;	//n
			  9'h032: keyData[6:0] <= 7'h0B;	//b
			  9'h033: keyData[6:0] <= 7'h04;	//h
			  9'h034: keyData[6:0] <= 7'h05;	//g
			  9'h035: keyData[6:0] <= 7'h10;	//y
			  9'h036: keyData[6:0] <= 7'h16;	//6
			  9'h037: keyData[6:0] <= 7'h7F;
			  9'h038: keyData[6:0] <= 7'h7F;
			  9'h039: keyData[6:0] <= 7'h7F;
			  9'h03a: keyData[6:0] <= 7'h2E;	//m
			  9'h03b: keyData[6:0] <= 7'h26;	//j
			  9'h03c: keyData[6:0] <= 7'h20;	//u
			  9'h03d: keyData[6:0] <= 7'h1A;	//7
			  9'h03e: keyData[6:0] <= 7'h1C;	//8
			  9'h03f: keyData[6:0] <= 7'h7F;
			  9'h040: keyData[6:0] <= 7'h7F;
			  9'h041: keyData[6:0] <= 7'h2B;	//<,
			  9'h042: keyData[6:0] <= 7'h28;	//k
			  9'h043: keyData[6:0] <= 7'h22;	//i
			  9'h044: keyData[6:0] <= 7'h1F;	//o
			  9'h045: keyData[6:0] <= 7'h1D;	//0
			  9'h046: keyData[6:0] <= 7'h19;	//9
			  9'h047: keyData[6:0] <= 7'h7F;
			  9'h048: keyData[6:0] <= 7'h7F;
			  9'h049: keyData[6:0] <= 7'h2F;	//>.
			  9'h04a: keyData[6:0] <= 7'h2C;	//FORWARD SLASH
			  9'h04b: keyData[6:0] <= 7'h25;	//l
			  9'h04c: keyData[6:0] <= 7'h29;	//;
			  9'h04d: keyData[6:0] <= 7'h23;	//p
			  9'h04e: keyData[6:0] <= 7'h1B;	//-
			  9'h04f: keyData[6:0] <= 7'h7F;
			  9'h050: keyData[6:0] <= 7'h7F;
			  9'h051: keyData[6:0] <= 7'h7F;
			  9'h052: keyData[6:0] <= 7'h27;	//'"
			  9'h053: keyData[6:0] <= 7'h7F;
			  9'h054: keyData[6:0] <= 7'h21;	//[
			  9'h055: keyData[6:0] <= 7'h18;	// =
			  9'h056: keyData[6:0] <= 7'h7F;
			  9'h057: keyData[6:0] <= 7'h7F;
			  9'h058: keyData[6:0] <= 7'h39;	//CAPSLOCK
			  9'h059: keyData[6:0] <= 7'h7B;	//RIGHT SHIFT
			  9'h05a: keyData[6:0] <= 7'h24;	//ENTER
			  9'h05b: keyData[6:0] <= 7'h1E;	//]
			  9'h05c: keyData[6:0] <= 7'h7F;
			  9'h05d: keyData[6:0] <= 7'h2A;	//BACKSLASH
			  9'h05e: keyData[6:0] <= 7'h7F;
			  9'h05f: keyData[6:0] <= 7'h7F;
			  9'h060: keyData[6:0] <= 7'h7F;
			  9'h061: keyData[6:0] <= 7'h7F;	//international left shift cut out (German '<>' key), 0x56 Set#1 code
			  9'h062: keyData[6:0] <= 7'h7F;
			  9'h063: keyData[6:0] <= 7'h7F;
			  9'h064: keyData[6:0] <= 7'h7F;
			  9'h065: keyData[6:0] <= 7'h7F;
			  9'h066: keyData[6:0] <= 7'h33;	//BACKSPACE
			  9'h067: keyData[6:0] <= 7'h7F;
			  9'h068: keyData[6:0] <= 7'h7F;
			  9'h069: keyData[6:0] <= 7'h53;	//KP 1
			  9'h06a: keyData[6:0] <= 7'h7F;
			  9'h06b: keyData[6:0] <= 7'h56;	//KP 4
			  9'h06c: keyData[6:0] <= 7'h59;	//KP 7
			  9'h06d: keyData[6:0] <= 7'h7F;
			  9'h06e: keyData[6:0] <= 7'h7F;
			  9'h06f: keyData[6:0] <= 7'h7F;
			  9'h070: keyData[6:0] <= 7'h52;	//KP 0
			  9'h071: keyData[6:0] <= 7'h41;	//KP .
			  9'h072: keyData[6:0] <= 7'h54;	//KP 2
			  9'h073: keyData[6:0] <= 7'h57;	//KP 5
			  9'h074: keyData[6:0] <= 7'h58;	//KP 6
			  9'h075: keyData[6:0] <= 7'h5B;	//KP 8
			  9'h076: keyData[6:0] <= 7'h35;	//ESCAPE
			  9'h077: keyData[6:0] <= 7'h47;	//NUMLOCK (Mac keypad clear?)
			  9'h078: keyData[6:0] <= 7'h67;	//F11 <OSD>
			  9'h079: keyData[6:0] <= 7'h45;	//KP +
			  9'h07a: keyData[6:0] <= 7'h55;	//KP 3
			  9'h07b: keyData[6:0] <= 7'h4E;	//KP -
			  9'h07c: keyData[6:0] <= 7'h43;	//KP *
			  9'h07d: keyData[6:0] <= 7'h5C;	//KP 9
			  9'h07e: keyData[6:0] <= 7'h7F;	//SCROLL LOCK / KP )
			  9'h07f: keyData[6:0] <= 7'h7F;
			  9'h080: keyData[6:0] <= 7'h7F;
			  9'h081: keyData[6:0] <= 7'h7F;
			  9'h082: keyData[6:0] <= 7'h7F;
			  9'h083: keyData[6:0] <= 7'h62;	//F7
			  9'h084: keyData[6:0] <= 7'h7F;
			  9'h085: keyData[6:0] <= 7'h7F;
			  9'h086: keyData[6:0] <= 7'h7F;
			  9'h087: keyData[6:0] <= 7'h7F;
			  9'h088: keyData[6:0] <= 7'h7F;
			  9'h089: keyData[6:0] <= 7'h7F;
			  9'h08a: keyData[6:0] <= 7'h7F;
			  9'h08b: keyData[6:0] <= 7'h7F;
			  9'h08c: keyData[6:0] <= 7'h7F;
			  9'h08d: keyData[6:0] <= 7'h7F;
			  9'h08e: keyData[6:0] <= 7'h7F;
			  9'h08f: keyData[6:0] <= 7'h7F;
			  9'h090: keyData[6:0] <= 7'h7F;
			  9'h091: keyData[6:0] <= 7'h7F;
			  9'h092: keyData[6:0] <= 7'h7F;
			  9'h093: keyData[6:0] <= 7'h7F;
			  9'h094: keyData[6:0] <= 7'h7F;
			  9'h095: keyData[6:0] <= 7'h7F;
			  9'h096: keyData[6:0] <= 7'h7F;
			  9'h097: keyData[6:0] <= 7'h7F;
			  9'h098: keyData[6:0] <= 7'h7F;
			  9'h099: keyData[6:0] <= 7'h7F;
			  9'h09a: keyData[6:0] <= 7'h7F;
			  9'h09b: keyData[6:0] <= 7'h7F;
			  9'h09c: keyData[6:0] <= 7'h7F;
			  9'h09d: keyData[6:0] <= 7'h7F;
			  9'h09e: keyData[6:0] <= 7'h7F;
			  9'h09f: keyData[6:0] <= 7'h7F;
			  9'h0a0: keyData[6:0] <= 7'h7F;
			  9'h0a1: keyData[6:0] <= 7'h7F;
			  9'h0a2: keyData[6:0] <= 7'h7F;
			  9'h0a3: keyData[6:0] <= 7'h7F;
			  9'h0a4: keyData[6:0] <= 7'h7F;
			  9'h0a5: keyData[6:0] <= 7'h7F;
			  9'h0a6: keyData[6:0] <= 7'h7F;
			  9'h0a7: keyData[6:0] <= 7'h7F;
			  9'h0a8: keyData[6:0] <= 7'h7F;
			  9'h0a9: keyData[6:0] <= 7'h7F;
			  9'h0aa: keyData[6:0] <= 7'h7F;
			  9'h0ab: keyData[6:0] <= 7'h7F;
			  9'h0ac: keyData[6:0] <= 7'h7F;
			  9'h0ad: keyData[6:0] <= 7'h7F;
			  9'h0ae: keyData[6:0] <= 7'h7F;
			  9'h0af: keyData[6:0] <= 7'h7F;
			  9'h0b0: keyData[6:0] <= 7'h7F;
			  9'h0b1: keyData[6:0] <= 7'h7F;
			  9'h0b2: keyData[6:0] <= 7'h7F;
			  9'h0b3: keyData[6:0] <= 7'h7F;
			  9'h0b4: keyData[6:0] <= 7'h7F;
			  9'h0b5: keyData[6:0] <= 7'h7F;
			  9'h0b6: keyData[6:0] <= 7'h7F;
			  9'h0b7: keyData[6:0] <= 7'h7F;
			  9'h0b8: keyData[6:0] <= 7'h7F;
			  9'h0b9: keyData[6:0] <= 7'h7F;
			  9'h0ba: keyData[6:0] <= 7'h7F;
			  9'h0bb: keyData[6:0] <= 7'h7F;
			  9'h0bc: keyData[6:0] <= 7'h7F;
			  9'h0bd: keyData[6:0] <= 7'h7F;
			  9'h0be: keyData[6:0] <= 7'h7F;
			  9'h0bf: keyData[6:0] <= 7'h7F;
			  9'h0c0: keyData[6:0] <= 7'h7F;
			  9'h0c1: keyData[6:0] <= 7'h7F;
			  9'h0c2: keyData[6:0] <= 7'h7F;
			  9'h0c3: keyData[6:0] <= 7'h7F;
			  9'h0c4: keyData[6:0] <= 7'h7F;
			  9'h0c5: keyData[6:0] <= 7'h7F;
			  9'h0c6: keyData[6:0] <= 7'h7F;
			  9'h0c7: keyData[6:0] <= 7'h7F;
			  9'h0c8: keyData[6:0] <= 7'h7F;
			  9'h0c9: keyData[6:0] <= 7'h7F;
			  9'h0ca: keyData[6:0] <= 7'h7F;
			  9'h0cb: keyData[6:0] <= 7'h7F;
			  9'h0cc: keyData[6:0] <= 7'h7F;
			  9'h0cd: keyData[6:0] <= 7'h7F;
			  9'h0ce: keyData[6:0] <= 7'h7F;
			  9'h0cf: keyData[6:0] <= 7'h7F;
			  9'h0d0: keyData[6:0] <= 7'h7F;
			  9'h0d1: keyData[6:0] <= 7'h7F;
			  9'h0d2: keyData[6:0] <= 7'h7F;
			  9'h0d3: keyData[6:0] <= 7'h7F;
			  9'h0d4: keyData[6:0] <= 7'h7F;
			  9'h0d5: keyData[6:0] <= 7'h7F;
			  9'h0d6: keyData[6:0] <= 7'h7F;
			  9'h0d7: keyData[6:0] <= 7'h7F;
			  9'h0d8: keyData[6:0] <= 7'h7F;
			  9'h0d9: keyData[6:0] <= 7'h7F;
			  9'h0da: keyData[6:0] <= 7'h7F;
			  9'h0db: keyData[6:0] <= 7'h7F;
			  9'h0dc: keyData[6:0] <= 7'h7F;
			  9'h0dd: keyData[6:0] <= 7'h7F;
			  9'h0de: keyData[6:0] <= 7'h7F;
			  9'h0df: keyData[6:0] <= 7'h7F;
			  9'h0e0: keyData[6:0] <= 7'h7F;	//ps2 extended key
			  9'h0e1: keyData[6:0] <= 7'h7F;
			  9'h0e2: keyData[6:0] <= 7'h7F;
			  9'h0e3: keyData[6:0] <= 7'h7F;
			  9'h0e4: keyData[6:0] <= 7'h7F;
			  9'h0e5: keyData[6:0] <= 7'h7F;
			  9'h0e6: keyData[6:0] <= 7'h7F;
			  9'h0e7: keyData[6:0] <= 7'h7F;
			  9'h0e8: keyData[6:0] <= 7'h7F;
			  9'h0e9: keyData[6:0] <= 7'h7F;
			  9'h0ea: keyData[6:0] <= 7'h7F;
			  9'h0eb: keyData[6:0] <= 7'h7F;
			  9'h0ec: keyData[6:0] <= 7'h7F;
			  9'h0ed: keyData[6:0] <= 7'h7F;
			  9'h0ee: keyData[6:0] <= 7'h7F;
			  9'h0ef: keyData[6:0] <= 7'h7F;
			  9'h0f0: keyData[6:0] <= 7'h7F;	//ps2 release code
			  9'h0f1: keyData[6:0] <= 7'h7F;
			  9'h0f2: keyData[6:0] <= 7'h7F;
			  9'h0f3: keyData[6:0] <= 7'h7F;
			  9'h0f4: keyData[6:0] <= 7'h7F;
			  9'h0f5: keyData[6:0] <= 7'h7F;
			  9'h0f6: keyData[6:0] <= 7'h7F;
			  9'h0f7: keyData[6:0] <= 7'h7F;
			  9'h0f8: keyData[6:0] <= 7'h7F;
			  9'h0f9: keyData[6:0] <= 7'h7F;
			  9'h0fa: keyData[6:0] <= 7'h7F;	//ps2 ack code
			  9'h0fb: keyData[6:0] <= 7'h7F;
			  9'h0fc: keyData[6:0] <= 7'h7F;
			  9'h0fd: keyData[6:0] <= 7'h7F;
			  9'h0fe: keyData[6:0] <= 7'h7F;
			  9'h0ff: keyData[6:0] <= 7'h7F;
			  9'h100: keyData[6:0] <= 7'h7F;
			  9'h101: keyData[6:0] <= 7'h7F;
			  9'h102: keyData[6:0] <= 7'h7F;
			  9'h103: keyData[6:0] <= 7'h7F;
			  9'h104: keyData[6:0] <= 7'h7F;
			  9'h105: keyData[6:0] <= 7'h7F;
			  9'h106: keyData[6:0] <= 7'h7F;
			  9'h107: keyData[6:0] <= 7'h7F;
			  9'h108: keyData[6:0] <= 7'h7F;
			  9'h109: keyData[6:0] <= 7'h7F;
			  9'h10a: keyData[6:0] <= 7'h7F;
			  9'h10b: keyData[6:0] <= 7'h7F;
			  9'h10c: keyData[6:0] <= 7'h7F;
			  9'h10d: keyData[6:0] <= 7'h7F;
			  9'h10e: keyData[6:0] <= 7'h7F;
			  9'h10f: keyData[6:0] <= 7'h7F;
			  9'h110: keyData[6:0] <= 7'h7F;
			  9'h111: keyData[6:0] <= 7'h37;	//RIGHT ALT (command)
			  9'h112: keyData[6:0] <= 7'h7F;
			  9'h113: keyData[6:0] <= 7'h7F;
			  9'h114: keyData[6:0] <= 7'h7F;
			  9'h115: keyData[6:0] <= 7'h7F;
			  9'h116: keyData[6:0] <= 7'h7F;
			  9'h117: keyData[6:0] <= 7'h7F;
			  9'h118: keyData[6:0] <= 7'h7F;
			  9'h119: keyData[6:0] <= 7'h7F;
			  9'h11a: keyData[6:0] <= 7'h7F;
			  9'h11b: keyData[6:0] <= 7'h7F;
			  9'h11c: keyData[6:0] <= 7'h7F;
			  9'h11d: keyData[6:0] <= 7'h7F;
			  9'h11e: keyData[6:0] <= 7'h7F;
			  9'h11f: keyData[6:0] <= 7'h3A;	//WINDOWS OR APPLICATION KEY (option)
			  9'h120: keyData[6:0] <= 7'h7F;
			  9'h121: keyData[6:0] <= 7'h7F;
			  9'h122: keyData[6:0] <= 7'h7F;
			  9'h123: keyData[6:0] <= 7'h7F;
			  9'h124: keyData[6:0] <= 7'h7F;
			  9'h125: keyData[6:0] <= 7'h7F;
			  9'h126: keyData[6:0] <= 7'h7F;
			  9'h127: keyData[6:0] <= 7'h7F;
			  9'h128: keyData[6:0] <= 7'h7F;
			  9'h129: keyData[6:0] <= 7'h7F;
			  9'h12a: keyData[6:0] <= 7'h7F;
			  9'h12b: keyData[6:0] <= 7'h7F;
			  9'h12c: keyData[6:0] <= 7'h7F;
			  9'h12d: keyData[6:0] <= 7'h7F;
			  9'h12e: keyData[6:0] <= 7'h7F;
			  9'h12f: keyData[6:0] <= 7'h7F;
			  9'h130: keyData[6:0] <= 7'h7F;
			  9'h131: keyData[6:0] <= 7'h7F;
			  9'h132: keyData[6:0] <= 7'h7F;
			  9'h133: keyData[6:0] <= 7'h7F;
			  9'h134: keyData[6:0] <= 7'h7F;
			  9'h135: keyData[6:0] <= 7'h7F;
			  9'h136: keyData[6:0] <= 7'h7F;
			  9'h137: keyData[6:0] <= 7'h7F;
			  9'h138: keyData[6:0] <= 7'h7F;
			  9'h139: keyData[6:0] <= 7'h7F;
			  9'h13a: keyData[6:0] <= 7'h7F;
			  9'h13b: keyData[6:0] <= 7'h7F;
			  9'h13c: keyData[6:0] <= 7'h7F;
			  9'h13d: keyData[6:0] <= 7'h7F;
			  9'h13e: keyData[6:0] <= 7'h7F;
			  9'h13f: keyData[6:0] <= 7'h7F;
			  9'h140: keyData[6:0] <= 7'h7F;
			  9'h141: keyData[6:0] <= 7'h7F;
			  9'h142: keyData[6:0] <= 7'h7F;
			  9'h143: keyData[6:0] <= 7'h7F;
			  9'h144: keyData[6:0] <= 7'h7F;
			  9'h145: keyData[6:0] <= 7'h7F;
			  9'h146: keyData[6:0] <= 7'h7F;
			  9'h147: keyData[6:0] <= 7'h7F;
			  9'h148: keyData[6:0] <= 7'h7F;
			  9'h149: keyData[6:0] <= 7'h7F;
			  9'h14a: keyData[6:0] <= 7'h4B;	//KP /
			  9'h14b: keyData[6:0] <= 7'h7F;
			  9'h14c: keyData[6:0] <= 7'h7F;
			  9'h14d: keyData[6:0] <= 7'h7F;
			  9'h14e: keyData[6:0] <= 7'h7F;
			  9'h14f: keyData[6:0] <= 7'h7F;
			  9'h150: keyData[6:0] <= 7'h7F;
			  9'h151: keyData[6:0] <= 7'h7F;
			  9'h152: keyData[6:0] <= 7'h7F;
			  9'h153: keyData[6:0] <= 7'h7F;
			  9'h154: keyData[6:0] <= 7'h7F;
			  9'h155: keyData[6:0] <= 7'h7F;
			  9'h156: keyData[6:0] <= 7'h7F;
			  9'h157: keyData[6:0] <= 7'h7F;
			  9'h158: keyData[6:0] <= 7'h7F;
			  9'h159: keyData[6:0] <= 7'h7F;
			  9'h15a: keyData[6:0] <= 7'h4C;	//KP ENTER
			  9'h15b: keyData[6:0] <= 7'h7F;
			  9'h15c: keyData[6:0] <= 7'h7F;
			  9'h15d: keyData[6:0] <= 7'h7F;
			  9'h15e: keyData[6:0] <= 7'h7F;
			  9'h15f: keyData[6:0] <= 7'h7F;
			  9'h160: keyData[6:0] <= 7'h7F;
			  9'h161: keyData[6:0] <= 7'h7F;
			  9'h162: keyData[6:0] <= 7'h7F;
			  9'h163: keyData[6:0] <= 7'h7F;
			  9'h164: keyData[6:0] <= 7'h7F;
			  9'h165: keyData[6:0] <= 7'h7F;
			  9'h166: keyData[6:0] <= 7'h7F;
			  9'h167: keyData[6:0] <= 7'h7F;
			  9'h168: keyData[6:0] <= 7'h7F;
			  9'h169: keyData[6:0] <= 7'h77;	//END
			  9'h16a: keyData[6:0] <= 7'h7F;
			  9'h16b: keyData[6:0] <= 7'h3B;	//ARROW LEFT
			  9'h16c: keyData[6:0] <= 7'h73;	//HOME
			  9'h16d: keyData[6:0] <= 7'h7F;
			  9'h16e: keyData[6:0] <= 7'h7F;
			  9'h16f: keyData[6:0] <= 7'h7F;
			  9'h170: keyData[6:0] <= 7'h72;	//INSERT = HELP
			  9'h171: keyData[6:0] <= 7'h75;	//DELETE (KP clear?)
			  9'h172: keyData[6:0] <= 7'h3D;	//ARROW DOWN
			  9'h173: keyData[6:0] <= 7'h7F;
			  9'h174: keyData[6:0] <= 7'h3C;	//ARROW RIGHT
			  9'h175: keyData[6:0] <= 7'h3E;	//ARROW UP
			  9'h176: keyData[6:0] <= 7'h7F;
			  9'h177: keyData[6:0] <= 7'h7F;
			  9'h178: keyData[6:0] <= 7'h7F;
			  9'h179: keyData[6:0] <= 7'h7F;
			  9'h17a: keyData[6:0] <= 7'h79;	//PGDN <OSD>
			  9'h17b: keyData[6:0] <= 7'h7F;
			  9'h17c: keyData[6:0] <= 7'h69;	//PRTSCR (F13)
			  9'h17d: keyData[6:0] <= 7'h74;	//PGUP <OSD>
			  9'h17e: keyData[6:0] <= 7'h71;	//ctrl+break (F15)
			  9'h17f: keyData[6:0] <= 7'h7F;
			  9'h180: keyData[6:0] <= 7'h7F;
			  9'h181: keyData[6:0] <= 7'h7F;
			  9'h182: keyData[6:0] <= 7'h7F;
			  9'h183: keyData[6:0] <= 7'h7F;
			  9'h184: keyData[6:0] <= 7'h7F;
			  9'h185: keyData[6:0] <= 7'h7F;
			  9'h186: keyData[6:0] <= 7'h7F;
			  9'h187: keyData[6:0] <= 7'h7F;
			  9'h188: keyData[6:0] <= 7'h7F;
			  9'h189: keyData[6:0] <= 7'h7F;
			  9'h18a: keyData[6:0] <= 7'h7F;
			  9'h18b: keyData[6:0] <= 7'h7F;
			  9'h18c: keyData[6:0] <= 7'h7F;
			  9'h18d: keyData[6:0] <= 7'h7F;
			  9'h18e: keyData[6:0] <= 7'h7F;
			  9'h18f: keyData[6:0] <= 7'h7F;
			  9'h190: keyData[6:0] <= 7'h7F;
			  9'h191: keyData[6:0] <= 7'h7F;
			  9'h192: keyData[6:0] <= 7'h7F;
			  9'h193: keyData[6:0] <= 7'h7F;
			  9'h194: keyData[6:0] <= 7'h7F;
			  9'h195: keyData[6:0] <= 7'h7F;
			  9'h196: keyData[6:0] <= 7'h7F;
			  9'h197: keyData[6:0] <= 7'h7F;
			  9'h198: keyData[6:0] <= 7'h7F;
			  9'h199: keyData[6:0] <= 7'h7F;
			  9'h19a: keyData[6:0] <= 7'h7F;
			  9'h19b: keyData[6:0] <= 7'h7F;
			  9'h19c: keyData[6:0] <= 7'h7F;
			  9'h19d: keyData[6:0] <= 7'h7F;
			  9'h19e: keyData[6:0] <= 7'h7F;
			  9'h19f: keyData[6:0] <= 7'h7F;
			  9'h1a0: keyData[6:0] <= 7'h7F;
			  9'h1a1: keyData[6:0] <= 7'h7F;
			  9'h1a2: keyData[6:0] <= 7'h7F;
			  9'h1a3: keyData[6:0] <= 7'h7F;
			  9'h1a4: keyData[6:0] <= 7'h7F;
			  9'h1a5: keyData[6:0] <= 7'h7F;
			  9'h1a6: keyData[6:0] <= 7'h7F;
			  9'h1a7: keyData[6:0] <= 7'h7F;
			  9'h1a8: keyData[6:0] <= 7'h7F;
			  9'h1a9: keyData[6:0] <= 7'h7F;
			  9'h1aa: keyData[6:0] <= 7'h7F;
			  9'h1ab: keyData[6:0] <= 7'h7F;
			  9'h1ac: keyData[6:0] <= 7'h7F;
			  9'h1ad: keyData[6:0] <= 7'h7F;
			  9'h1ae: keyData[6:0] <= 7'h7F;
			  9'h1af: keyData[6:0] <= 7'h7F;
			  9'h1b0: keyData[6:0] <= 7'h7F;
			  9'h1b1: keyData[6:0] <= 7'h7F;
			  9'h1b2: keyData[6:0] <= 7'h7F;
			  9'h1b3: keyData[6:0] <= 7'h7F;
			  9'h1b4: keyData[6:0] <= 7'h7F;
			  9'h1b5: keyData[6:0] <= 7'h7F;
			  9'h1b6: keyData[6:0] <= 7'h7F;
			  9'h1b7: keyData[6:0] <= 7'h7F;
			  9'h1b8: keyData[6:0] <= 7'h7F;
			  9'h1b9: keyData[6:0] <= 7'h7F;
			  9'h1ba: keyData[6:0] <= 7'h7F;
			  9'h1bb: keyData[6:0] <= 7'h7F;
			  9'h1bc: keyData[6:0] <= 7'h7F;
			  9'h1bd: keyData[6:0] <= 7'h7F;
			  9'h1be: keyData[6:0] <= 7'h7F;
			  9'h1bf: keyData[6:0] <= 7'h7F;
			  9'h1c0: keyData[6:0] <= 7'h7F;
			  9'h1c1: keyData[6:0] <= 7'h7F;
			  9'h1c2: keyData[6:0] <= 7'h7F;
			  9'h1c3: keyData[6:0] <= 7'h7F;
			  9'h1c4: keyData[6:0] <= 7'h7F;
			  9'h1c5: keyData[6:0] <= 7'h7F;
			  9'h1c6: keyData[6:0] <= 7'h7F;
			  9'h1c7: keyData[6:0] <= 7'h7F;
			  9'h1c8: keyData[6:0] <= 7'h7F;
			  9'h1c9: keyData[6:0] <= 7'h7F;
			  9'h1ca: keyData[6:0] <= 7'h7F;
			  9'h1cb: keyData[6:0] <= 7'h7F;
			  9'h1cc: keyData[6:0] <= 7'h7F;
			  9'h1cd: keyData[6:0] <= 7'h7F;
			  9'h1ce: keyData[6:0] <= 7'h7F;
			  9'h1cf: keyData[6:0] <= 7'h7F;
			  9'h1d0: keyData[6:0] <= 7'h7F;
			  9'h1d1: keyData[6:0] <= 7'h7F;
			  9'h1d2: keyData[6:0] <= 7'h7F;
			  9'h1d3: keyData[6:0] <= 7'h7F;
			  9'h1d4: keyData[6:0] <= 7'h7F;
			  9'h1d5: keyData[6:0] <= 7'h7F;
			  9'h1d6: keyData[6:0] <= 7'h7F;
			  9'h1d7: keyData[6:0] <= 7'h7F;
			  9'h1d8: keyData[6:0] <= 7'h7F;
			  9'h1d9: keyData[6:0] <= 7'h7F;
			  9'h1da: keyData[6:0] <= 7'h7F;
			  9'h1db: keyData[6:0] <= 7'h7F;
			  9'h1dc: keyData[6:0] <= 7'h7F;
			  9'h1dd: keyData[6:0] <= 7'h7F;
			  9'h1de: keyData[6:0] <= 7'h7F;
			  9'h1df: keyData[6:0] <= 7'h7F;
			  9'h1e0: keyData[6:0] <= 7'h7F;
			  9'h1e1: keyData[6:0] <= 7'h7F;
			  9'h1e2: keyData[6:0] <= 7'h7F;
			  9'h1e3: keyData[6:0] <= 7'h7F;
			  9'h1e4: keyData[6:0] <= 7'h7F;
			  9'h1e5: keyData[6:0] <= 7'h7F;
			  9'h1e6: keyData[6:0] <= 7'h7F;
			  9'h1e7: keyData[6:0] <= 7'h7F;
			  9'h1e8: keyData[6:0] <= 7'h7F;
			  9'h1e9: keyData[6:0] <= 7'h7F;
			  9'h1ea: keyData[6:0] <= 7'h7F;
			  9'h1eb: keyData[6:0] <= 7'h7F;
			  9'h1ec: keyData[6:0] <= 7'h7F;
			  9'h1ed: keyData[6:0] <= 7'h7F;
			  9'h1ee: keyData[6:0] <= 7'h7F;
			  9'h1ef: keyData[6:0] <= 7'h7F;
			  9'h1f0: keyData[6:0] <= 7'h7F;	//ps2 release code(duplicate, see $f0)
			  9'h1f1: keyData[6:0] <= 7'h7F;
			  9'h1f2: keyData[6:0] <= 7'h7F;
			  9'h1f3: keyData[6:0] <= 7'h7F;
			  9'h1f4: keyData[6:0] <= 7'h7F;
			  9'h1f5: keyData[6:0] <= 7'h7F;
			  9'h1f6: keyData[6:0] <= 7'h7F;
			  9'h1f7: keyData[6:0] <= 7'h7F;
			  9'h1f8: keyData[6:0] <= 7'h7F;
			  9'h1f9: keyData[6:0] <= 7'h7F;
			  9'h1fa: keyData[6:0] <= 7'h7F;	//ps2 ack code(duplicate see $fa)
			  9'h1fb: keyData[6:0] <= 7'h7F;
			  9'h1fc: keyData[6:0] <= 7'h7F;
			  9'h1fd: keyData[6:0] <= 7'h7F;
			  9'h1fe: keyData[6:0] <= 7'h7F;
			  9'h1ff: keyData[6:0] <= 7'h7F;
			endcase
			if(capslock_key && press) capslock <= ~capslock;
			if(!(capslock_key && capslock)) begin
				keyData[7] <= ~press;
				keyStrobe <= 1;
			end
		end
		else begin
			keyStrobe <= 0;
		end
		end  // close `if (clk_en) begin` (kstb sync gated update)
	end  // close `else begin` (synchronizer free-runs even when clk_en is low)

	if (reset) capslock <= 0;
end

endmodule
