// Apple Sound Chip (ASC) - Mac II audio controller
// Supports FIFO playback mode and 4-voice wavetable synthesis
// Address space: 8KB ($50F14000-$50F15FFF)
//
// Reference: Snow core/src/mac/asc.rs, MAME apple/asc.cpp

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
	reg [7:0] asc_fifo_mode;   // $803 - FIFO_MODE: bit7=clear FIFOs
	reg [7:0] asc_fifo_irq;    // $804 - FIFO_IRQ_STATUS (read clears)
	reg [7:0] asc_wt_control;  // $805 - WAVETABLE_CONTROL
	reg [7:0] asc_clock_rate;  // $807 - CLOCK_RATE: 0=22,257Hz, non-zero=11,127Hz

	// Phase and frequency registers — 32-bit, 4 channels
	// Layout at $810-$82F: 8 bytes per channel (4 phase + 4 freq), big-endian
	//   Ch0: phase=$810-$813, freq=$814-$817
	//   Ch1: phase=$818-$81B, freq=$81C-$81F
	//   Ch2: phase=$820-$823, freq=$824-$827
	//   Ch3: phase=$828-$82B, freq=$82C-$82F
	reg [31:0] phase [0:3];
	reg [31:0] freq  [0:3];

	// =====================================================================
	// FIFO engine — dual circular buffers
	// =====================================================================
	reg [9:0] fifo_a_wr_ptr, fifo_a_rd_ptr;
	reg [9:0] fifo_b_wr_ptr, fifo_b_rd_ptr;
	reg [10:0] fifo_a_count, fifo_b_count;  // 0..1024 entries

	// Last sample hold for FIFO empty case
	reg [7:0] fifo_last_l, fifo_last_r;

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

	// Channel register decode for $810-$82F
	wire [5:0] reg_off = addr[5:0] - 6'h10;  // 0-31 within channel reg space
	wire [1:0] ch_num = reg_off[4:3];
	wire ch_is_freq = reg_off[2];
	wire [1:0] ch_byte = reg_off[1:0];  // big-endian: 0=MSB, 3=LSB

	// Register read mux
	always @(*) begin
		data_out = 8'h00;
		if (cpu_read) begin
			if (addr[12:10] == 3'b000 && asc_mode == 8'h02) begin
				// $000-$3FF: RAM bank A (wavetable mode only)
				data_out = ram_a[addr[9:0]];
			end
			else if (addr[12:10] == 3'b001 && asc_mode == 8'h02) begin
				// $400-$7FF: RAM bank B (wavetable mode only)
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
					6'h07: data_out = asc_clock_rate;
					default: begin
						// $810-$82F: channel phase/freq registers
						if (addr[5:0] >= 6'h10 && addr[5:0] <= 6'h2F) begin
							if (ch_is_freq)
								case (ch_byte)
									2'd0: data_out = freq[ch_num][31:24];
									2'd1: data_out = freq[ch_num][23:16];
									2'd2: data_out = freq[ch_num][15:8];
									2'd3: data_out = freq[ch_num][7:0];
								endcase
							else
								case (ch_byte)
									2'd0: data_out = phase[ch_num][31:24];
									2'd1: data_out = phase[ch_num][23:16];
									2'd2: data_out = phase[ch_num][15:8];
									2'd3: data_out = phase[ch_num][7:0];
								endcase
						end
					end
				endcase
			end
		end
	end

	// =====================================================================
	// CPU write + FIFO/Wavetable engine
	// =====================================================================
	integer i;

	always @(posedge clk) begin
		if (reset) begin
			asc_mode <= 0;
			asc_control <= 0;
			asc_fifo_mode <= 0;
			asc_fifo_irq <= 0;
			asc_wt_control <= 0;
			asc_clock_rate <= 0;
			fifo_a_wr_ptr <= 0;
			fifo_a_rd_ptr <= 0;
			fifo_b_wr_ptr <= 0;
			fifo_b_rd_ptr <= 0;
			fifo_a_count <= 0;
			fifo_b_count <= 0;
			fifo_last_l <= 0;
			fifo_last_r <= 0;
			audio_left <= 0;
			audio_right <= 0;
			for (i = 0; i < 4; i = i + 1) begin
				phase[i] <= 0;
				freq[i] <= 0;
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
						// Direct RAM write (wavetable loading or off)
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
									phase[i] <= 0;
							end
						end
						6'h02: asc_control <= data_in;
						6'h03: begin
							asc_fifo_mode <= data_in;
							// Bit 7: clear FIFOs
							if (data_in[7]) begin
								fifo_a_wr_ptr <= 0;
								fifo_a_rd_ptr <= 0;
								fifo_b_wr_ptr <= 0;
								fifo_b_rd_ptr <= 0;
								fifo_a_count <= 0;
								fifo_b_count <= 0;
							end
						end
						// 6'h04: fifo_irq is read-only (cleared on read)
						6'h05: asc_wt_control <= data_in;
						6'h07: asc_clock_rate <= data_in;
						default: begin
							// $810-$82F: channel phase/freq registers
							if (addr[5:0] >= 6'h10 && addr[5:0] <= 6'h2F) begin
								if (ch_is_freq) begin
									case (ch_byte)
										2'd0: freq[ch_num][31:24] <= data_in;
										2'd1: freq[ch_num][23:16] <= data_in;
										2'd2: freq[ch_num][15:8]  <= data_in;
										2'd3: freq[ch_num][7:0]   <= data_in;
									endcase
								end else begin
									case (ch_byte)
										2'd0: phase[ch_num][31:24] <= data_in;
										2'd1: phase[ch_num][23:16] <= data_in;
										2'd2: phase[ch_num][15:8]  <= data_in;
										2'd3: phase[ch_num][7:0]   <= data_in;
									endcase
								end
							end
						end
					endcase
				end
			end

			// ----------------------------------------------------------
			// FIFO playback engine (mode == 1)
			// ----------------------------------------------------------
			if (asc_mode == 8'h01 && sample_tick) begin
				// Drain FIFO A, hold last sample if empty
				if (fifo_a_count > 0) begin
					fifo_last_l <= ram_a[fifo_a_rd_ptr];
					fifo_a_rd_ptr <= fifo_a_rd_ptr + 1'd1;
					fifo_a_count <= fifo_a_count - 1'd1;
				end
				// Drain FIFO B only in stereo mode
				if (ctrl_stereo && fifo_b_count > 0) begin
					fifo_last_r <= ram_b[fifo_b_rd_ptr];
					fifo_b_rd_ptr <= fifo_b_rd_ptr + 1'd1;
					fifo_b_count <= fifo_b_count - 1'd1;
				end

				// IRQ at half-empty (count reaches 512)
				if (fifo_a_count == 11'd512 || (ctrl_stereo && fifo_b_count == 11'd512))
					asc_fifo_irq[0] <= 1'b1;
				// IRQ at empty
				if (fifo_a_count == 11'd1 || (ctrl_stereo && fifo_b_count == 11'd1))
					asc_fifo_irq[1] <= 1'b1;
			end

			// ----------------------------------------------------------
			// Wavetable engine (mode == 2)
			// ----------------------------------------------------------
			if (asc_mode == 8'h02 && sample_tick) begin
				for (i = 0; i < 4; i = i + 1) begin
					phase[i] <= phase[i] + freq[i];
				end
			end

			// ----------------------------------------------------------
			// Audio output generation (no volume scaling, raw samples)
			// ----------------------------------------------------------
			if (sample_tick) begin
				if (asc_mode == 8'h01) begin
					// FIFO mode: use current or last sample
					// Convert unsigned 8-bit → signed 16-bit
					if (fifo_a_count > 0)
						audio_left <= {ram_a[fifo_a_rd_ptr] ^ 8'h80, 8'h00};
					else
						audio_left <= {fifo_last_l ^ 8'h80, 8'h00};

					if (ctrl_stereo) begin
						if (fifo_b_count > 0)
							audio_right <= {ram_b[fifo_b_rd_ptr] ^ 8'h80, 8'h00};
						else
							audio_right <= {fifo_last_r ^ 8'h80, 8'h00};
					end else begin
						// Mono: duplicate left → right
						if (fifo_a_count > 0)
							audio_right <= {ram_a[fifo_a_rd_ptr] ^ 8'h80, 8'h00};
						else
							audio_right <= {fifo_last_l ^ 8'h80, 8'h00};
					end
				end
				else if (asc_mode == 8'h02) begin
					// Wavetable mode: mix all 4 channels, output to both L and R
					audio_left  <= wt_mix;
					audio_right <= wt_mix;
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
	// 32-bit phase, upper 9 bits after >>15 give 512-sample wavetable index
	// All 4 channels summed and divided by 4, output to both L and R
	// =====================================================================
	wire [8:0] wt_idx0 = phase[0][23:15];
	wire [8:0] wt_idx1 = phase[1][23:15];
	wire [8:0] wt_idx2 = phase[2][23:15];
	wire [8:0] wt_idx3 = phase[3][23:15];

	// Ch 0: ram_a[0..511], Ch 1: ram_a[512..1023]
	// Ch 2: ram_b[0..511], Ch 3: ram_b[512..1023]
	wire [7:0] wt_sample0 = ram_a[{1'b0, wt_idx0}];
	wire [7:0] wt_sample1 = ram_a[{1'b1, wt_idx1}];
	wire [7:0] wt_sample2 = ram_b[{1'b0, wt_idx2}];
	wire [7:0] wt_sample3 = ram_b[{1'b1, wt_idx3}];

	// Sum all 4 unsigned samples, divide by 4 → unsigned 8-bit average
	wire [9:0] wt_sum = wt_sample0 + wt_sample1 + wt_sample2 + wt_sample3;
	wire [7:0] wt_avg = wt_sum[9:2];

	// Convert unsigned 8-bit average → signed 16-bit
	wire signed [15:0] wt_mix = {wt_avg ^ 8'h80, 8'h00};

endmodule
