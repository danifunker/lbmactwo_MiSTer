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
	input [31:0] address,
	input _cpuAS,
	input memoryOverlayOn,
	output reg selectRAM,
	output reg selectROM,
	output reg selectSCSI,
	output reg selectSCC,
	output reg selectIWM,
	output reg selectVIA,
	output reg selectSEOverlay,
	output reg selectNuBus
);

	always @(*) begin
		selectRAM = 0;
		selectROM = 0;
		selectSCSI = 0;
		selectSCC = 0;
		selectIWM = 0;
		selectVIA = 0;
		selectSEOverlay = 0;
		selectNuBus = 0;

		// ========================================================================
		// 32-bit NuBus Addressing (Mac II mode)
		// ========================================================================
		// Check if we're in 32-bit address space (not 24-bit compatibility mode)
		// 24-bit compatibility uses $00xxxxxx or $FFxxxxxx
		if (address[31:24] != 8'h00 && address[31:24] != 8'hFF) begin
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
			// Mac IIx 32-bit I/O space: $5000_0000 - $500F_FFFF
			// VIA1: $5000_0000, VIA2: $5000_2000, SCC: $5000_4000
			// SCSI: $5001_0000, IWM: $5001_6000
			else if (address[31:20] == 12'h500) begin
				if (address[19:13] == 7'b0000_000)       // $5000_0000 - $5000_1FFF: VIA1
					selectVIA = !_cpuAS;
				else if (address[19:13] == 7'b0000_001)  // $5000_2000 - $5000_3FFF: VIA2
					selectVIA = !_cpuAS;
				else if (address[19:13] == 7'b0000_010)  // $5000_4000 - $5000_5FFF: SCC
					selectSCC = !_cpuAS;
				else if (address[19:14] == 6'b0001_00)   // $5001_0000 - $5001_3FFF: SCSI
					selectSCSI = !_cpuAS;
				else if (address[19:13] == 7'b0001_011)  // $5001_6000 - $5001_7FFF: IWM/SWIM
					selectIWM = !_cpuAS;
				else if (address[19:13] == 7'b0100_000)  // $5004_0000 - $5004_1FFF: VIA1 alt
					selectVIA = !_cpuAS;
			end
		end

		// ========================================================================
		// 24-bit Address Space (Mac Plus/SE/Classic and Mac II compatibility)
		// ========================================================================
		// This handles $00xxxxxx space (and $FFxxxxxx which mirrors it)
		if (address[31:24] == 8'h00 || address[31:24] == 8'hFF) begin
			casez (address[23:20])
				4'b00??: begin // $00_0000 - $3F_FFFF (4MB)
					if (memoryOverlayOn == 0)
						selectRAM = !_cpuAS;
					else begin
						// Overlay mode: ROM appears at bottom of memory
						// Mac II: 256K ROM at $00_0000 - $03_FFFF when overlay is on
						// Mac Plus/SE: 128K ROM can extend to $0F_FFFF with mirroring
						if (address[23:20] == 4'b0000) begin
							// Check ROM size: if 256K (configROMSize[1]==1), only map first 256K
							if (configROMSize[1]) begin
								// 256K ROM: only $00_0000 - $03_FFFF
								if (address[19:18] == 2'b00)  // address < $040000
									selectROM = !_cpuAS;
								else
									selectRAM = !_cpuAS;  // Above ROM = RAM
							end else begin
								// 128K or smaller ROM: original behavior (repeats to $0F_FFFF)
								selectROM = !_cpuAS;
							end
						end else begin
							// Above $0F_FFFF = RAM even in overlay mode
							selectRAM = !_cpuAS;
						end
					end
				end
				
				4'b0100: begin // $40_0000 - $4F_FFFF (ROM space)
					// Mac Plus ROM detection via SCSI
					// If ROM is 256K (configROMSize[1]==1), or if A17==0 (first 128K),
					// then this is ROM. Otherwise it might be SCSI space.
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
				
				4'b10?1: begin // $A0_0000 - $AF_FFFF and $B0_0000 - $BF_FFFF (SCC)
					// Note: In Mac II mode, need to avoid conflict with NuBus slot $A and $B
					// But those are at $A000_0000+, not $00A0_0000
					// So in 24-bit space, SCC is safe here
					selectSCC = !_cpuAS;
				end
				
				4'b1100: begin // $C0_0000 - $CF_FFFF (IWM on some models)
					// Note: In Mac II mode, avoid conflict with NuBus slot $C at $C000_0000
					// But we're in 24-bit space ($00Cxxxxx), so this is safe
					if (!configROMSize[1])
						selectIWM = !_cpuAS;
				end
				
				4'b1101: begin // $D0_0000 - $DF_FFFF (IWM)
					// Note: In Mac II mode, avoid conflict with NuBus slot $D at $D000_0000
					// But we're in 24-bit space ($00Dxxxxx), so this is safe
					selectIWM = !_cpuAS;
				end
				
				4'b1110: begin // $E0_0000 - $EF_FFFF (VIA - Mac Plus/SE)
					// Note: In Mac II mode, avoid conflict with NuBus slot $E at $E000_0000
					// But we're in 24-bit space ($00Exxxxx), so this is safe
					if (address[19]) // $E8_0000 - $EF_FFFF
						selectVIA = !_cpuAS;
				end

				4'b1111: begin // $F0_0000 - $FF_FFFF (Mac IIx I/O mirror of $5000_0000)
					// This is the 24-bit mirror of the 32-bit I/O space at $5000_0000
					// VIA1: $F0_0000, VIA2: $F0_2000, SCC: $F0_4000
					// SCSI: $F1_0000, IWM: $F1_6000
					if (address[19:13] == 7'b0000_000)       // $F0_0000 - $F0_1FFF: VIA1
						selectVIA = !_cpuAS;
					else if (address[19:13] == 7'b0000_001)  // $F0_2000 - $F0_3FFF: VIA2
						selectVIA = !_cpuAS;
					else if (address[19:13] == 7'b0000_010)  // $F0_4000 - $F0_5FFF: SCC
						selectSCC = !_cpuAS;
					else if (address[19:14] == 6'b0001_00)   // $F1_0000 - $F1_3FFF: SCSI
						selectSCSI = !_cpuAS;
					else if (address[19:13] == 7'b0001_011)  // $F1_6000 - $F1_7FFF: IWM/SWIM
						selectIWM = !_cpuAS;
					else if (address[19:13] == 7'b0100_000)  // $F4_0000 - $F4_1FFF: VIA1 alt
						selectVIA = !_cpuAS;
				end

				default:
					; // select nothing
			endcase
		end
	end
endmodule