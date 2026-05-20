// JTAG-readable debug probes via altsource_probe.
//
// Each probe is read from CLI with:
//   quartus_stp_tcl -t scripts/issp_read.tcl <probe_index>
// Or via SystemConsole / In-System Sources & Probes Editor.
//
// We expose key signals for diagnosing the Mac vs Video SDRAM contention:
//   probe 0: {cpuAddr[23:0], _cpuAS, _cpuRW, _cpuUDS, _cpuLDS, _cpuDTACK, video_en}
//   probe 1: {memoryDataOut[15:0], arb_mac_dout[15:0]}  (Mac data bus snapshot)
//   probe 2: {arb_mac_addr[23:0], arb_mac_we, arb_mac_oe, grant_video, video_clean, mac_stall, 3'd0}
//   probe 3: {arb_vram_addr[24:0], arb_vram_rd, arb_vram_wr, arb_vram_ready, vram_state[2:0]}
//   probe 4: {sdram_out[15:0], mac_idle_cnt[3:0], cpuAddr[31:24], 4'd0}
//            (SDRAM data + arbiter state + high byte of PC)

module debug_probes (
    input wire        clk,

    input wire [31:0] cpuAddr,
    input wire        cpuAS_n,
    input wire        cpuRW,
    input wire        cpuUDS_n,
    input wire        cpuLDS_n,
    input wire        cpuDTACK_n,
    input wire        video_en,

    input wire [15:0] memoryDataOut,
    input wire [15:0] arb_mac_dout,

    input wire [24:0] arb_mac_addr,
    input wire        arb_mac_we,
    input wire        arb_mac_oe,
    input wire        grant_video,
    input wire        video_clean,
    input wire        mac_stall,

    input wire [24:0] arb_vram_addr,
    input wire        arb_vram_rd,
    input wire        arb_vram_wr,
    input wire        arb_vram_ready,
    input wire [2:0]  vram_state,

    input wire [15:0] sdram_out,
    input wire [3:0]  mac_idle_cnt,

    // Video card register snapshots
    input wire [2:0]  vid_mode_raw,
    input wire [16:0] vid_base_offset,
    input wire [9:0]  vid_stride,
    input wire [23:0] vid_clut0,
    input wire [23:0] vid_clut1,

    // JTAG-controlled test pattern output (drives nubus_video_highres
    // dbg_test_pattern input).  0 = normal, 1-4 = patterns.
    output wire [2:0] vid_test_pattern,

    // JTAG-driven override of clut[0]/[1] for the normal scanout.
    // Lets us force a known palette to see Mac's framebuffer regardless
    // of what Mac actually wrote into the real CLUT.
    output wire        vid_clut_override,
    output wire [23:0] vid_clut0_force,
    output wire [23:0] vid_clut1_force,

    // RAMDAC write-history readback: drive an index out, read the word back.
    output wire [4:0]  vid_ramdac_hist_idx,
    input  wire [31:0] vid_ramdac_hist
);

    // Snapshot the wide buses on every clock so JTAG reads (which can land
    // any time) get a clock-synchronous, coherent sample rather than
    // glitchy combinational values.
    reg [31:0] cpuAddr_r;
    reg [15:0] memoryDataOut_r, arb_mac_dout_r, sdram_out_r;
    reg [24:0] arb_mac_addr_r, arb_vram_addr_r;
    reg        cpuAS_n_r, cpuRW_r, cpuUDS_n_r, cpuLDS_n_r, cpuDTACK_n_r;
    reg        video_en_r;
    reg        arb_mac_we_r, arb_mac_oe_r, grant_video_r, video_clean_r;
    reg        mac_stall_r;
    reg        arb_vram_rd_r, arb_vram_wr_r, arb_vram_ready_r;
    reg [2:0]  vram_state_r;
    reg [3:0]  mac_idle_cnt_r;

    always @(posedge clk) begin
        cpuAddr_r        <= cpuAddr;
        cpuAS_n_r        <= cpuAS_n;
        cpuRW_r          <= cpuRW;
        cpuUDS_n_r       <= cpuUDS_n;
        cpuLDS_n_r       <= cpuLDS_n;
        cpuDTACK_n_r     <= cpuDTACK_n;
        video_en_r       <= video_en;
        memoryDataOut_r  <= memoryDataOut;
        arb_mac_dout_r   <= arb_mac_dout;
        arb_mac_addr_r   <= arb_mac_addr;
        arb_mac_we_r     <= arb_mac_we;
        arb_mac_oe_r     <= arb_mac_oe;
        grant_video_r    <= grant_video;
        video_clean_r    <= video_clean;
        mac_stall_r      <= mac_stall;
        arb_vram_addr_r  <= arb_vram_addr;
        arb_vram_rd_r    <= arb_vram_rd;
        arb_vram_wr_r    <= arb_vram_wr;
        arb_vram_ready_r <= arb_vram_ready;
        vram_state_r     <= vram_state;
        sdram_out_r      <= sdram_out;
        mac_idle_cnt_r   <= mac_idle_cnt;
    end

    // ---- ISSP instances ----
    // probe_width chosen <=32; pack signals into 32-bit groups.

    // PROBE 0: CPU control + low addr
    altsource_probe #(
        .instance_id ("CP0_"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_probe0 (
        .probe ({cpuAddr_r[23:0], cpuAS_n_r, cpuRW_r, cpuUDS_n_r, cpuLDS_n_r,
                 cpuDTACK_n_r, video_en_r, 2'b00}),
        .source(),
        .source_clk(clk),
        .source_ena(1'b1)
    );

    // PROBE 1: data buses
    altsource_probe #(
        .instance_id ("DATA"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_probe1 (
        .probe ({memoryDataOut_r, arb_mac_dout_r}),
        .source(),
        .source_clk(clk),
        .source_ena(1'b1)
    );

    // PROBE 2: arbiter mac side
    altsource_probe #(
        .instance_id ("MAC_"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_probe2 (
        .probe ({arb_mac_addr_r[23:0], arb_mac_we_r, arb_mac_oe_r,
                 grant_video_r, video_clean_r, mac_stall_r, 3'b000}),
        .source(),
        .source_clk(clk),
        .source_ena(1'b1)
    );

    // PROBE 3: arbiter video side
    altsource_probe #(
        .instance_id ("VID_"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_probe3 (
        .probe ({arb_vram_addr_r[23:0], arb_vram_rd_r, arb_vram_wr_r,
                 arb_vram_ready_r, vram_state_r, 2'b00}),
        .source(),
        .source_clk(clk),
        .source_ena(1'b1)
    );

    // PROBE 4: sdram dout + mac idle counter + cpuAddr[31:24]
    altsource_probe #(
        .instance_id ("SDRA"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_probe4 (
        .probe ({sdram_out_r, mac_idle_cnt_r, cpuAddr_r[31:24], 4'd0}),
        .source(),
        .source_clk(clk),
        .source_ena(1'b1)
    );

    // ------------------------------------------------------------------------
    // Video registers + JTAG test-pattern source
    // ------------------------------------------------------------------------
    reg [2:0]  vid_mode_raw_r;
    reg [16:0] vid_base_offset_r;
    reg [9:0]  vid_stride_r;
    reg [23:0] vid_clut0_r;
    reg [23:0] vid_clut1_r;
    always @(posedge clk) begin
        vid_mode_raw_r    <= vid_mode_raw;
        vid_base_offset_r <= vid_base_offset;
        vid_stride_r      <= vid_stride;
        vid_clut0_r       <= vid_clut0;
        vid_clut1_r       <= vid_clut1;
    end

    // PROBE 5: video card register state
    //  [31:29] = mode_raw (3 bits)
    //  [28:12] = vram_base_offset (17 bits)
    //  [11:2]  = vram_stride (10 bits)
    //  [1:0]   = 0
    altsource_probe #(
        .instance_id ("VREG"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_probe5 (
        .probe ({vid_mode_raw_r, vid_base_offset_r, vid_stride_r, 2'd0}),
        .source(),
        .source_clk(clk),
        .source_ena(1'b1)
    );

    // PROBE 6: CLUT entry 0 and 1 (the two indexes used in 1bpp mode)
    //  [31:24] = clut[0].R, [23:16] = clut[0].G, [15:8] = clut[0].B, [7:0] = clut[1].R
    altsource_probe #(
        .instance_id ("CLU0"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_probe6 (
        .probe ({vid_clut0_r, vid_clut1_r[23:16]}),
        .source(),
        .source_clk(clk),
        .source_ena(1'b1)
    );

    // PROBE 7: CLUT[1].G, CLUT[1].B (the rest of clut[1]) + spare
    altsource_probe #(
        .instance_id ("CLU1"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_probe7 (
        .probe ({vid_clut1_r[15:0], 16'd0}),
        .source(),
        .source_clk(clk),
        .source_ena(1'b1)
    );

    // SOURCE probe -- JTAG-writable register driving the video test
    // pattern selector.  Pad to 8 bits, take low 3 as the pattern code.
    wire [7:0] tp_src_raw;
    altsource_probe #(
        .instance_id ("VTPN"),
        .probe_width (1),
        .source_width(8),
        .source_initial_value("0"),
        .sld_auto_instance_index ("YES")
    ) cp_test_src (
        .probe (1'b0),
        .source(tp_src_raw),
        .source_clk(clk),
        .source_ena(1'b1)
    );
    assign vid_test_pattern = tp_src_raw[2:0];

    // SOURCE probe -- 32-bit CLUT-override word, layout:
    //   bit 31      = enable override (any non-zero of high byte = on)
    //   bits 23..0  = clut[0] RGB (R in [23:16], G in [15:8], B in [7:0])
    // CLUT[1] uses a separate source probe below.
    wire [31:0] clut0_src;
    altsource_probe #(
        .instance_id ("CLUE"),
        .probe_width (1),
        .source_width(32),
        .source_initial_value("0"),
        .sld_auto_instance_index ("YES")
    ) cp_clut0_src (
        .probe (1'b0),
        .source(clut0_src),
        .source_clk(clk),
        .source_ena(1'b1)
    );
    assign vid_clut_override = clut0_src[31];
    assign vid_clut0_force = clut0_src[23:0];

    // SOURCE probe for clut[1] override RGB
    wire [31:0] clut1_src;
    altsource_probe #(
        .instance_id ("CLUF"),
        .probe_width (1),
        .source_width(32),
        .source_initial_value("0"),
        .sld_auto_instance_index ("YES")
    ) cp_clut1_src (
        .probe (1'b0),
        .source(clut1_src),
        .source_clk(clk),
        .source_ena(1'b1)
    );
    assign vid_clut1_force = clut1_src[23:0];

    // SOURCE probe -- selects which RAMDAC-history entry to read (low 5 bits).
    wire [7:0] hist_idx_src;
    altsource_probe #(
        .instance_id ("RHIX"),
        .probe_width (1),
        .source_width(8),
        .source_initial_value("0"),
        .sld_auto_instance_index ("YES")
    ) cp_hist_idx (
        .probe (1'b0),
        .source(hist_idx_src),
        .source_clk(clk),
        .source_ena(1'b1)
    );
    assign vid_ramdac_hist_idx = hist_idx_src[4:0];

    // PROBE -- reads back the selected RAMDAC-history word
    // {wptr[4:0], 2'b0, entry[24:0]}.
    reg [31:0] hist_rd_r;
    always @(posedge clk) hist_rd_r <= vid_ramdac_hist;
    altsource_probe #(
        .instance_id ("RHDT"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_hist_rd (
        .probe (hist_rd_r),
        .source(),
        .source_clk(clk),
        .source_ena(1'b1)
    );

endmodule
