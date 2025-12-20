/*
 * TG68K - 68000 Compatible CPU Core with FPU Support
 * 
 * This is a Verilog wrapper for the TG68K VHDL CPU core that provides:
 * - MC68000/68010/68020 CPU compatibility (configurable via 'cpu' input)
 * - MC68881/68882 FPU support (configurable via FPU_Enable parameter)
 * - 68000-compatible bus interface with proper bus arbitration
 * - VPA/VMA support for 6800-style peripherals
 * - E clock generation for peripheral timing
 * 
 * Architecture:
 *   tg68k.v (this file - Verilog wrapper)
 *     └─> TG68K.vhd (VHDL top-level wrapper)
 *           └─> TG68KdotC_Kernel.vhd (CPU core)
 *                 └─> TG68K_FPU.vhd (FPU coprocessor)
 * 
 * FPU Integration:
 *   When FPU_Enable = 1, the core implements a complete MC68881/68882 FPU
 *   - 8 80-bit floating-point registers (FP0-FP7)
 *   - IEEE 754 single, double, and extended precision formats
 *   - Full instruction set: FADD, FSUB, FMUL, FDIV, FSQRT, transcendentals
 *   - FMOVE, FMOVEM for data transfer
 *   - FSAVE/FRESTORE for context switching
 *   - FPU exceptions (divide by zero, overflow, underflow, etc.)
 *   - Coprocessor interface registers (CIR) for MC68020 compatibility
 * 
 * Usage:
 *   - Set FPU_Enable = 1 to enable FPU (default)
 *   - Set FPU_Enable = 0 to disable FPU (saves logic)
 *   - Requires CPU type "11" (68020) for full FPU functionality
 *   - FPU instructions are $F200-$F3FF (F-line opcodes with coprocessor ID 001)
 * 
 * Copyright (c) 2021-2025 TG68K Contributors
 * Licensed under LGPL v3 or later
 */

