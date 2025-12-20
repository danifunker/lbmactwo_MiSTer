/*
 68000 compatible bus-wrapper for TG68K
 Switches instantiation to the TG68K.vhd wrapper to include FPU support internally.
 */

module tg68k #(
	parameter FPU_Enable = 1  // 1 = Enable FPU inside the VHDL wrapper
) (
	input clk,
	input reset,
	input phi1,
	input phi2,
	input [1:0] cpu,

	input  dtack_n,
	output rw_n,
	output as_n,
	output uds_n,
	output lds_n,
	output [2:0] fc,
	output reset_n,

	output reg E,
	input E_div,
	output E_PosClkEn,
	output E_NegClkEn,
	output vma_n,
	input vpa_n,

	input br_n,
	output bg_n,
	input bgack_n,

	input [2:0] ipl,
	input berr,
	input [15:0] din,
	output [15:0] dout,
	output reg [31:0] addr
);

wire  [1:0] tg68_busstate;
wire        tg68_clkena = phi1 && (s_state == 7 || tg68_busstate == 2'b01);
wire [31:0] tg68_addr;
wire [15:0] tg68_din;
reg  [15:0] tg68_din_r;
wire        tg68_uds_n;
wire        tg68_lds_n;
wire        tg68_rw;

// Interrupt autovector logic
wire auto_iack = fc == 3'b111 && !vpa_n;
wire [7:0] auto_vector = {4'h1, 1'b1, addr[3:1]};
assign tg68_din = auto_iack ? {auto_vector, auto_vector} : din;

reg         uds_n_r;
reg         lds_n_r;
reg         rw_r;
reg         as_n_r;

assign      as_n = as_n_r;
assign      uds_n = uds_n_r;
assign      lds_n = lds_n_r;
assign      rw_n = rw_r;

reg   [2:0] s_state;

always @(posedge clk) begin
	if (reset) begin
		s_state <= 0;
		as_n_r <= 1;
		rw_r <= 1;
		uds_n_r <= 1;
		lds_n_r <= 1;
	end else begin
		addr <= tg68_addr;

		if (phi1) begin
			if (s_state != 4) s_state <= s_state + 1'd1;
			if (busreq_ack || bus_granted) s_state <= s_state;
			if (tg68_busstate == 2'b01) s_state <= 0;

			case (s_state)
				1: if (tg68_busstate != 2'b01) begin
					rw_r <= tg68_rw;
					if (tg68_rw) begin
						uds_n_r <= tg68_uds_n;
						lds_n_r <= tg68_lds_n;
					end
					as_n_r <= 0;
				end
				3: if (tg68_busstate != 2'b01) begin
					if (!tg68_rw) begin
						uds_n_r <= tg68_uds_n;
						lds_n_r <= tg68_lds_n;
					end
				end
				7: rw_r <= 1;
				default :;
			endcase

		end else if (phi2) begin
			if (s_state != 4 || tg68_busstate == 2'b01 || !dtack_n || xVma || berr)
				s_state <= s_state + 1'd1;
			if ((busreq_ack || bus_granted) && !busrel_ack) s_state <= s_state;
			if (tg68_busstate == 2'b01) s_state <= 0;

			case (s_state)
				6: begin
					tg68_din_r <= tg68_din;
					uds_n_r <= 1;
					lds_n_r <= 1;
					as_n_r <= 1;
				end
				default :;
			endcase
		end
	end
end

// E clock and VMA generation
reg [3:0] eCntr;
reg rVma;
reg Vpai;
assign vma_n = rVma;
wire xVma = ~rVma & (eCntr == 8) & en_E;

assign E_PosClkEn = (phi2 & (eCntr == 5) & en_E);
assign E_NegClkEn = (phi2 & (eCntr == 9) & en_E);
reg en_E;

always @( posedge clk) begin
	if (reset) begin
		E <= 1'b0;
		eCntr <=0;
		rVma <= 1'b1;
		en_E <= 1'b1;
	end else begin
		if (phi1) begin
			Vpai <= vpa_n;
			if (E_div) en_E <= !en_E; else en_E <= 1'b1;
		end

		if (phi2 & en_E) begin
			if (eCntr == 9) E <= 1'b0;
			else if (eCntr == 5) E <= 1'b1;

			if (eCntr == 9) eCntr <= 0;
			else eCntr <= eCntr + 1'b1;
		end

		if (phi2 & s_state != 0 & ~Vpai & (eCntr == 3) & en_E)
			rVma <= 1'b0;
		else if (phi1 & eCntr == 0 & en_E)
			rVma <= 1'b1;
	end
end

// Bus arbitration
reg bg_n_r;
assign bg_n = bg_n_r;
wire busreq_ack = !br_n && s_state == 0;
wire busrel_ack = bus_acked && !bgack;
reg bgack, bus_granted, bus_acked, bus_acked_d;

always @(posedge clk) begin
	if (reset) begin
		bg_n_r <= 1;
		bus_granted <= 0;
		bus_acked <= 0;
	end else begin
		if (phi1) begin
			bgack <= ~bgack_n;
			bus_acked_d <= bus_acked;
		end
		if (phi2) begin
			if (busreq_ack) begin
				bg_n_r <= 0;
				bus_granted <= 1;
				bus_acked <= bgack;
			end
			if (bus_granted && bgack) bus_acked <= 1;
			if (bus_granted && bus_acked_d) bg_n_r <= 1;
			if (busrel_ack) begin
				bus_acked <= 0;
				bus_granted <= 0;
			end
		end
	end
end

// -------------------------------------------------------------------------
// CRITICAL CHANGE: Instantiating TG68K (Wrapper) instead of TG68KdotC_Kernel
// This wrapper contains the Kernel AND the FPU wired together internally.
// -------------------------------------------------------------------------
TG68K #(
	.SR_Read(2),
	.VBR_Stackframe(2),
	.extAddr_Mode(2),
	.MUL_Mode(2),
	.DIV_Mode(2),
	.BitField(2),
	.BarrelShifter(0),
	.MUL_Hardware(1),
	.FPU_Enable(1) // This parameter is passed to the VHDL wrapper
) tg68k_wrapper (
	.clk            ( clk           ),
	.nReset         ( ~reset        ),
	.clkena_in      ( tg68_clkena   ),
	.data_in        ( tg68_din_r    ),
	.IPL            ( ipl           ),
	.IPL_autovector ( 1'b0          ),
	.berr           ( berr          ),
	.clr_berr       ( /*tg68_clr_berr*/ ),
	.CPU            ( cpu           ),
	.addr_out       ( tg68_addr     ),
	.data_write     ( dout          ),
	.nUDS           ( tg68_uds_n    ),
	.nLDS           ( tg68_lds_n    ),
	.nWr            ( tg68_rw       ),
	.busstate       ( tg68_busstate ),
	.nResetOut      ( reset_n       ),
	.FC             ( fc            )
);

endmodule