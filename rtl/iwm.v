/* IWM 

   Mapped to $DFE1FF - $DFFFFF
	
	The 16 IWM one-bit registers are {8'hDF, 8'b111xxxx1, 8'hFF}:
		0	$0		ca0L		CA0 off (0)
		1	$200	ca0H		CA0 on (1)
		2	$400	ca1L		CA1 off (0)
		3	$600	ca1H		CA1 on (1)
		4	$800	ca2L		CA2 off (0)
		5	$A00	ca2H		CA2 on (1)
		6	$C00	ph3L		LSTRB off (low)
		7	$E00	ph3H		LSTRB on (high)
		8	$1000	mtrOff	ENABLE disk enable off
		9	$1200	mtrOn		ENABLE disk enable on
		10	$1400	intDrive	SELECT select internal drive
		11	$1600	extDrive	SELECT select external drive
		12	$1800	q6L		Q6 off
		13	$1A00	q6H		Q6 on
		14	$1C00	q7L		Q7 off, read register
		15	$1E00	q7H		Q7 on, write register
	
	Notes from IWM manual:
	Serial data is shifted in/out MSB first, with a bit transferred every 2 microseconds.
	When writing data, a 1 is written as a transition on writeData at a bit cell boundary time, and a 0 is written as no transition.
	When reading data, a falling transition within a bit cell window is considered to be a 1, and no falling transition is considered a 0.
	When reading data, the read data register will latch the shift register when a 1 is shifted into the MSB.
	The read data register will be cleared 14 fclk periods (about 2 microseconds) after a valid data read takes place-- a valid data read 
	   being defined as both /DEV being low and D7 (the MSB) outputting a one from the read data register for at least one fclk period.
*/		

