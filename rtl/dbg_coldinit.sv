// dbg_coldinit — cold-load integrity instrument (always-on, ~60 registers).
//
// Motivation (2026-06-12): cold core loads intermittently leave the machine
// in a state that crashes every boot until the NEXT cold load re-rolls it,
// while warm resets preserve whatever state they inherit (good or bad).
// Nothing in the init path ever VERIFIES its own work. This module makes
// every cold load self-reporting:
//
//   1. ROM download checksum: 32-bit byte-sum of the boot0.rom ioctl stream
//      (byte-order-insensitive, so the HPS 16-bit word byte-order quirk
//      cannot false-alarm) + word count, compared against constants computed
//      from the canonical patched ROM (md5 3ac98d2a..., scripts/
//      patch_rom_nomemtest.sh output). The LIVE sum is also exposed, so even
//      if the ROM file changes, sum variance across boots = transport
//      corruption caught red-handed.
//   2. Init choreography timeline: ms timestamps of rom_loaded, clear_done,
//      pram_ready and the first img_mounted per slot — direct evidence of
//      the cold-boot ordering instead of inference.
//   3. PLL-unlock counter: pll_locked dropouts (power-sag tell; also the
//      SDRAM controller re-init trigger, since sdram.init = !pll_locked).
//      Best-effort: a hard unlock may stall clk_sys itself, but brownouts
//      that recover still leave a count.
//
// Read over JTAG ISSP (scripts/read_coldinit.tcl) — the JTAG path goes
// through the USB-Blaster, NOT the HPS, so reading costs the Linux side
// nothing (see memory feedback-shared-mister-protocol).
//
// Deliberately NOT gated behind DBG_PROBES: this is a production integrity
// instrument, small by design (no wide CPU/bus capture like dbg_min).

module dbg_coldinit (
	input         clk,            // clk_sys
	input         pll_locked,
	input         ioctl_download, // dio_download
	input  [7:0]  ioctl_index,    // dio_index
	input         ioctl_wr,
	input  [15:0] ioctl_data,
	input  [2:0]  img_mounted,    // SC0 / SC1 / PRAM-slot mount strobes
	input         rom_loaded,
	input         clear_done,
	input         pram_ready
);

	// Expected constants for the canonical no-memtest Mac II ROM
	// (boot0.rom md5 3ac98d2a..., 262144 bytes). Regenerate with:
	//   sh scripts/patch_rom_nomemtest.sh MacII.rom boot0.rom
	//   python: sum(open('boot0.rom','rb').read()) & 0xFFFFFFFF
	localparam [31:0] ROM_EXPECT_SUM   = 32'h013F_FEF5;
	localparam [17:0] ROM_EXPECT_WORDS = 18'd131072;

	// ---- millisecond timebase (clk_sys = 31.3344 MHz) --------------------
	reg [14:0] presc = 0;
	reg        ms_tick = 0;
	reg [15:0] ms_cnt = 0;          // saturates at 65535 ms (~65 s)
	always @(posedge clk) begin
		if (presc == 15'd31333) begin presc <= 0; ms_tick <= 1'b1; end
		else                    begin presc <= presc + 1'b1; ms_tick <= 1'b0; end
		if (ms_tick && ms_cnt != 16'hFFFF) ms_cnt <= ms_cnt + 1'b1;
	end

	// ---- ROM download stream checksum (ioctl index 0 only) ---------------
	reg  [31:0] dl_sum   = 0;
	reg  [17:0] dl_words = 0;
	reg         dl_act_d = 0;
	wire        rom_dl   = ioctl_download && (ioctl_index == 8'd0);
	always @(posedge clk) begin
		dl_act_d <= rom_dl;
		if (rom_dl && !dl_act_d) begin            // download start: restart sum
			dl_sum   <= 0;
			dl_words <= 0;
		end else if (rom_dl && ioctl_wr) begin
			dl_sum   <= dl_sum + ioctl_data[7:0] + ioctl_data[15:8];
			dl_words <= dl_words + 1'b1;
		end
	end
	wire rom_sum_ok = (dl_sum == ROM_EXPECT_SUM) && (dl_words == ROM_EXPECT_WORDS);

	// ---- PLL unlock counter ----------------------------------------------
	reg       pll_d = 0;
	reg [3:0] unlock_cnt = 0;
	always @(posedge clk) begin
		pll_d <= pll_locked;
		if (pll_d && !pll_locked && unlock_cnt != 4'hF)
			unlock_cnt <= unlock_cnt + 1'b1;
	end

	// ---- mount events + first-mount timestamps ---------------------------
	reg [2:0]  mnt_d = 0;
	reg [1:0]  mnt_cnt0 = 0, mnt_cnt1 = 0, mnt_cnt2 = 0;   // saturating
	reg [15:0] t_mnt0 = 16'hFFFF;                          // FFFF = never
	always @(posedge clk) begin
		mnt_d <= img_mounted;
		if (img_mounted[0] && !mnt_d[0]) begin
			if (mnt_cnt0 != 2'd3) mnt_cnt0 <= mnt_cnt0 + 1'b1;
			if (t_mnt0 == 16'hFFFF) t_mnt0 <= ms_cnt;
		end
		if (img_mounted[1] && !mnt_d[1] && mnt_cnt1 != 2'd3) mnt_cnt1 <= mnt_cnt1 + 1'b1;
		if (img_mounted[2] && !mnt_d[2] && mnt_cnt2 != 2'd3) mnt_cnt2 <= mnt_cnt2 + 1'b1;
	end

	// ---- init milestone timestamps ----------------------------------------
	reg        rom_d = 0, clr_d = 0, prdy_d = 0;
	reg [15:0] t_rom = 16'hFFFF, t_clear = 16'hFFFF, t_pram = 16'hFFFF;
	always @(posedge clk) begin
		rom_d  <= rom_loaded;
		clr_d  <= clear_done;
		prdy_d <= pram_ready;
		if (rom_loaded && !rom_d  && t_rom   == 16'hFFFF) t_rom   <= ms_cnt;
		if (clear_done && !clr_d  && t_clear == 16'hFFFF) t_clear <= ms_cnt;
		if (pram_ready && !prdy_d && t_pram  == 16'hFFFF) t_pram  <= ms_cnt;
	end

	// ---- JTAG In-System Probes ---------------------------------------------
	// PCS0: live ROM download byte-sum
	// PCS1: {rom_sum_ok,1'b0,dl_words[17:0],unlock_cnt[3:0],mnt_cnt0,mnt_cnt1,
	//        mnt_cnt2,clear_done,pram_ready}
	// PCS2: {t_rom, t_clear}
	// PCS3: {t_pram, t_mnt0}
`ifndef SIMULATION
	altsource_probe #(
		.instance_id ("PCS0"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) p_pcs0 (.probe(dl_sum), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("PCS1"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) p_pcs1 (.probe({rom_sum_ok, 1'b0, dl_words, unlock_cnt,
	                  mnt_cnt0, mnt_cnt1, mnt_cnt2, clear_done, pram_ready}),
	          .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("PCS2"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) p_pcs2 (.probe({t_rom, t_clear}), .source(), .source_clk(clk), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("PCS3"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) p_pcs3 (.probe({t_pram, t_mnt0}), .source(), .source_clk(clk), .source_ena(1'b1));
`endif

endmodule
