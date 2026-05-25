// Minimal JTAG debug probes for diagnosing the main-hwfixes early-boot hang.
//
// Read with: quartus_stp_tcl -t scripts/cpu_state.tcl
//
// PADR : cpuAddr[31:0] snapshot (where the CPU is accessing / stuck).
// PSTA : packed bus/decoder state (see bit layout below).
// PACT : free-running counter of CPU bus cycles (rising edge of _cpuAS).
//        If PACT stops advancing, the CPU is frozen; the PADR/PSTA snapshot
//        then shows the offending access (e.g. an FPU coprocessor access at
//        cpuFC=7 with DSACK never asserting).
module dbg_min (
    input wire        clk,

    input wire [31:0] cpuAddr,
    input wire [2:0]  cpuFC,
    input wire        cpuAS_n,
    input wire        cpuRW,
    input wire        cpuDTACK_n,
    input wire        cpuUDS_n,
    input wire        cpuLDS_n,

    input wire        selectFPU,
    input wire        selectRAM,
    input wire        selectROM,
    input wire        selectNuBus,
    input wire        fpu_dsack0_n,
    input wire        fpu_dsack1_n,
    input wire        mac_dout_valid,

    // Interrupt path (diagnose the frozen Ticks/60Hz boot hang).
    input wire [2:0]  cpuIPL_n,   // _cpuIPL: 111=none 110=VIA1 101=VIA2 011=SCC

    // Bus-error watchdog (catch the unmapped/non-responding access that may
    // be dropping the Mac into the ROM serial monitor).
    input wire        berr,

    // Video card state
    input wire        video_en,
    input wire [15:0] vram_wr_cnt,      // CPU VRAM writes (Mac drawing)
    input wire [15:0] vram_fetch_cnt,   // completed video scanout fetches

    // SCSI state (diagnose the bus-status poll hang)
    input wire        selectSCSI,
    input wire [15:0] scsi_rd_data,     // dataControllerDataOut (SCSI reg value)
    input wire [1:0]  img_mounted,      // HPS disk-mount pulses
    input wire [1:0]  sd_rd,            // SCSI disk read requests
    input wire [1:0]  sd_wr,            // SCSI disk write requests
    input wire [1:0]  sd_ack,           // HPS disk-op completion
    input wire [15:0] scsi_dbg,         // NCR5380 selection/arbitration state
    input wire [15:0] scsi_dbg2,        // NCR5380 phase + io handshake
    input wire [15:0] scsi_dbg3,        // per-target REQ/ACK observations
    input wire [15:0] scsi_dbg4,        // bus-reset count + completion flags
    input wire [15:0] scsi_dbg5,        // per-target command-type bitmap

    // Raw disk data the HPS delivers (to catch byte-order/corruption)
    input wire [15:0] sd_buff_dout,
    input wire [7:0]  sd_buff_addr,
    input wire        sd_buff_wr,

    // HPS ROM-download stream (confirm the NuBus video declaration ROM,
    // boot1.rom @ index 1, actually reaches the card on hardware).
    input wire        ioctl_wr,
    input wire [7:0]  ioctl_idx,

    // ADB/VIA1-SR state (diagnose the mouse-fix boot spin).
    // [31:29] acr_shift_mode [28] shift_dir [27] sr_active [26] sr_out_done
    // [25] sr_out_ack [24] sr_out_pending [23:16] sr_shadow
    // [15] adb_int [14] adb_dout_strobe [13] adb_din_strobe [12] listen
    // [11] cmd_processed [10] cmd_valid [9:8] adb_st [7:0] cmd_byte
    input wire [31:0] dbg_adb,

    // Shift-in completion diagnosis: [17:1]=via1_shift_timer [0]=sr_ext_complete
    input wire [17:0] dbg_adb2,

    // ---- Audio-regression diagnosis (MDC 8*24 video swap) -----------------
    input wire        selectASC,        // CPU accessing the Apple Sound Chip
    input wire        asc_irq_n,        // ASC FIFO refill-request IRQ (active-low)
    input wire signed [15:0] asc_audio_l, // ASC left output sample
    input wire [15:0] card_irq_cnt,     // video card VBL IRQ assertion count
    input wire [15:0] card_ack_cnt,     // video card bus-ACK count
    input wire        card_vbl_en       // video card VBL IRQ enabled?
);

    // Coherent snapshots on clk.
    reg [31:0] cpuAddr_r;
    reg [31:0] sta_r;
    always @(posedge clk) begin
        cpuAddr_r <= cpuAddr;
        sta_r <= {
            13'd0,
            mac_dout_valid,                 // [18]
            fpu_dsack1_n, fpu_dsack0_n,     // [17:16]
            selectNuBus, selectROM,         // [15:14]
            selectRAM, selectFPU,           // [13:12]
            cpuLDS_n, cpuUDS_n,             // [11:10]
            cpuDTACK_n, cpuRW, cpuAS_n,     // [9:7]
            cpuFC,                          // [6:4]
            4'd0
        };
    end

    // Free-running bus-cycle counter: increments on each _cpuAS assertion
    // (falling edge). A frozen value => CPU is hung.
    reg cpuAS_n_d;
    reg [31:0] as_cycles;
    always @(posedge clk) begin
        cpuAS_n_d <= cpuAS_n;
        if (cpuAS_n_d && !cpuAS_n)   // falling edge of _cpuAS = new bus cycle
            as_cycles <= as_cycles + 32'd1;
    end

    altsource_probe #(
        .instance_id ("PADR"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_padr (.probe(cpuAddr_r), .source(), .source_clk(clk), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("PSTA"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psta (.probe(sta_r), .source(), .source_clk(clk), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("PACT"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pact (.probe(as_cycles), .source(), .source_clk(clk), .source_ena(1'b1));

    // Video card state: {video_en, vram_wr_cnt[15:0], vram_fetch_cnt[15:0]}.
    // If vram_wr_cnt advances, the Mac is drawing the framebuffer; if
    // vram_fetch_cnt advances, scanout is reading VRAM. video_en shows
    // whether the Mac has enabled the card.
    reg [31:0] vid_r;
    always @(posedge clk)
        vid_r <= {15'd0, video_en, vram_wr_cnt};
    reg [31:0] vfetch_r;
    always @(posedge clk)
        vfetch_r <= {16'd0, vram_fetch_cnt};

    altsource_probe #(
        .instance_id ("PVID"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pvid (.probe(vid_r), .source(), .source_clk(clk), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("PVFC"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pvfc (.probe(vfetch_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // SCSI diagnosis:
    //   scsi_last_rd  : value the CPU last read from the SCSI controller
    //   scsi_last_reg : NCR5380 register offset of that read (cpuAddr[6:0])
    //   img_seen      : sticky OR of img_mounted (did the HPS mount a disk?)
    //   sdrd/sdwr_seen: sticky OR of sd_rd/sd_wr (did SCSI ever touch the disk?)
    reg [15:0] scsi_last_rd;
    reg [6:0]  scsi_last_reg;
    reg [1:0]  img_seen;
    reg [1:0]  sdrd_seen;
    reg [1:0]  sdwr_seen;
    always @(posedge clk) begin
        if (selectSCSI && cpuRW) begin   // a CPU read of a SCSI register
            scsi_last_rd  <= scsi_rd_data;
            scsi_last_reg <= cpuAddr[6:0];
        end
        img_seen  <= img_seen  | img_mounted;
        sdrd_seen <= sdrd_seen | sd_rd;
        sdwr_seen <= sdwr_seen | sd_wr;
    end
    reg [31:0] scsi_r;
    always @(posedge clk)
        scsi_r <= {sdwr_seen, sdrd_seen, img_seen, 1'b0, scsi_last_reg, scsi_last_rd};

    altsource_probe #(
        .instance_id ("PSCS"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pscs (.probe(scsi_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // NCR5380 selection diagnosis.
    //   sel_ids     : sticky OR of every ID byte driven while SEL asserted
    //                 (shows which SCSI IDs the Mac actually selected)
    //   scsi_dbg_hi : snapshot of the full state captured the moment the Mac
    //                 selects a HIGH id (bit6=ID6 or bit5=ID5 -- where the
    //                 disks live), so target_mounted/target_bsy are visible
    //                 for the disks' own selection.
    // scsi_dbg bit map: [14]=SEL [13]=BSY [12:11]=target_bsy [10:9]=mounted
    //                   [8]=ICR.ADB [7:0]=data_bus(ID bits)
    reg [15:0] scsi_dbg_hi;
    reg [7:0]  sel_ids;
    always @(posedge clk) begin
        if (scsi_dbg[14]) begin                   // SEL asserted
            sel_ids <= sel_ids | scsi_dbg[7:0];
            if (scsi_dbg[6] || scsi_dbg[5])        // selecting ID6 or ID5
                scsi_dbg_hi <= scsi_dbg;
        end
    end
    reg [31:0] scsi2_r;
    always @(posedge clk)
        scsi2_r <= {8'd0, sel_ids, scsi_dbg_hi};

    altsource_probe #(
        .instance_id ("PSC2"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psc2 (.probe(scsi2_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // Post-selection progress: track the MAX phase each target reaches and
    // whether the HPS ever completes a disk op (sd_ack).  scsi_dbg2 layout:
    //   [13:11] target_phase[1]  [10:8] target_phase[0]
    //   [5:4] io_rd  [3:2] io_wr  [1:0] io_ack
    // phases: 0 IDLE,1 CMD_IN,2 DATA_OUT,3 DATA_IN,4 STATUS_OUT,5 MSG_OUT
    reg [2:0] max_ph0, max_ph1;
    reg [1:0] io_ack_seen;
    reg [1:0] sd_ack_seen;
    wire [2:0] ph0 = scsi_dbg2[10:8];
    wire [2:0] ph1 = scsi_dbg2[13:11];
    always @(posedge clk) begin
        if (ph0 > max_ph0) max_ph0 <= ph0;
        if (ph1 > max_ph1) max_ph1 <= ph1;
        io_ack_seen <= io_ack_seen | scsi_dbg2[1:0];
        sd_ack_seen <= sd_ack_seen | sd_ack;
    end
    reg [31:0] scsi3_r;
    always @(posedge clk)
        scsi3_r <= {8'd0, ph1, ph0, sd_ack_seen, io_ack_seen, 1'b0, max_ph1, 1'b0, max_ph0, scsi_dbg2[5:0]};

    altsource_probe #(
        .instance_id ("PSC3"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psc3 (.probe(scsi3_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // Per-target REQ/ACK observations (sticky, from scsi.v dbg_hs).
    reg [31:0] scsi4_r;
    always @(posedge clk)
        scsi4_r <= {16'd0, scsi_dbg3};

    // PSC4 disabled to free fit budget for audio probes (PVBL/PASC/PAUD).
    // altsource_probe #(
    //     .instance_id ("PSC4"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psc4 (.probe(scsi4_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // Bus-reset count + completion flags (survive scsi_rst).
    reg [31:0] scsi5_r;
    always @(posedge clk)
        scsi5_r <= {16'd0, scsi_dbg4};

    // PSC5 disabled to free fit budget for audio probes (PVBL/PASC/PAUD).
    // altsource_probe #(
    //     .instance_id ("PSC5"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psc5 (.probe(scsi5_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // LIVE snapshot of the NCR5380 selection state (what the Mac is doing in
    // the stuck loop right now): {out_en,SEL,BSY,target_bsy,mounted,ADB,data}.
    reg [31:0] scsi7_r;
    always @(posedge clk)
        scsi7_r <= {16'd0, scsi_dbg};

    altsource_probe #(
        .instance_id ("PSC7"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psc7 (.probe(scsi7_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // Per-target command-type bitmap.
    reg [31:0] scsi6_r;
    always @(posedge clk)
        scsi6_r <= {16'd0, scsi_dbg5};

    // PSC6 disabled to free fit budget for audio probes (PVBL/PASC/PAUD).
    // altsource_probe #(
    //     .instance_id ("PSC6"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psc6 (.probe(scsi6_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // Disk-flow: first word of the most recent sector + write-strobe count, to
    // tell whether disk reads are STILL happening during the stuck scan or
    // frozen (data already wired; cheap to re-add).
    reg [15:0] disk_word0;
    reg [15:0] disk_wr_cnt;
    always @(posedge clk) begin
        if (sd_buff_wr) begin
            disk_wr_cnt <= disk_wr_cnt + 16'd1;
            if (sd_buff_addr == 8'd0) disk_word0 <= sd_buff_dout;
        end
    end
    reg [31:0] disk_r;
    always @(posedge clk)
        disk_r <= {disk_wr_cnt, disk_word0};

    altsource_probe #(
        .instance_id ("PSC8"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psc8 (.probe(disk_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ---- ROM-download verification (PSCG) ---------------------------------
    // Count HPS ioctl writes per ROM index, to confirm the NuBus video
    // declaration ROM (boot1.rom @ index 1) actually loads on hardware:
    //   idx0_cnt = system ROM bytes (boot0.rom) - should be large (~256K)
    //   idx1_cnt = video declaration ROM bytes (boot1.rom) - expect ~8192
    // If idx1_cnt is 0 the card never gets its declaration ROM (Slot Manager
    // can't init it -> no video).  ~4096 would indicate the wrong (Toby) ROM.
    reg [31:0] idx0_cnt, idx1_cnt;
    initial begin idx0_cnt = 32'd0; idx1_cnt = 32'd0; end
    always @(posedge clk) begin
        if (ioctl_wr) begin
            if (ioctl_idx == 8'd0) idx0_cnt <= idx0_cnt + 32'd1;
            if (ioctl_idx == 8'd1) idx1_cnt <= idx1_cnt + 32'd1;
        end
    end
    reg [31:0] idx1_r, idx0_r;
    always @(posedge clk) begin
        idx1_r <= idx1_cnt;
        idx0_r <= idx0_cnt;
    end

    altsource_probe #(
        .instance_id ("PSCG"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pscg (.probe(idx1_r), .source(), .source_clk(clk), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("PSCH"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psch (.probe(idx0_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ---- Bus-reset trigger snapshot (PSCF) --------------------------------
    // Latch the SCSI target phase/io-handshake state at the moment the Mac
    // issues each bus reset, to see whether resets fire MID-READ (a target in
    // DATA_OUT => transfer problem, supports the stale-io_rd theory) or BETWEEN
    // transactions (targets IDLE => higher-level reject).  rst_count lives in
    // scsi_dbg4[15:8]; scsi_dbg2 carries the phases:
    //   [13:11]=phase t1(ID5) [10:8]=phase t0(ID6) [5:4]=io_rd [3:2]=io_wr [1:0]=io_ack
    wire [7:0] dmin_rstc = scsi_dbg4[15:8];
    reg  [7:0] dmin_rstc_d;
    reg  [7:0] dmin_rst_seen;
    reg [15:0] dbg2_at_rst;
    initial begin dmin_rstc_d = 8'd0; dmin_rst_seen = 8'd0; dbg2_at_rst = 16'd0; end
    always @(posedge clk) begin
        dmin_rstc_d <= dmin_rstc;
        if (dmin_rstc != dmin_rstc_d) begin   // bus-reset count changed
            dbg2_at_rst   <= scsi_dbg2;
            dmin_rst_seen <= dmin_rst_seen + 8'd1;
        end
    end
    reg [31:0] rstsnap_r;
    always @(posedge clk)
        rstsnap_r <= {dmin_rst_seen, 8'd0, dbg2_at_rst};

    // PSCF disabled to free fit budget for audio probes (PVBL/PASC/PAUD).
    // altsource_probe #(
    //     .instance_id ("PSCF"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pscf (.probe(rstsnap_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== Audio-regression probes (PVBL / PASC / PAUD) ====================
    // Diagnose the distorted startup chime after the MDC 8*24 video swap.
    //
    // PVBL: is the video card touching the CPU during the chime window?
    //   {card_vbl_en, card_irq_cnt[14:0], card_ack_cnt[15:0]}
    //   - card_irq_cnt climbing  => card raising VBL IRQs (cycle theft)
    //   - card_vbl_en=1 early     => driver enabled VBL during/near the chime
    //   - card_ack_cnt            => bus cycles the card answered
    reg [31:0] pvbl_r;
    always @(posedge clk)
        pvbl_r <= {card_vbl_en, card_irq_cnt[14:0], card_ack_cnt};

    altsource_probe #(
        .instance_id ("PVBL"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pvbl (.probe(pvbl_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PASC: ASC FIFO refill cadence — refill REQUESTS vs CPU REFILLS.
    //   {asc_irq_cnt[15:0], asc_wr_cnt[15:0]}
    //   asc_irq_cnt : # times ASC asserted its refill IRQ (asc_irq_n falling)
    //   asc_wr_cnt  : # CPU writes to the ASC ($50F14xxx)
    //   If asc_irq_cnt outruns asc_wr_cnt the FIFO is underrunning -> distortion.
    reg asc_irq_d;
    reg [15:0] asc_irq_cnt;
    reg [15:0] asc_wr_cnt;
    always @(posedge clk) begin
        asc_irq_d <= asc_irq_n;
        if (asc_irq_d && !asc_irq_n)                 // ASC refill request
            asc_irq_cnt <= asc_irq_cnt + 16'd1;
        if (cpuAS_n_d && !cpuAS_n && selectASC && !cpuRW)  // CPU write to ASC
            asc_wr_cnt <= asc_wr_cnt + 16'd1;
    end
    reg [31:0] pasc_r;
    always @(posedge clk)
        pasc_r <= {asc_irq_cnt, asc_wr_cnt};

    altsource_probe #(
        .instance_id ("PASC"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pasc (.probe(pasc_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PAUD: ASC output sample range (distortion signature).  Track sticky
    // signed min/max of the left channel.  Clean audio sweeps a bounded range;
    // a stuck/garbled stream shows full-scale clipping (min=-32768,max=32767)
    // or a collapsed (near-zero) range.  {audio_max[15:0], audio_min[15:0]}.
    reg signed [15:0] audio_min;
    reg signed [15:0] audio_max;
    initial begin audio_min = 16'sh7FFF; audio_max = 16'sh8000; end
    always @(posedge clk) begin
        if (asc_audio_l < audio_min) audio_min <= asc_audio_l;
        if (asc_audio_l > audio_max) audio_max <= asc_audio_l;
    end
    reg [31:0] paud_r;
    always @(posedge clk)
        paud_r <= {audio_max, audio_min};

    altsource_probe #(
        .instance_id ("PAUD"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_paud (.probe(paud_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== ADB / VIA1-SR diagnostic probes (PADB / PAD2 / PAD3) ============
    // DISABLED to free fit budget now that the ADB shift-in hang is fixed.
    // These were used to diagnose the VIA1 SR shift-in completion bug (the
    // read-initiated shift-in that never armed the timer). To re-enable for
    // future ADB/VIA debugging: delete the surrounding /* */ block comment.
    // The dbg_adb / dbg_adb2 inputs (and their plumbing through
    // dataController_top -> LBMacTwo -> here) are left wired but unused; they
    // synthesize away while disabled. NOTE: re-enabling adds 3 probes and the
    // design is at ~19 probes / 82% ALMs — it may then fail to fit; trim an
    // out-of-scope SCSI probe (PSC4/PSC5/PSCF) if so.
    /*
    // PADB: live coherent snapshot of the ADB FSM + VIA1 shift-register
    // handshake. Sample it several times: if the CPU is spinning while ADB is
    // wedged, the state (adb_st / cmd_valid / sr_out_pending) will be static.
    reg [31:0] adb_r;
    always @(posedge clk) adb_r <= dbg_adb;

    altsource_probe #(
        .instance_id ("PADB"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_padb (.probe(adb_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PAD2: edge counters for the two ADB strobes + the VIA1 sr_out_pending
    // assertions. Tells whether byte delivery is happening repeatedly, once,
    // or never during the spin.  {pend_cnt[7:0], dout_cnt[11:0], din_cnt[11:0]}.
    reg din_d, dout_d, pend_d;
    reg [11:0] din_cnt, dout_cnt;
    reg [7:0]  pend_cnt;
    initial begin din_cnt=0; dout_cnt=0; pend_cnt=0; din_d=0; dout_d=0; pend_d=0; end
    always @(posedge clk) begin
        din_d  <= dbg_adb[13];
        dout_d <= dbg_adb[14];
        pend_d <= dbg_adb[24];
        if (dbg_adb[13] && !din_d)  din_cnt  <= din_cnt  + 12'd1;
        if (dbg_adb[14] && !dout_d) dout_cnt <= dout_cnt + 12'd1;
        if (dbg_adb[24] && !pend_d) pend_cnt <= pend_cnt + 8'd1;
    end
    reg [31:0] adb2_r;
    always @(posedge clk) adb2_r <= {pend_cnt, dout_cnt, din_cnt};

    altsource_probe #(
        .instance_id ("PAD2"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pad2 (.probe(adb2_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PAD3: VIA1 shift-in completion diagnosis.
    //   {complete_cnt[14:0], via1_shift_timer[16:0]}
    // If via1_shift_timer is a static nonzero value across samples it is NOT
    // counting down; if it's 0 it was never armed; if complete_cnt never
    // increments, sr_ext_complete never fires (shift_active never clears).
    wire [16:0] shift_timer_now = dbg_adb2[17:1];
    wire        sr_complete_now = dbg_adb2[0];
    reg  sr_complete_d;
    reg [14:0] complete_cnt;
    initial begin complete_cnt = 15'd0; sr_complete_d = 1'b0; end
    always @(posedge clk) begin
        sr_complete_d <= sr_complete_now;
        if (sr_complete_now && !sr_complete_d) complete_cnt <= complete_cnt + 15'd1;
    end
    reg [31:0] adb3_r;
    always @(posedge clk) adb3_r <= {complete_cnt, shift_timer_now};

    altsource_probe #(
        .instance_id ("PAD3"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pad3 (.probe(adb3_r), .source(), .source_clk(clk), .source_ena(1'b1));
    */

endmodule
