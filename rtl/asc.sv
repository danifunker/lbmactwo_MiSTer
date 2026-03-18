// Apple Sound Chip (ASC) - Mac II audio controller
// Supports FIFO playback mode and 4-voice wavetable synthesis
// Address space: 8KB ($50F14000-$50F15FFF)
//
// Reference: MAME apple/asc.cpp, Inside Macintosh: Sound

module asc(
	input         clk,        // 32.5 MHz system clock
	input         reset,      // active high
	input  [12:0] addr,       // 8KB address window
	input   [7:0] data_in,    // CPU data (upper byte of bus)
	output reg [7:0] data_out,
	input         cs,         // chip select
	input         rw,         // 1=read, 0=write
	input         ds,         // data strobe (active high, from !_cpuUDS)
	output reg signed [15:0] audio_left,
	output reg signed [15:0] audio_right,
	output        irq_n       // active-low IRQ to VIA2 CB1
);

	// =====================================================================
	// Dual 1KB RAM banks (FIFO / wavetable data)
	// =====================================================================
	reg [7:0] ram_a [0:1023];  // $000-$3FF
	reg [7:0] ram_b [0:1023];  // $400-$7FF

	// =====================================================================
	// Registers at offset $800+
	// =====================================================================
	reg [7:0] asc_mode;        // $801 - MODE: 0=off, 1=FIFO, 2=wavetable
	reg [7:0] asc_control;     // $802 - CONTROL: bit1=stereo
	reg [7:0] asc_fifo_mode;   // $803 - FIFO_MODE
	reg [7:0] asc_fifo_irq;    // $804 - FIFO_IRQ_STATUS (read clears)
	reg [7:0] asc_wt_control;  // $805 - WAVETABLE_CONTROL
	reg [7:0] asc_volume;      // $806 - VOLUME (0-255 scale)
	reg [7:0] asc_clock_rate;  // $807 - CLOCK_RATE: 0=22,257Hz, non-zero=11,127Hz

	// Phase increment and accumulator registers — 24-bit (9.15 fixed-point)
	// 4 voices, 3 bytes each
	// Increments: $810-$817 (high/low pairs per voice, 16-bit written by CPU)
	//   Real ASC has 24-bit increments; we store 24 bits, CPU writes the upper 16
	// Accumulators: $818-$81F (same layout)
	reg [23:0] phase_inc [0:3];
	reg [23:0] phase_acc [0:3];

	// =====================================================================
	// FIFO engine — dual circular buffers
	// =====================================================================
	reg [9:0] fifo_a_wr_ptr, fifo_a_rd_ptr;
	reg [9:0] fifo_b_wr_ptr, fifo_b_rd_ptr;
	reg [10:0] fifo_a_count, fifo_b_count;  // 0..1024 entries

	// =====================================================================
	// Sample rate divider
	// CLOCK_RATE=0: 22,257 Hz → 32,500,000/22,257 ≈ 1460 cycles
	// CLOCK_RATE≠0: 11,127 Hz → 32,500,000/11,127 ≈ 2921 cycles
	// =====================================================================
	localparam SAMPLE_DIV_22K = 16'd1460;
	localparam SAMPLE_DIV_11K = 16'd2921;
	wire [15:0] sample_div = (asc_clock_rate == 8'h00) ? SAMPLE_DIV_22K : SAMPLE_DIV_11K;
	reg [15:0] sample_counter;
	wire sample_tick = (sample_counter >= sample_div - 1);

	always @(posedge clk) begin
		if (reset) begin
			sample_counter <= 0;
		end else begin
			if (sample_tick)
				sample_counter <= 0;
			else
				sample_counter <= sample_counter + 1'd1;
		end
	end

	// =====================================================================
	// Control register decode
	// =====================================================================
	wire ctrl_stereo = asc_control[1];  // 0=mono (A→both), 1=stereo (A→L, B→R)

	// =====================================================================
	// IRQ generation
	// =====================================================================
	assign irq_n = ~(|asc_fifo_irq);

	// =====================================================================
	// CPU read/write interface
	// =====================================================================
	wire cpu_access = cs && ds;
	wire cpu_read   = cpu_access && rw;
	wire cpu_write  = cpu_access && !rw;

	// Register read mux
	always @(*) begin
		data_out = 8'h00;
		if (cpu_read) begin
			if (addr[12:10] == 3'b000) begin
				// $000-$3FF: RAM bank A
				data_out = ram_a[addr[9:0]];
			end
			else if (addr[12:10] == 3'b001) begin
				// $400-$7FF: RAM bank B
				data_out = ram_b[addr[9:0]];
			end
			else if (addr[12:11] == 2'b01) begin
				// $800-$FFF: registers
				case (addr[5:0])
					6'h00: data_out = 8'h00;           // VERSION = 0x00 (original ASC)
					6'h01: data_out = asc_mode;
					6'h02: data_out = asc_control;
					6'h03: data_out = asc_fifo_mode;
					6'h04: data_out = asc_fifo_irq;    // read clears (in clocked block)
					6'h05: data_out = asc_wt_control;
					6'h06: data_out = asc_volume;
					6'h07: data_out = asc_clock_rate;
					// Phase increment registers (upper 16 of 24 bits)
					6'h10: data_out = phase_inc[0][23:16];
					6'h11: data_out = phase_inc[0][15:8];
					6'h12: data_out = phase_inc[1][23:16];
					6'h13: data_out = phase_inc[1][15:8];
					6'h14: data_out = phase_inc[2][23:16];
					6'h15: data_out = phase_inc[2][15:8];
					6'h16: data_out = phase_inc[3][23:16];
					6'h17: data_out = phase_inc[3][15:8];
					// Phase accumulator registers (upper 16 of 24 bits)
					6'h18: data_out = phase_acc[0][23:16];
					6'h19: data_out = phase_acc[0][15:8];
					6'h1A: data_out = phase_acc[1][23:16];
					6'h1B: data_out = phase_acc[1][15:8];
					6'h1C: data_out = phase_acc[2][23:16];
					6'h1D: data_out = phase_acc[2][15:8];
					6'h1E: data_out = phase_acc[3][23:16];
					6'h1F: data_out = phase_acc[3][15:8];
					default: data_out = 8'h00;
				endcase
			end
		end
	end

	// =====================================================================
	// CPU write + FIFO/Wavetable engine
	// =====================================================================
	integer i;

	// Volume scaling: multiply signed 16-bit sample by unsigned 8-bit volume
	// Result is 24-bit, take upper 16 bits
	function signed [15:0] vol_scale;
		input signed [15:0] sample;
		input [7:0] vol;
		reg signed [23:0] product;
		begin
			product = sample * $signed({1'b0, vol});
			vol_scale = product[23:8];
		end
	endfunction

	always @(posedge clk) begin
		if (reset) begin
			asc_mode <= 0;
			asc_control <= 0;
			asc_fifo_mode <= 0;
			asc_fifo_irq <= 0;
			asc_wt_control <= 0;
			asc_volume <= 0;
			asc_clock_rate <= 0;
			fifo_a_wr_ptr <= 0;
			fifo_a_rd_ptr <= 0;
			fifo_b_wr_ptr <= 0;
			fifo_b_rd_ptr <= 0;
			fifo_a_count <= 0;
			fifo_b_count <= 0;
			audio_left <= 0;
			audio_right <= 0;
			for (i = 0; i < 4; i = i + 1) begin
				phase_inc[i] <= 0;
				phase_acc[i] <= 0;
			end
		end else begin
			// ----------------------------------------------------------
			// IRQ status clear on read of $804
			// ----------------------------------------------------------
			if (cpu_read && addr[12:11] == 2'b01 && addr[5:0] == 6'h04) begin
				asc_fifo_irq <= 0;
			end

			// ----------------------------------------------------------
			// CPU writes
			// ----------------------------------------------------------
			if (cpu_write) begin
				if (addr[12:10] == 3'b000) begin
					// $000-$3FF: RAM bank A / FIFO A write
					if (asc_mode == 8'h01) begin
						// FIFO mode: append to circular buffer
						ram_a[fifo_a_wr_ptr] <= data_in;
						fifo_a_wr_ptr <= fifo_a_wr_ptr + 1'd1;
						if (fifo_a_count < 11'd1024)
							fifo_a_count <= fifo_a_count + 1'd1;
					end else begin
						// Direct RAM write (wavetable loading)
						ram_a[addr[9:0]] <= data_in;
					end
				end
				else if (addr[12:10] == 3'b001) begin
					// $400-$7FF: RAM bank B / FIFO B write
					if (asc_mode == 8'h01) begin
						ram_b[fifo_b_wr_ptr] <= data_in;
						fifo_b_wr_ptr <= fifo_b_wr_ptr + 1'd1;
						if (fifo_b_count < 11'd1024)
							fifo_b_count <= fifo_b_count + 1'd1;
					end else begin
						ram_b[addr[9:0]] <= data_in;
					end
				end
				else if (addr[12:11] == 2'b01) begin
					// $800+: registers
					case (addr[5:0])
						6'h01: begin
							asc_mode <= data_in;
							// Reset FIFOs and phase on mode change
							if (data_in != asc_mode) begin
								fifo_a_wr_ptr <= 0;
								fifo_a_rd_ptr <= 0;
								fifo_b_wr_ptr <= 0;
								fifo_b_rd_ptr <= 0;
								fifo_a_count <= 0;
								fifo_b_count <= 0;
								for (i = 0; i < 4; i = i + 1)
									phase_acc[i] <= 0;
							end
						end
						6'h02: asc_control <= data_in;
						6'h03: asc_fifo_mode <= data_in;
						// 6'h04: fifo_irq is read-only (cleared on read)
						6'h05: asc_wt_control <= data_in;
						6'h06: asc_volume <= data_in;
						6'h07: asc_clock_rate <= data_in;
						// Phase increment: CPU writes 16-bit pairs → upper 16 of 24
						6'h10: phase_inc[0][23:16] <= data_in;
						6'h11: phase_inc[0][15:8]  <= data_in;
						6'h12: phase_inc[1][23:16] <= data_in;
						6'h13: phase_inc[1][15:8]  <= data_in;
						6'h14: phase_inc[2][23:16] <= data_in;
						6'h15: phase_inc[2][15:8]  <= data_in;
						6'h16: phase_inc[3][23:16] <= data_in;
						6'h17: phase_inc[3][15:8]  <= data_in;
						// Phase accumulator: CPU writes 16-bit pairs → upper 16 of 24
						6'h18: phase_acc[0][23:16] <= data_in;
						6'h19: phase_acc[0][15:8]  <= data_in;
						6'h1A: phase_acc[1][23:16] <= data_in;
						6'h1B: phase_acc[1][15:8]  <= data_in;
						6'h1C: phase_acc[2][23:16] <= data_in;
						6'h1D: phase_acc[2][15:8]  <= data_in;
						6'h1E: phase_acc[3][23:16] <= data_in;
						6'h1F: phase_acc[3][15:8]  <= data_in;
						default: ;
					endcase
				end
			end

			// ----------------------------------------------------------
			// FIFO playback engine (mode == 1)
			// ----------------------------------------------------------
			if (asc_mode == 8'h01 && sample_tick) begin
				// Always drain FIFO A (left / mono source)
				if (fifo_a_count > 0) begin
					fifo_a_rd_ptr <= fifo_a_rd_ptr + 1'd1;
					fifo_a_count <= fifo_a_count - 1'd1;
				end
				// Drain FIFO B only in stereo mode
				if (ctrl_stereo && fifo_b_count > 0) begin
					fifo_b_rd_ptr <= fifo_b_rd_ptr + 1'd1;
					fifo_b_count <= fifo_b_count - 1'd1;
				end

				// IRQ at half-empty (count reaches 512)
				if (fifo_a_count == 11'd512 || (ctrl_stereo && fifo_b_count == 11'd512))
					asc_fifo_irq[0] <= 1'b1;
				// IRQ at nearly empty (count reaches 1)
				if (fifo_a_count == 11'd1 || (ctrl_stereo && fifo_b_count == 11'd1))
					asc_fifo_irq[1] <= 1'b1;
			end

			// ----------------------------------------------------------
			// Wavetable engine (mode == 2)
			// ----------------------------------------------------------
			if (asc_mode == 8'h02 && sample_tick) begin
				for (i = 0; i < 4; i = i + 1) begin
					phase_acc[i] <= phase_acc[i] + phase_inc[i];
				end
			end

			// ----------------------------------------------------------
			// Audio output generation
			// ----------------------------------------------------------
			if (sample_tick) begin
				if (asc_mode == 8'h01) begin
					// FIFO mode: convert unsigned 8-bit → signed 16-bit, apply volume
					if (fifo_a_count > 0) begin
						audio_left <= vol_scale({ram_a[fifo_a_rd_ptr] ^ 8'h80, 8'h00}, asc_volume);
					end else begin
						audio_left <= 16'sh0000;
					end

					if (ctrl_stereo) begin
						// Stereo: FIFO B → right
						if (fifo_b_count > 0)
							audio_right <= vol_scale({ram_b[fifo_b_rd_ptr] ^ 8'h80, 8'h00}, asc_volume);
						else
							audio_right <= 16'sh0000;
					end else begin
						// Mono: duplicate left → right
						if (fifo_a_count > 0)
							audio_right <= vol_scale({ram_a[fifo_a_rd_ptr] ^ 8'h80, 8'h00}, asc_volume);
						else
							audio_right <= 16'sh0000;
					end
				end
				else if (asc_mode == 8'h02) begin
					// Wavetable mode with volume
					audio_left  <= vol_scale(wt_mix_left,  asc_volume);
					audio_right <= vol_scale(wt_mix_right, asc_volume);
				end
				else begin
					audio_left  <= 16'sh0000;
					audio_right <= 16'sh0000;
				end
			end
		end
	end

	// =====================================================================
	// Wavetable mixing (combinational)
	// 9.15 fixed-point: upper 9 bits of 24-bit phase → 512-sample index
	// =====================================================================
	wire [8:0] wt_idx0 = phase_acc[0][23:15];
	wire [8:0] wt_idx1 = phase_acc[1][23:15];
	wire [8:0] wt_idx2 = phase_acc[2][23:15];
	wire [8:0] wt_idx3 = phase_acc[3][23:15];

	// Ch 0: ram_a[0..511], Ch 1: ram_a[512..1023]
	// Ch 2: ram_b[0..511], Ch 3: ram_b[512..1023]
	wire [7:0] wt_sample0 = ram_a[{1'b0, wt_idx0}];
	wire [7:0] wt_sample1 = ram_a[{1'b1, wt_idx1}];
	wire [7:0] wt_sample2 = ram_b[{1'b0, wt_idx2}];
	wire [7:0] wt_sample3 = ram_b[{1'b1, wt_idx3}];

	// Convert unsigned to signed and extend to 16-bit
	wire signed [15:0] wt_s0 = {wt_sample0 ^ 8'h80, 8'h00};
	wire signed [15:0] wt_s1 = {wt_sample1 ^ 8'h80, 8'h00};
	wire signed [15:0] wt_s2 = {wt_sample2 ^ 8'h80, 8'h00};
	wire signed [15:0] wt_s3 = {wt_sample3 ^ 8'h80, 8'h00};

	// Mix: left = ch0 + ch1, right = ch2 + ch3 (with saturation-free /2 averaging)
	wire signed [15:0] wt_mix_left  = (wt_s0 >>> 1) + (wt_s1 >>> 1);
	wire signed [15:0] wt_mix_right = (wt_s2 >>> 1) + (wt_s3 >>> 1);

endmodule