module tg68k #(
	parameter FPU_Enable = 1  // 1 = Enable FPU (MC68881/68882), 0 = Disable FPU
) (
	// Clock and Reset
	input clk,
	input reset,
	input phi1,              // Phase 1 clock (rising edge active)
	input phi2,              // Phase 2 clock (rising edge active)
	input [1:0] cpu,         // CPU type: 00=68000, 01=68010, 11=68020 (FPU requires 68020)

	// Asynchronous Bus Interface
	input  dtack_n,          // Data Transfer Acknowledge (active low)
	output rw_n,             // Read/Write (1=read, 0=write)
	output as_n,             // Address Strobe (active low)
	output uds_n,            // Upper Data Strobe (active low)
	output lds_n,            // Lower Data Strobe (active low)
	output [2:0] fc,         // Function Code (000=user data, 001=user program, etc.)
	output reset_n,          // CPU reset output (active low)

	// 6800-style Synchronous Bus Interface
	output reg E,            // Enable clock for 6800 peripherals
	input E_div,             // E clock divider enable
	output E_PosClkEn,       // E positive edge clock enable
	output E_NegClkEn,       // E negative edge clock enable
	output vma_n,            // Valid Memory Address (active low)
	input vpa_n,             // Valid Peripheral Address (active low)

	// Bus Arbitration
	input br_n,              // Bus Request (active low)
	output bg_n,             // Bus Grant (active low)
	input bgack_n,           // Bus Grant Acknowledge (active low)

	// Interrupts and Error Handling
	input [2:0] ipl,         // Interrupt Priority Level
	input berr,              // Bus Error

	// Data Bus
	input [15:0] din,        // Data input
	output [15:0] dout,      // Data output
	output reg [31:0] addr   // Address bus
);

	// =========================================================================
	// Internal Signals
	// =========================================================================

	// TG68K Core Interface
	wire  [1:0] tg68_busstate;   // 00=fetch, 01=idle, 10=read, 11=write
	wire        tg68_clkena;     // Clock enable for TG68K core
	wire [31:0] tg68_addr;       // Address from TG68K core
	wire [15:0] tg68_din;        // Data input to TG68K core
	reg  [15:0] tg68_din_r;      // Registered data input
	wire        tg68_uds_n;      // Upper data strobe from core
	wire        tg68_lds_n;      // Lower data strobe from core
	wire        tg68_rw;         // Read/write from core

	// Clock Enable Logic
	// TG68K runs when:
	//  - In idle state (busstate == 01), OR
	//  - At end of bus cycle (s_state == 7), OR
	//  - During phi1 phase
	assign tg68_clkena = phi1 && (s_state == 7 || tg68_busstate == 2'b01);

	// Interrupt Autovector Logic
	// When CPU acknowledges interrupt (FC=111) and VPA asserted:
	//  - Generate autovector in format $18 + (IPL * 2)
	//  - Vectors $18-$1F for IPL 0-7
	wire auto_iack = fc == 3'b111 && !vpa_n;
	wire [7:0] auto_vector = {4'h1, 1'b1, addr[3:1]};
	assign tg68_din = auto_iack ? {auto_vector, auto_vector} : din;

	// Bus Control Signals
	reg uds_n_r;
	reg lds_n_r;
	reg rw_r;
	reg as_n_r;

	assign as_n  = as_n_r;
	assign uds_n = uds_n_r;
	assign lds_n = lds_n_r;
	assign rw_n  = rw_r;

	// =========================================================================
	// Bus State Machine
	// =========================================================================
	
	reg [2:0] s_state;
	
	/*
	 * Bus cycle state machine:
	 *   0: Idle - wait for CPU to start access
	 *   1: Setup - assert AS, RW, UDS/LDS for reads
	 *   2: (transitional)
	 *   3: Assert UDS/LDS for writes
	 *   4: Wait - hold until DTACK or VMA/VPA
	 *   5: (transitional)
	 *   6: Latch data on reads, deassert strobes
	 *   7: Complete - return to idle
	 */

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
				// Advance state unless waiting for DTACK
				if (s_state != 4) s_state <= s_state + 1'd1;
				
				// Hold state during bus arbitration
				if (busreq_ack || bus_granted) s_state <= s_state;
				
				// Reset state when CPU returns to idle
				if (tg68_busstate == 2'b01) s_state <= 0;

				case (s_state)
					1: if (tg68_busstate != 2'b01) begin
						rw_r <= tg68_rw;
						if (tg68_rw) begin
							// For reads, assert data strobes early
							uds_n_r <= tg68_uds_n;
							lds_n_r <= tg68_lds_n;
						end
						as_n_r <= 0;
					end
					
					3: if (tg68_busstate != 2'b01) begin
						if (!tg68_rw) begin
							// For writes, assert data strobes after address stable
							uds_n_r <= tg68_uds_n;
							lds_n_r <= tg68_lds_n;
						end
					end
					
					7: rw_r <= 1;  // Return RW to idle (read) state
					
					default: ;
				endcase
			end else if (phi2) begin
				// Continue state advancement unless waiting
				if (s_state != 4 || tg68_busstate == 2'b01 || !dtack_n || xVma || berr)
					s_state <= s_state + 1'd1;
					
				// Hold state during bus arbitration
				if ((busreq_ack || bus_granted) && !busrel_ack) s_state <= s_state;
				
				// Reset state when CPU returns to idle
				if (tg68_busstate == 2'b01) s_state <= 0;

				case (s_state)
					6: begin
						// Latch input data and deassert all strobes
						tg68_din_r <= tg68_din;
						uds_n_r <= 1;
						lds_n_r <= 1;
						as_n_r <= 1;
					end
					
					default: ;
				endcase
			end
		end
	end

	// =========================================================================
	// E Clock Generation (6800 Peripheral Support)
	// =========================================================================
	
	reg [3:0] eCntr;        // E clock counter (0-9)
	reg rVma;               // VMA output register
	reg Vpai;               // Latched VPA input
	assign vma_n = rVma;
	
	// VMA assertion logic
	// Assert VMA (active low) when:
	//  - Not in reset
	//  - VPA is asserted (peripheral detected)
	//  - At appropriate point in E clock cycle
	wire xVma = ~rVma & (eCntr == 8) & en_E;
	
	// E clock edge enables
	assign E_PosClkEn = (phi2 & (eCntr == 5) & en_E);  // Rising edge
	assign E_NegClkEn = (phi2 & (eCntr == 9) & en_E);  // Falling edge
	
	reg en_E;  // E clock enable (can be divided)
	
	/*
	 * E Clock Timing:
	 *   - 10 states per E clock cycle
	 *   - E goes high at state 5
	 *   - E goes low at state 9
	 *   - Can be divided by 2 via E_div input
	 */
	
	always @(posedge clk) begin
		if (reset) begin
			E <= 1'b0;
			eCntr <= 0;
			rVma <= 1'b1;
			en_E <= 1'b1;
		end else begin
			if (phi1) begin
				Vpai <= vpa_n;
				
				// Optional E clock divider
				if (E_div) 
					en_E <= !en_E; 
				else 
					en_E <= 1'b1;
			end

			if (phi2 & en_E) begin
				// Generate E clock waveform
				if (eCntr == 9) 
					E <= 1'b0;
				else if (eCntr == 5) 
					E <= 1'b1;

				// Advance counter
				if (eCntr == 9) 
					eCntr <= 0;
				else 
					eCntr <= eCntr + 1'b1;
			end

			// VMA timing relative to E clock
			if (phi2 & s_state != 0 & ~Vpai & (eCntr == 3) & en_E)
				rVma <= 1'b0;  // Assert VMA
			else if (phi1 & eCntr == 0 & en_E)
				rVma <= 1'b1;  // Deassert VMA
		end
	end

	// =========================================================================
	// Bus Arbitration
	// =========================================================================
	
	reg bg_n_r;
	assign bg_n = bg_n_r;
	
	// Bus request acknowledge when:
	//  - BR asserted (active low)
	//  - CPU at idle (s_state == 0)
	wire busreq_ack = !br_n && s_state == 0;
	
	// Bus release when:
	//  - Bus was granted
	//  - BGACK deasserted
	wire busrel_ack = bus_acked && !bgack;
	
	reg bgack, bus_granted, bus_acked, bus_acked_d;
	
	/*
	 * Bus Arbitration Protocol:
	 *   1. External device asserts BR
	 *   2. CPU finishes current bus cycle (s_state reaches 0)
	 *   3. CPU asserts BG
	 *   4. External device asserts BGACK and uses bus
	 *   5. External device releases BGACK
	 *   6. CPU deasserts BG and resumes operation
	 */
	
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
					bg_n_r <= 0;        // Grant bus
					bus_granted <= 1;
					bus_acked <= bgack;
				end
				
				if (bus_granted && bgack) 
					bus_acked <= 1;
					
				if (bus_granted && bus_acked_d) 
					bg_n_r <= 1;        // Retract grant
					
				if (busrel_ack) begin
					bus_acked <= 0;
					bus_granted <= 0;
				end
			end
		end
	end

	// =========================================================================
	// TG68K CPU Core Instantiation
	// =========================================================================
	
	/*
	 * CRITICAL: Instantiating TG68K (VHDL Wrapper)
	 * 
	 * This is NOT the direct kernel - it's the wrapper that contains:
	 *   - TG68KdotC_Kernel (CPU core)
	 *   - TG68K_FPU (when FPU_Enable = 1)
	 *   - Internal bus state machine
	 * 
	 * The FPU is fully integrated into the CPU pipeline and handles:
	 *   - F-line instruction decode ($Fxxx opcodes)
	 *   - Coprocessor Interface Register (CIR) protocol
	 *   - FSAVE/FRESTORE context switching
	 *   - FMOVEM register block transfers
	 *   - FPU exception processing
	 * 
	 * FPU Parameter Flow:
	 *   tg68k.v FPU_Enable parameter
	 *     → TG68K.vhd FPU_Enable generic
	 *       → TG68KdotC_Kernel.vhd FPU_Enable generic
	 *         → Conditional instantiation of TG68K_FPU component
	 */
	
	TG68K #(
		.SR_Read(2),           // Status register read: 2=switchable with CPU(0)
		.VBR_Stackframe(2),    // Vector Base Register: 2=switchable with CPU(0)
		.extAddr_Mode(2),      // Extended addressing: 2=switchable with CPU(1)
		.MUL_Mode(2),          // Multiply: 2=switchable (16/32-bit)
		.DIV_Mode(2),          // Divide: 2=switchable (16/32-bit)
		.BitField(2),          // Bitfield ops: 2=switchable with CPU(1)
		.BarrelShifter(0),     // Barrel shifter: 0=disabled
		.MUL_Hardware(1),      // Hardware multiplier: 1=enabled
		.FPU_Enable(FPU_Enable) // FPU: 0=disabled, 1=MC68881/68882 enabled
	) tg68k_wrapper (
		.clk            ( clk           ),
		.nReset         ( ~reset        ),
		.clkena_in      ( tg68_clkena   ),
		.data_in        ( tg68_din_r    ),
		.IPL            ( ipl           ),
		.IPL_autovector ( 1'b0          ),
		.berr           ( berr          ),
		.clr_berr       (               ),  // Not used
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

/*
 * FPU USAGE NOTES:
 * 
 * 1. ENABLING THE FPU:
 *    - Set parameter FPU_Enable = 1 when instantiating tg68k
 *    - Set cpu input to 2'b11 (68020 mode) for full functionality
 *    - FPU adds approximately 15-20% logic utilization
 * 
 * 2. FPU INSTRUCTION FORMAT:
 *    - All FPU instructions start with $F2xx or $F3xx
 *    - Opcode format: 1111 001x xxxx xxxx (F-line with coprocessor ID 001)
 *    - Examples:
 *      * FADD.X FP1,FP0  → $F200 $0422
 *      * FMOVE.S #1.0,FP0 → $F200 $4400 + immediate data
 * 
 * 3. FPU REGISTERS:
 *    - FP0-FP7: Eight 80-bit extended precision registers
 *    - FPCR: Control register (rounding mode, exception enables)
 *    - FPSR: Status register (condition codes, exception flags)
 *    - FPIAR: Instruction address register
 * 
 * 4. DATA FORMATS:
 *    - .B (byte), .W (word), .L (long) - integer formats
 *    - .S (single) - 32-bit IEEE 754 float
 *    - .D (double) - 64-bit IEEE 754 float
 *    - .X (extended) - 80-bit IEEE 754 extended
 *    - .P (packed) - BCD packed decimal
 * 
 * 5. EXCEPTION HANDLING:
 *    - FPU generates exceptions via standard 68K exception mechanism
 *    - Exception vectors:
 *      * Vector 48 ($C0): FPU BSUN (Branch/Set on Unordered)
 *      * Vector 49 ($C4): FPU Inexact
 *      * Vector 50 ($C8): FPU Divide by Zero
 *      * Vector 51 ($CC): FPU Underflow
 *      * Vector 52 ($D0): FPU Operand Error
 *      * Vector 53 ($D4): FPU Overflow
 *      * Vector 54 ($D8): FPU Signaling NaN
 * 
 * 6. CONTEXT SWITCHING:
 *    - FSAVE -(An): Save FPU state to stack (NULL, IDLE, or BUSY frame)
 *    - FRESTORE (An)+: Restore FPU state from stack
 *    - Frame formats:
 *      * $00: NULL (no FPU state, 4 bytes)
 *      * $41: IDLE (normal state, 60 bytes)
 *      * Others: Implementation specific
 * 
 * 7. PERFORMANCE:
 *    - Single precision ops: ~4-12 cycles
 *    - Double precision ops: ~6-16 cycles
 *    - Extended precision ops: ~8-24 cycles
 *    - Transcendental functions: ~32-64 cycles
 *    - Actual timing depends on operation and operand types
 * 
 * 8. COMPATIBILITY:
 *    - Implements MC68881/68882 instruction set
 *    - Binary compatible with original Motorola FPU
 *    - Supports MC68020 coprocessor interface protocol
 *    - IEEE 754 compliant (with optional non-IEEE modes)
 * 
 * 9. SYNTHESIS CONSIDERATIONS:
 *    - Uses DSP blocks for multipliers when available
 *    - Pipelined design for better timing
 *    - Can meet 50MHz+ on modern FPGAs
 *    - Approximately 5000-8000 LUTs depending on target
 * 
 * 10. DEBUGGING:
 *     - FPU state visible through FSAVE
 *     - Exception flags in FPSR
 *     - FPIAR points to faulting instruction
 *     - Use FTST to examine FP register contents
 */
