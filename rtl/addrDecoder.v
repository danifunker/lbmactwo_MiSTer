/*
	($000000 - $03FFFF) RAM  4MB, or Overlay ROM 4MB
	
	($400000 - $4FFFFF) ROM 1MB
		64K Mac 128K/512K ROM is $400000 - $40FFFF
		128K Mac 512Ke/Plus ROM is $400000 - $41FFFF
		If ROM is mirrored when A17 is 1, then SCSI is assumed to be unavailable

	($580000 - $580FFF) SCSI (Mac Plus only, not implemented here)

	($600000 - $7FFFFF) Overlay RAM 2MB

	($9FFFF8 - $BFFFFF) SCC
		The SCC is on the upper byte of the data bus, so you must use only even-addressed byte reads.
		When writing, you must use only odd-addressed byte writes (the MC68000 puts your data on both bytes of the bus, so it works correctly).
		A byte read of an odd SCC read address tries to reset the entire SCC.
		A word access to any SCC address will shift the phase of the computer's high-frequency timing by 128 ns.

		($9FFFF8) SCC read channel B control
		($9FFFFA) SCC read channel A control
		($9FFFFC) SCC read channel B data in/out
		($9FFFFE) SCC read channel A data in/out

		($BFFFF9) SCC write channel B control
		($BFFFFB) SCC write channel A control
		($BFFFFD) SCC write channel B data in/out
		($BFFFFF) SCC write channel A data in/out

	($DFE1FF - $DFFFFF) IWM
		The IWM is on the lower byte of the data bus, so use odd-addressed byte accesses only. 
		The 16 IWM registers are {8'hDF, 8'b111xxxx1, 8'hFF}:
			0	$0		ph0L		CA0 off (0)
			1	$200	ph0H		CA0 on (1)
			2	$400	ph1L		CA1 off (0)
			3	$600	ph1H		CA1 on (1)
			4	$800	h2L		CA2 off (0)
			5	$A00	ph2H		CA2 on (1)
			6	$C00	ph3L		LSTRB off (low)
			7	$E00	ph3H		LSTRB on (high)
			8	$1000	mtrOff	disk enable off
			9	$1200	mtrOn		disk enable on
			10	$1400	intDrive	select internal drive
			11	$1600	extDrive	select external drive
			12	$1800	q6L		Q6 off
			13	$1A00	q6H		Q6 on
			14	$1C00	q7L		Q7 off, read register
			15	$1E00	q7H		Q7 on, write register
		
	($EFE1FE - $EFFFFE) VIA
		The VIA is on the upper byte of the data bus, so use even-addressed byte accesses only.
		The 16 VIA registers are {8'hEF, 8'b111xxxx1, 8'hFE}:
			0	$0		vBufB		register B
			1	$200	?????		not used?
			2	$400	vDirB		register B direction register
			3	$600	vDirA		register A direction register
			4	$800	vT1C		timer 1 counter (low-order byte)
			5	$A00	vT1CH		timer 1 counter (high-order byte)
			6	$C00	vT1L		timer 1 latch (low-order byte)
			7	$E00	vT1LH		timer 1 latch (high-order byte)
			8	$1000	vT2C		timer 2 counter (low-order byte)
			9	$1200	vT2CH		timer 2 counter (high-order byte)
			10	$1400	vSR		shift register (keyboard)
			11	$1600	vACR		auxiliary control register
			12	$1800	vPCR		peripheral control register
			13	$1A00	vIFR		interrupt flag register
			14	$1C00	vIER		interrupt enable register
			15	$1E00	vBufA		register A

	($F00000 - $F00005) memory phase read test

	($F80000 - $FFFFEF) space for test software

	($FFFFF0 - $FFFFFF) interrupt vectors

	Note: This can all be decoded using only the highest 4 address bits, if SCSI, phase read test, and test software are not used.
	7 other address bits are used by peripherals to determine which register to access:
		A12-A9 - IWM and VIA
		A2-A0 - SCC

	NuBus Slot Space (Mac II):
		Standard Slot Space:  $s000 0000 - $sEFF FFFF (where s = slot 9-E)
			Slot $9:  $9000 0000 - $9EFF FFFF
			Slot $A:  $A000 0000 - $AEFF FFFF
			Slot $B:  $B000 0000 - $BEFF FFFF
			Slot $C:  $C000 0000 - $CEFF FFFF
			Slot $D:  $D000 0000 - $DEFF FFFF
			Slot $E:  $E000 0000 - $EEFF FFFF
		
		Super Slot Space:     $Fs00 0000 - $FsFF FFFF (where s = slot 9-E)
			Slot $9:  $F900 0000 - $F9FF FFFF
			Slot $A:  $FA00 0000 - $FAFF FFFF
			Slot $B:  $FB00 0000 - $FBFF FFFF
			Slot $C:  $FC00 0000 - $FCFF FFFF
			Slot $D:  $FD00 0000 - $FDFF FFFF
			Slot $E:  $FE00 0000 - $FEFF FFFF
*/

