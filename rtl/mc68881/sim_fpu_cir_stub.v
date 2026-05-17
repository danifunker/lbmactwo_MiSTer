// CIR-protocol no-op FPU stub.
//
// Pin-compatible with mc68881_top so it can drop into any sim that
// would otherwise instantiate the real FPU. Accepts CIR writes and
// always responds 0x2000 to CIR_RESPONSE reads. 0x2000 is neither a
// Null Primary (would need bits[12]=0, bits[11:8]=1001) nor a Transfer
// Primary (would need bit[12]=1), so TG68K's cp_idle_resp decoder
// falls into its "unknown primary" branch and raises trap_1111 — an
// F-line emulator trap.
//
// Net effect: every FPU instruction the CPU issues triggers an F-line
// trap, which lets a software FPU package (SANE on Mac, FPSP-style on
// 68040) emulate the op. Much faster to simulate than the real FPU.
//
// Asserts dsack0_n + sense_n (FPU "present") so the M68020 protocol
// doesn't time out. Latches OpWord/Command/Condition/Restore writes
// purely for $display debug (gated by +fpu_stub_debug plusarg).

module sim_fpu_cir_stub
(
	input         clk,
	input         reset_n,
	input  [4:0]  a_in,
	input  [31:0] d_in,
	output reg [31:0] d_out,
	input  [1:0]  size_n,
	input         as_n,
	input         cs_n,
	input         rw,
	input         ds_n,
	output        dsack0_n,
	output        dsack1_n,
	output        sense_n,
	output        status_valid
);
	localparam [4:0] CIR_RESPONSE  = 5'd0;
	localparam [4:0] CIR_SAVE      = 5'd2;
	localparam [4:0] CIR_RESTORE   = 5'd3;
	localparam [4:0] CIR_OPWORD    = 5'd4;
	localparam [4:0] CIR_COMMAND   = 5'd5;
	localparam [4:0] CIR_CONDITION = 5'd7;
	localparam [4:0] CIR_OPERAND   = 5'd8;

	localparam [15:0] RESP_NULL  = 16'h2000;
	localparam [15:0] FRAME_NULL = 16'h0000;

	wire active = !as_n && !cs_n && !ds_n;
	assign dsack0_n = ~active;
	assign dsack1_n = 1'b1;
	assign sense_n = 1'b0;
	assign status_valid = 1'b1;

	reg active_d;
	reg [15:0] opword;
	reg [15:0] command;
	reg [15:0] condition;
	reg [15:0] restore_format;

	always @(*) begin
		case (a_in)
			CIR_RESPONSE: d_out = {16'h0000, RESP_NULL};
			CIR_SAVE:     d_out = {16'h0000, FRAME_NULL};
			CIR_OPERAND:  d_out = 32'h00000000;
			default:      d_out = {16'h0000, RESP_NULL};
		endcase
	end

	always @(posedge clk) begin
		if (!reset_n) begin
			active_d <= 1'b0;
			opword <= 16'h0000;
			command <= 16'h0000;
			condition <= 16'h0000;
			restore_format <= FRAME_NULL;
		end else begin
			active_d <= active;
			if (active && !active_d && !rw) begin
				case (a_in)
					CIR_OPWORD:    opword <= d_in[15:0];
					CIR_COMMAND:   command <= d_in[15:0];
					CIR_CONDITION: condition <= d_in[15:0];
					CIR_RESTORE:   restore_format <= d_in[15:0];
					default: ;
				endcase
				if ($test$plusargs("fpu_stub_debug")) begin
					$display("[FPU_STUB_WR] reg=%0d data=%04h opword=%04h command=%04h condition=%04h restore=%04h",
					         a_in, d_in[15:0], opword, command, condition, restore_format);
				end
			end
			if (active && !active_d && rw && $test$plusargs("fpu_stub_debug")) begin
				$display("[FPU_STUB_RD] reg=%0d data=%04h opword=%04h command=%04h condition=%04h restore=%04h size_n=%b",
				         a_in, d_out[15:0], opword, command, condition, restore_format, size_n);
			end
		end
	end
endmodule
