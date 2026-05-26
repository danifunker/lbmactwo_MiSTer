module addrController_top(
	// clocks:
	input clk,
	output clk8,						// 7.8336 MHz (C7M = C15M / 2) — peripheral fclk
	output clk8_en_p,
	output clk8_en_n,
	output clk16_en_p,
	output clk16_en_n,

	// system config:
	input turbo,               // 0 = normal, 1 = faster
	input [1:0] configROMSize,  // 0 = 64K ROM, 1 = 128K ROM, 2 = 256K ROM
	input [1:0] configRAMSize,	// 0 = 1MB, 1 = 2MB, 2 = 4MB, 3 = 8MB RAM
	input [1:0] glueRAMSize,    // Mac II GLUE RAM bank placement from VIA2 PA7:6

	// CPU memory interface (supports 32-bit addressing for 68020/68030):
	input [31:0] cpuAddr,
	input _cpuUDS,
	input _cpuLDS,
	input _cpuRW,	
	input _cpuAS,
	
	// RAM/ROM:
	output [22:0] memoryAddr,			// 23-bit byte address (8MB max RAM)
	output _memoryUDS,
	output _memoryLDS,	
	output _romOE,
	output _ramOE,	
	output _ramWE,	
	output videoBusControl,
	output dioBusControl,
	output cpuBusControl,
	output memoryLatch,
	
	// peripherals:
	output selectSCSI,
	output selectSCC,
	output selectIWM,
	output selectVIA,
	output selectVIA2,
	output selectRAM,
	output selectROM,
	output selectSCSIDMA,
	output selectSEOverlay,
	output selectNuBus,
	output selectASC,

	// video:
	output hsync,
	output vsync,
	output _hblank,
	output _vblank,
	output loadPixels,
	input  vid_alt,
		
	// misc
	input memoryOverlayOn,
	
	// interface to read dsk image from ram
	input [21:0] dskReadAddrInt,
	output dskReadAckInt,
	input [21:0] dskReadAddrExt,
	output dskReadAckExt
);

	assign dioBusControl = extraBusControl;

	// interleaved RAM access for CPU and video
	reg [1:0] busCycle;
	reg [1:0] busPhase;
	reg [1:0] extra_slot_count;

	always @(posedge clk) begin
		busPhase <= busPhase + 1'd1;
		if (busPhase == 2'b11)
			busCycle <= busCycle + 2'd1;
	end
	assign memoryLatch = busPhase == 2'd3;
	assign clk8 = !busPhase[1];
	assign clk8_en_p = busPhase == 2'b11;
	assign clk8_en_n = busPhase == 2'b01;
	assign clk16_en_p = !busPhase[0];
	assign clk16_en_n = busPhase[0];

	reg extra_slot_advance;
	always @(posedge clk)
		if (clk8_en_n) extra_slot_advance <= (busCycle == 2'b11);

	// allocate memory slots in the extra cycle
	always @(posedge clk) begin
		if(clk8_en_p && extra_slot_advance) begin
			extra_slot_count <= extra_slot_count + 2'd1;
		end
	end

	// video controls memory bus during the first clock of the four-clock cycle
	assign videoBusControl = (busCycle == 2'b00);
	// cpu controls memory bus during the second and fourth clock of the four-clock cycle
	assign cpuBusControl = (busCycle == 2'b01) || (busCycle == 2'b11);
	// IWM/audio gets 3rd cycle
	wire extraBusControl = (busCycle == 2'b10);

	// interconnects
	wire [21:0] videoAddr;
	
	// RAM/ROM control signals
	wire videoControlActive = _hblank;

	assign _romOE = ~(cpuBusControl && selectROM && _cpuRW);
	
	assign _ramOE = ~((videoBusControl && videoControlActive) ||
						(cpuBusControl && selectRAM && _cpuRW));
	assign _ramWE = ~(cpuBusControl && selectRAM && !_cpuRW);
	
	assign _memoryUDS = cpuBusControl ? _cpuUDS : 1'b0;
	assign _memoryLDS = cpuBusControl ? _cpuLDS : 1'b0;
	// 23-bit address path so 8MB RAM (cpuAddr[22:0]) is reachable.  The built-in
	// video framebuffer only lives in the low 4MB, so its A22 is forced to 0.
	wire [22:0] addrMux = videoBusControl ? {1'b0, videoAddr} : cpuAddr[22:0];
	wire [22:0] macAddr;
	assign macAddr[15:0] = addrMux[15:0];

	// video always addresses ram
	wire ram_access = (cpuBusControl && selectRAM) || videoBusControl;
	wire rom_access = (cpuBusControl && selectROM);
	wire ram2m_bank_a_mirror = cpuBusControl && selectRAM &&
	                           configRAMSize == 2'b01 &&
	                           (glueRAMSize == 2'b00 || glueRAMSize == 2'b01) &&
	                           cpuAddr[23:20] == 4'h2;

	// ROM address clamping (simulate smaller ROM sizes)
	// RAM address mirroring is controlled by the Mac II GLUE bank placement
	// latch (VIA2 PA7:6).  For the 2MB layout MAME models, only the bank-A
	// mirror at $00200000-$002FFFFF wraps to physical bank A; the base
	// $00000000-$001FFFFF range must remain unique for ROM RAM sizing.
	// Other RAM sizes pass through unmodified — selectRAM gating in addrDecoder
	// handles size limiting (out-of-range accesses BERR like real hardware).
	assign macAddr[16] = rom_access && configROMSize == 2'b00 ? 1'b0 :     // force A16 to 0 for 64K ROM access
									addrMux[16];
	assign macAddr[17] = rom_access && configROMSize == 2'b01 ? 1'b0 :  // force A17 to 0 for 128K ROM access
									rom_access && configROMSize == 2'b00 ? 1'b1 :  // force A17 to 1 for 64K ROM access (64K ROM image is at $20000)
									addrMux[17];
	assign macAddr[18] = rom_access && configROMSize != 2'b11 ? 1'b0 : // force A18 to 0 for 64K/128K/256K ROM access
									addrMux[18];
	assign macAddr[19] = rom_access ? 1'b0 : addrMux[19];
	assign macAddr[20] = rom_access ? 1'b0 : addrMux[20];
	assign macAddr[21] = rom_access ? 1'b0 :
									ram2m_bank_a_mirror ? 1'b0 :
									addrMux[21];
	assign macAddr[22] = rom_access ? 1'b0 : addrMux[22];   // A22 selects upper 4MB of an 8MB SIMM set

			
	// floppy emulation gets extra slots 0 and 1
	assign dskReadAckInt = (extraBusControl == 1'b1) && (extra_slot_count == 0);
	assign dskReadAckExt = (extraBusControl == 1'b1) && (extra_slot_count == 1);

	assign memoryAddr =
		dskReadAckInt ? {1'b0, dskReadAddrInt} + 23'h100000:   // first dsk image at 1MB
		dskReadAckExt ? {1'b0, dskReadAddrExt} + 23'h200000:   // second dsk image at 2MB
		macAddr;

	// address decoding
	addrDecoder ad(
		.configROMSize(configROMSize),
		.configRAMSize(configRAMSize),
		.glueRAMSize(glueRAMSize),
		.address(cpuAddr),
		._cpuAS(_cpuAS),
		.memoryOverlayOn(memoryOverlayOn),
		.selectRAM(selectRAM),
		.selectROM(selectROM),
		.selectSCSI(selectSCSI),
		.selectSCSIDMA(selectSCSIDMA),
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA),
		.selectVIA2(selectVIA2),
		.selectSEOverlay(selectSEOverlay),
		.selectNuBus(selectNuBus),
		.selectASC(selectASC));

	// video
	videoTimer vt(
		.clk(clk),
		.clk_en(clk8_en_p),
		.busCycle(busCycle), 
		.vid_alt(vid_alt),
		.videoAddr(videoAddr), 
		.hsync(hsync), 
		.vsync(vsync), 
		._hblank(_hblank),
		._vblank(_vblank), 
		.loadPixels(loadPixels));
		
endmodule