module addrDecoder(
	input [1:0] configROMSize,
	input [1:0] configRAMSize,	// 0=1MB, 1=2MB, 2+=4MB
	input [31:0] address,
	input _cpuAS,
	input memoryOverlayOn,
	output reg selectRAM,
	output reg selectROM,
	output reg selectSCSI,
	output reg selectSCC,
	output reg selectIWM,
	output reg selectVIA,
	output reg selectVIA2,
	output reg selectSEOverlay,
	output reg selectNuBus,
	output reg selectASC
);

	always @(*) begin
		selectRAM = 0;
		selectROM = 0;
		selectSCSI = 0;
		selectSCC = 0;
		selectIWM = 0;
		selectVIA = 0;
		selectVIA2 = 0;
		selectSEOverlay = 0;
		selectNuBus = 0;
		selectASC = 0;

		// ========================================================================
		// 32-bit NuBus Addressing (Mac II mode)
		// ========================================================================
		// Check if we're in 32-bit address space (not 24-bit compatibility mode)
		// 24-bit compatibility uses $00xxxxxx or $FFxxxxxx
		// Also treat $80xxxxxx as 24-bit: the Slot Manager flags sResource entry
		// pointers with BSET #7 (byte 0), turning $0000xxxx into $8000xxxx.
		// On real Mac II this bus-errors and the handler strips bit 31; since
		// TG68K doesn't fully implement format $B fault address, mirror $80→$00 instead.
		if (address[31:24] != 8'h00 && address[31:24] != 8'hFF
		    && address[31:24] != 8'h80) begin
			// Standard NuBus Slot Space: $9000_0000 - $EEFF_FFFF
			// Each slot gets $0F00_0000 bytes (slots 9-E)
			if (address[31:28] >= 4'h9 && address[31:28] <= 4'hE) begin
				// Only select if within the valid slot range ($x000_0000 - $xEFF_FFFF)
				// Avoid conflict with $xF00_0000+ which could be slot ROM space
				if (address[27:24] <= 4'hE) begin
					selectNuBus = !_cpuAS;
				end
			end
			// Super Slot Space: $F900_0000 - $FEFF_FFFF
			// Each slot gets $0100_0000 bytes (slots 9-E)
			else if (address[31:28] == 4'hF &&
			         address[27:24] >= 4'h9 &&
			         address[27:24] <= 4'hE) begin
				selectNuBus = !_cpuAS;
			end
			// Mac IIx 32-bit ROM space: $4000_0000 - $40FF_FFFF (with mirroring)
			// Mac IIx uses 256KB ROM, mirrored throughout $40xx_xxxx range
			else if (address[31:24] == 8'h40) begin
				selectROM = !_cpuAS;
			end
			// Mac II 32-bit I/O space: $50F0_xxxx only
			// Real hardware confirms $5000_xxxx does NOT mirror — falls through to RAM
			// Only $50Fx_xxxx decodes as I/O; $51E0_0000 bus errors (not periodic)
			// VIA1: +$0000, VIA2: +$2000, SCC: +$4000, SCSI: +$10000, IWM: +$16000
			else if (address[31:20] == 12'h50F) begin
				if (address[19:13] == 7'b0000_000)       // +$00_0000: VIA1
					selectVIA = !_cpuAS;
				else if (address[19:13] == 7'b0000_001)  // +$00_2000: VIA2
					selectVIA2 = !_cpuAS;
				else if (address[19:13] == 7'b0000_010)  // +$00_4000: SCC
					selectSCC = !_cpuAS;
				else if (address[19:14] == 6'b0001_00)   // +$01_0000: SCSI
					selectSCSI = !_cpuAS;
				else if (address[19:13] == 7'b0001_010)  // +$01_4000: ASC
					selectASC = !_cpuAS;
				else if (address[19:13] == 7'b0001_011)  // +$01_6000: IWM/SWIM
					selectIWM = !_cpuAS;
				else if (address[19:13] == 7'b0100_000)  // +$04_0000: VIA1 alt
					selectVIA = !_cpuAS;
			end
		end

		// ========================================================================
		// 24-bit Address Space (Mac Plus/SE/Classic and Mac II compatibility)
		// ========================================================================
		// This handles $00xxxxxx space (and $FFxxxxxx/$80xxxxxx which mirror it)
		//
		// RAM takes priority over 24-bit peripheral mappings, matching real Mac II
		// hardware where the SIMM decoder responds before the peripheral decoder.
		// With >4MB RAM, addresses like $40xxxx (ROM in 24-bit mode) become RAM.
		// Peripherals remain accessible via 32-bit addresses ($40000000 ROM,
		// $50F00000 I/O) which are decoded in the 32-bit section above.
		//
		// RAM ranges (with mirroring for ROM detection):
		//   1MB: $00-$0F only (no mirror)
		//   2MB: $00-$3F (mirrored in 4MB space, addr wraps at 2MB)
		//        plus bank B at $80-$8F, matching Mac II GLUE bank placement
		//   4MB: $00-$3F (no mirror)
		//   8MB: $00-$7F (no mirror, overrides 24-bit ROM/SCSI)
		if (address[31:24] == 8'h00 || address[31:24] == 8'hFF || address[31:24] == 8'h80) begin

			// Check if address is within RAM range (including mirror space)
			// Overlay mode is handled separately below
			if (!memoryOverlayOn && (
				(configRAMSize == 2'b00 && address[23:20] == 4'h0) ||                // 1MB: $00-$0F
				(configRAMSize == 2'b01 && address[23:22] == 2'b00) ||               // 2MB: $00-$3F (mirrored)
				(configRAMSize == 2'b01 && address[23:20] == 4'h8) ||                // 2MB: bank B at $80-$8F
				(configRAMSize == 2'b10 && address[23:22] == 2'b00) ||               // 4MB: $00-$3F
				(configRAMSize == 2'b11 && address[23]    == 1'b0)))                  // 8MB: $00-$7F
			begin
				selectRAM = !_cpuAS;
			end
			else begin
				// Overlay mode OR address outside RAM range: decode 24-bit peripherals
				casez (address[23:20])
					4'b00??: begin // $00_0000 - $3F_FFFF
						if (memoryOverlayOn) begin
							// Overlay mode: ROM appears at bottom of memory
							if (address[23:20] == 4'b0000) begin
								if (configROMSize[1]) begin
									// 256K ROM: $00_0000 - $03_FFFF
									if (address[19:18] == 2'b00)
										selectROM = !_cpuAS;
									else
										selectRAM = !_cpuAS;
								end else begin
									// 128K or smaller ROM: repeats to $0F_FFFF
									selectROM = !_cpuAS;
								end
							end else begin
								selectRAM = !_cpuAS;
							end
						end
						// Non-overlay outside RAM range: no select -> bus error
					end

					4'b0100: begin // $40_0000 - $4F_FFFF (ROM in 24-bit space)
						if (configROMSize[1] || address[17] == 1'b0)
							selectROM = !_cpuAS;
						selectSEOverlay = !_cpuAS;
					end

					4'b0101: begin // $50_0000 - $5F_FFFF (SCSI space)
						if (address[19]) // $58_0000 - $5F_FFFF
							selectSCSI = !_cpuAS;
						selectSEOverlay = !_cpuAS;
					end

					4'b0110: begin // $60_0000 - $6F_FFFF (Overlay RAM)
						if (memoryOverlayOn)
							selectRAM = !_cpuAS;
					end

					4'b10?1: begin // $A0/$B0 (SCC in 24-bit space)
						selectSCC = !_cpuAS;
					end

					4'b1100: begin // $C0 (IWM on some models)
						if (!configROMSize[1])
							selectIWM = !_cpuAS;
					end

					4'b1101: begin // $D0 (IWM)
						selectIWM = !_cpuAS;
					end

					4'b1110: begin // $E0 (VIA - Mac Plus/SE)
						if (address[19])
							selectVIA = !_cpuAS;
					end

					4'b1111: begin // $F0 (Mac II 24-bit I/O mirror of $5000_0000)
						if (address[19:13] == 7'b0000_000)       // VIA1
							selectVIA = !_cpuAS;
						else if (address[19:13] == 7'b0000_001)  // VIA2
							selectVIA2 = !_cpuAS;
						else if (address[19:13] == 7'b0000_010)  // SCC
							selectSCC = !_cpuAS;
						else if (address[19:14] == 6'b0001_00)   // SCSI
							selectSCSI = !_cpuAS;
						else if (address[19:13] == 7'b0001_010)  // ASC
							selectASC = !_cpuAS;
						else if (address[19:13] == 7'b0001_011)  // IWM/SWIM
							selectIWM = !_cpuAS;
						else if (address[19:13] == 7'b0100_000)  // VIA1 alt
							selectVIA = !_cpuAS;
					end

					default:
						; // select nothing
				endcase
			end
		end
	end
endmodule