// Clocking (Step 2 of clocking-confirmation work):
//   The Mac II clocks the IWM at C15M = 15.6672 MHz (MAME: IWM(config, m_fdc, C15M)).
//   Internally the IWM divides by 2 to produce the ~7.8336 MHz fclk that times
//   the GCR bit cells (~2 µs per bit, 128 fclk per byte) and the read-latch
//   clear delay (14 fclk ≈ 1.8 µs). The parent wires cep/cen here at the
//   C15M rate; we derive ce_p_div2 / ce_n_div2 below and pass those to the
//   floppy module and to every internal register that needs fclk timing.
module iwm
(
	input clk,
	input cep,       // C15M-rate enable (15.6672 MHz)
	input cen,       // C15M-rate enable (15.6672 MHz)

	input _reset,
	input selectIWM,
	input _cpuRW,
	input _cpuUDS,
	input _cpuLDS,
	input [15:0] dataIn,
	input [3:0] cpuAddrRegHi,
	input SEL, // from VIA
	input driveSel, // internal drive select, 0 - upper, 1 - lower
	output [15:0] dataOut,
	input [1:0] insertDisk,
	output [1:0] diskEject,
	input [1:0] diskSides,
	
	output [1:0] diskMotor,
	output [1:0] diskAct,
	
	// interface to fetch data for internal drive
	output [21:0] dskReadAddrInt,
	input dskReadAckInt,
	output [21:0] dskReadAddrExt,
	input dskReadAckExt,
	input [7:0] dskReadData
);

	// Internal /2 phase divider — produces the ~7.8336 MHz fclk timing
	// expected by the floppy bit-cell engine, IWM read-latch clear timer, and
	// read-arm delay. Toggles once per cep pulse so ce_p_div2 / ce_n_div2 fire
	// every other cep / cen tick.
	reg ce_phase;
	always @(posedge clk or negedge _reset) begin
		if (!_reset)      ce_phase <= 1'b0;
		else if (cep)     ce_phase <= ~ce_phase;
	end
	wire ce_p_div2 = cep & ce_phase;
	wire ce_n_div2 = cen & ce_phase;

	// Mac II uses even addresses (UDS), Mac Plus/SE uses odd (LDS)
	wire iwmAccess = !_cpuLDS | !_cpuUDS;
	wire [7:0] dataInByte = !_cpuLDS ? dataIn[7:0] : dataIn[15:8];
	reg [7:0] dataOutLo;
	assign dataOut = { dataOutLo, dataOutLo }; // replicate to both byte lanes
	
	// IWM state
	reg ca0, ca1, ca2, lstrb, selectExternalDrive, q6, q7;
	reg ca0Next, ca1Next, ca2Next, lstrbNext, selectExternalDriveNext, q6Next, q7Next;
	wire advanceDriveHead; // prevents overrun when debugging, does not exit on a real Mac!
	reg [7:0] writeData;
	reg [7:0] readDataLatch;
	reg [11:0] readDataArmDelay;
	wire _iwmBusy, _writeUnderrun;
	assign _iwmBusy = 1'b1; // for writes, a value of 1 here indicates the IWM write buffer is empty
	assign _writeUnderrun = 1'b1;

	// floppy disk drives
	// The IWM has one active/motor latch and one drive-select latch. MAME's
	// iwm_device switches the active drive when SELECT changes while active,
	// rather than keeping separate enables latched per drive.
	reg diskEnable;
	reg diskEnableNext;
	wire diskEnableInt = diskEnable & ~selectExternalDrive;
	wire diskEnableExt = diskEnable & selectExternalDrive;
	wire diskEnableIntNext = diskEnableNext & ~selectExternalDriveNext;
	wire diskEnableExtNext = diskEnableNext & selectExternalDriveNext;
	wire newByteReadyInt;
	wire [7:0] readDataInt /*verilator public_flat_rd*/;
	wire senseInt;
	wire newByteReadyExt;
	wire [7:0] readDataExt /*verilator public_flat_rd*/;
	wire senseExt;
	
	floppy floppyInt
	(
		.clk(clk),
		.cep(ce_p_div2),
		.cen(ce_n_div2),

		._reset(_reset),
		.ca0(ca0),
		.ca1(ca1),
		.ca2(ca2),
		.SEL(SEL),
		.lstrb(lstrb),
		._enable(~(diskEnableInt & driveSel)),
		.writeData(writeData),
		.readData(readDataInt),
		.sense(senseInt),
		.advanceDriveHead(advanceDriveHead),
		.newByteReady(newByteReadyInt),
		.drivePresent(1'b1),
		.insertDisk(insertDisk[0]),
		.diskSides(diskSides[0]),
		.diskEject(diskEject[0]),	

		.motor(diskMotor[0]),
		.act(diskAct[0]),

		.dskReadAddr(dskReadAddrInt),
		.dskReadAck(dskReadAckInt),
		.dskReadData(dskReadData)
	);

	floppy floppyExt
	(
		.clk(clk),
		.cep(ce_p_div2),
		.cen(ce_n_div2),

		._reset(_reset),
		.ca0(ca0),
		.ca1(ca1),
		.ca2(ca2),
		.SEL(SEL),
		.lstrb(lstrb),
		._enable(~diskEnableExt),
		.writeData(writeData),
		.readData(readDataExt),
		.sense(senseExt),
		.advanceDriveHead(advanceDriveHead),
		.newByteReady(newByteReadyExt),
		// Match MAME's add_35_nc external connector: no external drive is
		// installed unless one is explicitly configured.
		.drivePresent(1'b0),
		.insertDisk(insertDisk[1]),
		.diskSides(diskSides[1]),
		.diskEject(diskEject[1]),
		
		.motor(diskMotor[1]),
		.act(diskAct[1]),

		.dskReadAddr(dskReadAddrExt),
		.dskReadAck(dskReadAckExt),
		.dskReadData(dskReadData)
	);
	
	wire [7:0] readData = selectExternalDrive ? readDataExt : readDataInt;
	wire newByteReady = selectExternalDrive ? newByteReadyExt : newByteReadyInt;
	wire anyDiskEnable = diskEnable;
	wire selectedDiskEnableNext = diskEnableNext;
	wire anyDiskEnableNext = diskEnableNext;
	wire readDataArmed = (readDataArmDelay == 12'd0);
	
	reg [4:0] iwmMode;
	/* IWM mode register: S C M H L
 	 S	Clock speed:
			0 = 7 MHz
			1 = 8 MHz
		Should always be 1 for Macintosh.
	 C	Bit cell time:
			0 = 4 usec/bit (for 5.25 drives)
			1 = 2 usec/bit (for 3.5 drives) (Macintosh mode)
	 M	Motor-off timer:
			0 = leave drive on for 1 sec after program turns
			    it off
			1 = no delay (Macintosh mode)
		Should be 0 for 5.25 and 1 for 3.5.
	 H	Handshake protocol:
			0 = synchronous (software must supply proper
			    timing for writing data)
			1 = asynchronous (IWM supplies timing) (Macintosh Mode)
		Should be 0 for 5.25 and 1 for 3.5.
	 L	Latch mode:
			0 = read-data stays valid for about 7 usec
			1 = read-data stays valid for full byte time (Macintosh mode)
		Should be 0 for 5.25 and 1 for 3.5.
	*/

	// any read/write access to IWM bit registers will change their values
	always @(*) begin
		ca0Next <= ca0;
		ca1Next <= ca1;
		ca2Next <= ca2;
		lstrbNext <= lstrb;
		diskEnableNext <= diskEnable;
		selectExternalDriveNext <= selectExternalDrive;
		q6Next <= q6;
		q7Next <= q7;

		if (selectIWM == 1'b1 && iwmAccess) begin
			case (cpuAddrRegHi[3:1])
				3'h0: // ca0
					ca0Next <= cpuAddrRegHi[0];
				3'h1: // ca1
					ca1Next <= cpuAddrRegHi[0];
				3'h2: // ca2
					ca2Next <= cpuAddrRegHi[0];
				3'h3: // lstrb
					lstrbNext <= cpuAddrRegHi[0];
				3'h4: // disk enable
					diskEnableNext <= cpuAddrRegHi[0];
				3'h5: // external drive
					selectExternalDriveNext <= cpuAddrRegHi[0];
				3'h6: // Q6 
					q6Next <= cpuAddrRegHi[0];
				3'h7: // Q7 
					q7Next <= cpuAddrRegHi[0];
			endcase
		end
	end

	// update IWM bit registers
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			ca0 <= 0;
			ca1 <= 0;
			ca2 <= 0;
			lstrb <= 0;
			diskEnable <= 0;
			selectExternalDrive <= 0;
			q6 <= 0;
			q7 <= 0;
		end
		else begin
			ca0 <= ca0Next;
			ca1 <= ca1Next;
			ca2 <= ca2Next;
			lstrb <= lstrbNext;
			diskEnable <= diskEnableNext;
			selectExternalDrive <= selectExternalDriveNext;
			q6 <= q6Next;
			q7 <= q7Next;
		end
	end
	
	// read IWM state
	always @(*) begin
		dataOutLo = 8'hEF;
		
		// reading any IWM address returns state as selected by Q7 and Q6
		case ({q7Next,q6Next})
			2'b00: // data-in register (from disk drive) - MSB is 1 when data is valid
				dataOutLo <= anyDiskEnableNext ? (anyDiskEnable ? readDataLatch : 8'h00) : 8'hFF;
			2'b01: // IWM status register - read only
				dataOutLo <= { (selectExternalDriveNext ? senseExt : senseInt), 1'b0, selectedDiskEnableNext, iwmMode };
			2'b10: // handshake - read only
				dataOutLo <= { _iwmBusy, _writeUnderrun, 6'b000000 };
			2'b11: // IWM mode register when not enabled (write-only), or (write?) data register when enabled
				dataOutLo <= 0;
		endcase
	end

	// write IWM state
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin		
			iwmMode <= 0;
			writeData <= 0;
		end
		else if(ce_n_div2) begin
			if (_cpuRW == 0 && selectIWM == 1'b1 && iwmAccess) begin
				// writing to any IWM address modifies state as selected by Q7 and Q6
				case ({q7Next,q6Next})
					2'b11: begin
						if (diskEnable)
							writeData <= dataInByte;
						else
							iwmMode <= dataInByte[4:0];
					end
				endcase
			end
		end
	end

	// Manage incoming bytes from the disk drive
	wire iwmRead = (_cpuRW == 1'b1 && selectIWM == 1'b1 && iwmAccess);
	reg [3:0] readLatchClearTimer;
	reg diskEnableReadD;
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			readDataLatch <= 0;
			readLatchClearTimer <= 0;
			readDataArmDelay <= 0;
			diskEnableReadD <= 0;
		end
		else if(ce_n_div2) begin
			diskEnableReadD <= anyDiskEnable;

			if (readDataArmDelay != 0) begin
				readDataArmDelay <= readDataArmDelay - 1'b1;
			end

			// a countdown timer governs how long after a data latch read before the latch is cleared
			if (readLatchClearTimer != 0) begin
				readLatchClearTimer <= readLatchClearTimer - 1'b1;
			end

			// MAME clears the IWM data register when the controller enters active
			// read mode. Avoid exposing stale idle-drive data on the motor-on access.
			if ((!anyDiskEnable && anyDiskEnableNext) || (!diskEnableReadD && anyDiskEnable)) begin
				readDataLatch <= 0;
				readLatchClearTimer <= 0;
				readDataArmDelay <= 12'h400;
			end

			// the conclusion of a valid CPU read from the IWM will start the timer to clear the latch
			else if (iwmRead && readDataLatch[7]) begin
				readLatchClearTimer <= 4'hD; // clear latch 14 clocks after the conclusion of a valid read
			end

			// when the drive indicates that a new byte is ready, latch it
			// NOTE: the real IWM must self-synchronize with the incoming data to determine when to latch it
			if (anyDiskEnable && readDataArmed && newByteReady) begin
				readDataLatch <= readData;
			end
			else if (readLatchClearTimer == 1'b1) begin
				readDataLatch <= 0;
			end
		end
	end
	assign advanceDriveHead = (readLatchClearTimer == 1'b1) ||
	                          (anyDiskEnable && !readDataArmed && newByteReady); // prevents overrun when debugging, does not exist on a real Mac!
endmodule
