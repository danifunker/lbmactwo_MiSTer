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

    // SR byte-sequence diagnosis (last 4 bytes each, newest in [7:0]):
    input wire [31:0] dbg_adb3,   // bytes CPU READ from VIA1 SR
    input wire [31:0] dbg_adb4,   // bytes LOADED into VIA1 SR (shift-in)

    // ---- Audio-regression diagnosis (MDC 8*24 video swap) -----------------
    input wire        selectASC,        // CPU accessing the Apple Sound Chip
    input wire        asc_irq_n,        // ASC FIFO refill-request IRQ (active-low)
    input wire signed [15:0] asc_audio_l, // ASC left output sample
    input wire [15:0] card_irq_cnt,     // video card VBL IRQ assertion count
    input wire [15:0] card_ack_cnt,     // video card bus-ACK count
    input wire        card_vbl_en,      // video card VBL IRQ enabled?

    // Mouse event diagnostic (PMSE)
    input wire [24:0] ps2_mouse,        // raw HPS mouse vector (bit 24 toggles per packet)
    input wire        mouse_has_event,  // from adb.sv: latched mouse event pending

    // Floppy / IWM byte-stream diagnostics (PFLP / PIWM)
    input wire [15:0] flp_byte_cnt,     // newByteReady rising edges (sat)
    input wire [15:0] flp_miss_cnt,     // 128-cep slot misses (sat) — RAW marker
    input wire [7:0]  flp_disk_data,    // live diskImageData (0 = no fresh byte)
    input wire [15:0] iwm_ack_cnt,      // dskReadAckInt edges (sat) — SDRAM grants
    input wire [7:0]  iwm_latch,        // live readDataLatch ([7] = "byte avail")
    input wire [6:0]  iwm_arm_high,     // top 7 bits of readDataArmDelay[11:5]

    // Floppy track / step diagnostics (PFLT)
    input wire [6:0]  flp_track,        // live driveTrack
    input wire        flp_side,         // live driveSide
    input wire [15:0] flp_step_cnt,     // STEP register write edges (wrap16)

    // IORB ioResult write probe (PIR1): cpu data bus on writes to $3B4.
    // tells us whether the driver ever COMPLETES the I/O (writes ioResult)
    // or whether the OS is truly stuck on a single never-finishing call.
    input wire [15:0] cpu_dout,         // cpuDataOut[15:0] (CPU write data)

    // PIR3 / ioRefNum probe: the muxed read-back data the CPU receives on
    // its bus cycle (cpu_data_in in LBMacTwo.sv). Latched when mac_dout_valid
    // is asserted at the matching address. Allows PIR3 to record the actual
    // refnum read at IORB+0x18.
    input wire [15:0] cpu_din,          // cpu_data_in[15:0] (CPU read data)

    // PIRQ probe: unencoded per-source IRQ signals (active-low).  Edge-count
    // each to compare assertion rates between Phase 1 and Phase 2.  In build
    // #8's PIPL data only SCC (lvl 4) was seen in Phase 1's ipl_seen bitmap;
    // P2 shows lvl1+lvl2 but NOT lvl4 -- suggests SCC IRQs stop in P2.
    input wire        via1_irq_n,        // VIA1 (Tick/60Hz, ADB, ASC FIFO, RTC)
    input wire        via2_irq_n,        // VIA2 (SCSI, NuBus, slot IRQs)
    input wire        scc_irq_n,         // SCC (serial / AppleTalk)

    // PSCC probe: CPU access to SCC. PIRQ build #9 showed scc_irq_cnt=0
    // throughout boot, so SCC IRQ never asserts. PSCC tests whether the OS
    // even talks to SCC -- if not, the boot ROM didn't initialize it.
    input wire        selectSCC,         // selectSCC from addrDecoder

    // PIOH probe (build #11): per-peripheral CPU access counters. PSCC
    // showed SCC isn't the wedge. PIOH identifies which peripheral the
    // post-Phase-1 busy-loop IS hammering.
    input wire        selectVIA,         // VIA1 select (Tick, ADB, ASC FIFO IRQ, RTC)
    input wire        selectVIA2,        // VIA2 select (SCSI, NuBus IRQs)
    input wire        selectIWM,         // IWM/SWIM select (floppy regs)

    // PFST probe: packed FPU CIR FSM state (see mc68881_top.vhd port comment).
    // Build #15's FRESTORE fix did not unblock boot; this probe is to see
    // what protocol step the FSM is actually wedged on.
    input wire [31:0] fpu_dbg_cir_state
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

    // PVID disabled to free JTAG-routing headroom for the cold-boot RAM-clear logic.
    // altsource_probe #(
    //     .instance_id ("PVID"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pvid (.probe(vid_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PVFC disabled to free JTAG-routing headroom for the cold-boot RAM-clear logic.
    // altsource_probe #(
    //     .instance_id ("PVFC"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pvfc (.probe(vfetch_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PSCS disabled to free fit budget for PIRQ (per-source IRQ counters).
    // The "last SCSI read" diagnosis isn't load-bearing for the post-Phase-1
    // busy-loop investigation.
    // altsource_probe #(
    //     .instance_id ("PSCS"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pscs (.probe(scsi_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PSC2 disabled (along with PSC3) to free fit budget for PIR3 (ioRefNum).
    // The SCSI selection-state diagnosis isn't load-bearing for the
    // Welcome-hang investigation.
    // altsource_probe #(
    //     .instance_id ("PSC2"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psc2 (.probe(scsi2_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PSC3 disabled to free fit budget for PIR2 (dynamic IORB ioResult watcher).
    // The SCSI phase-progress counters are not load-bearing for the
    // Welcome-hang investigation; re-enable by uncommenting if SCSI debugging
    // is needed again.
    // altsource_probe #(
    //     .instance_id ("PSC3"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psc3 (.probe(scsi3_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PSC7 disabled to free fit budget for slot-E write monitor (PSLT).
    // altsource_probe #(
    //     .instance_id ("PSC7"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psc7 (.probe(scsi7_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PSC8 disabled to free fit budget for PSCC.
    // The sd_buff disk-word read counter isn't load-bearing now that we
    // know Phase 1 disk I/O completes normally and the hang is post-disk.
    // altsource_probe #(
    //     .instance_id ("PSC8"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psc8 (.probe(disk_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PSCG/PSCH disabled to free fit budget for PIPL (IRQ delivery probe).
    // We know boot0+boot1 ROMs load correctly on hardware; the ROM-download
    // verification probes aren't load-bearing for the post-Welcome busy-loop
    // investigation. Re-enable by uncommenting if ROM-load debugging is
    // needed again.
    // altsource_probe #(
    //     .instance_id ("PSCG"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pscg (.probe(idx1_r), .source(), .source_clk(clk), .source_ena(1'b1));
    //
    // altsource_probe #(
    //     .instance_id ("PSCH"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psch (.probe(idx0_r), .source(), .source_clk(clk), .source_ena(1'b1));

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
    // PADB: live coherent snapshot of the ADB FSM + VIA1 shift-register
    // handshake. Sample it several times: if the CPU is spinning while ADB is
    // wedged, the state (adb_st / cmd_valid / sr_out_pending) will be static.
    reg [31:0] adb_r;
    always @(posedge clk) adb_r <= dbg_adb;

    // PADB disabled to free fit budget for PMEM (passive memory snoop at
    // the busy-loop PC). ADB diagnostics aren't load-bearing for the
    // post-Phase-1 hang -- mouse/keyboard already work.
    // altsource_probe #(
    //     .instance_id ("PADB"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_padb (.probe(adb_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PAD2 disabled to free fit budget for PMEM.
    // altsource_probe #(
    //     .instance_id ("PAD2"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pad2 (.probe(adb2_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PAD3 disabled to free fit budget for PMEM.
    // altsource_probe #(
    //     .instance_id ("PAD3"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pad3 (.probe(adb3_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PMSE: mouse event diagnostic — counts ps2_mouse[24] toggles (HPS
    // delivering events?) and mouse_has_event rising edges (adb.sv latching?).
    reg ps2m24_d, mhe_d;
    reg [15:0] ps2m24_cnt;   // HPS mouse packet count
    reg [15:0] mhe_cnt;      // adb.sv mouse_has_event assertion count
    initial begin ps2m24_cnt = 0; mhe_cnt = 0; ps2m24_d = 0; mhe_d = 0; end
    always @(posedge clk) begin
        ps2m24_d <= ps2_mouse[24];
        mhe_d    <= mouse_has_event;
        if (ps2_mouse[24] != ps2m24_d) ps2m24_cnt <= ps2m24_cnt + 16'd1;
        if (mouse_has_event && !mhe_d) mhe_cnt    <= mhe_cnt    + 16'd1;
    end
    reg [31:0] mse_r;
    always @(posedge clk) mse_r <= {ps2m24_cnt, mhe_cnt};

    // PMSE disabled to free ALM/JTAG budget for PFLP/PIWM (floppy-stream
    // probes). Mouse path is healthy; re-enable if needed.
    // altsource_probe #(
    //     .instance_id ("PMSE"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pmse (.probe(mse_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== Floppy byte-stream diagnostic (PFLP) =============================
    // Diagnose the post-Welcome boot freeze on Boot712.dsk. Two 16-bit
    // saturating counters from the internal-drive floppy module:
    //   [31:16] flp_byte_cnt — newByteReady rising-edge count: bytes
    //                          successfully fed to the IWM. Should climb
    //                          steadily while Mac OS reads the floppy.
    //   [15:0]  flp_miss_cnt — slot misses: moments when the byte-slot
    //                          timer wraps to 0 with the drive selected
    //                          for read but the delivery condition fails
    //                          (typically because diskImageData was not
    //                          refilled in time). A nonzero, growing miss
    //                          count while byte_cnt is stalled fingerprints
    //                          the SDRAM-arbiter starvation hypothesis.
    reg [31:0] pflp_r;
    always @(posedge clk)
        pflp_r <= {flp_byte_cnt, flp_miss_cnt};

    altsource_probe #(
        .instance_id ("PFLP"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pflp (.probe(pflp_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== IWM latch / SDRAM-grant diagnostic (PIWM) ========================
    // Complements PFLP from the IWM side. Layout:
    //   [31:16] iwm_ack_cnt    — dskReadAckInt rising edges: SDRAM grants
    //                            for the internal drive. Should match the
    //                            byte-delivery rate (~60 kB/s while reading).
    //   [15:8]  iwm_latch      — live readDataLatch (Mac reads bit 7 as
    //                            "fresh byte available" indicator).
    //   [7]     flp_disk_data!=0 — live "fresh byte staged" indicator from
    //                              floppy.v (diskImageData != 0).
    //   [6:0]   iwm_arm_high   — top 7 bits of readDataArmDelay[11:5];
    //                            non-zero means the post-motor-on arm
    //                            delay is still counting down.
    reg [31:0] piwm_r;
    always @(posedge clk)
        piwm_r <= {iwm_ack_cnt, iwm_latch, (flp_disk_data != 8'h00), iwm_arm_high};

    altsource_probe #(
        .instance_id ("PIWM"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_piwm (.probe(piwm_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== IORB capture (PIOA) =============================================
    // The Welcome hang reaches IOWait at 0x40006C36-3A, which polls
    // word @ (a0 + 0x10) — the ioResult field of an IORB. Capture the
    // FIRST data-read address that follows an instruction fetch at the
    // poll, AND a count of how many times we passed through the loop.
    //
    // Strategy: track whether the previous AS cycle's instruction fetch
    // was at 0x40006C36 (mid-loop). If so, the next AS cycle is the
    // data read at (a0 + 0x10). Capture that address.
    //
    //   [31:0] last data address read right after PC was at 0x40006C36
    //          (= a0 + 0x10; the IORB is at this minus 0x10).
    reg prev_was_iowait_fetch;
    reg [31:0] iowait_data_addr;
    initial begin
        prev_was_iowait_fetch = 1'b0;
        iowait_data_addr      = 32'h0;
    end
    // PIOC: count IOWait poll iterations (every time PC = 0x40006C36).
    // If high & growing during hang, IOWait is actively spinning.
    reg [15:0] iowait_iter_cnt;
    initial iowait_iter_cnt = 16'd0;

    always @(posedge clk) begin
        // The IOWait body is `move.w $10(a0),d0 ; bgt.b $-4`. The 68020
        // prefetcher reorders the bus cycles, so the IF at 0x40006C36 is
        // NOT immediately followed by the DF at (a0+0x10) — the prefetcher
        // may do extra IFs (e.g. the IF at 0x40006C38 for the BGT word)
        // BEFORE the execute unit issues the DF. Solution: arm a "looking
        // for DF" flag on IF at C36, and capture the FIRST subsequent bus
        // cycle whose address is OUTSIDE the ROM region (i.e. in RAM /
        // IO space). a0+0x10 is in RAM (the IORB lives in RAM).
        if (cpuAS_n_d && !cpuAS_n) begin
            if (cpuAddr == 32'h4000_6C36) begin
                prev_was_iowait_fetch <= 1'b1;
                iowait_iter_cnt      <= iowait_iter_cnt + 16'd1;
            end else if (prev_was_iowait_fetch && cpuAddr[31:28] != 4'h4) begin
                // First non-ROM cycle after the C36 IF -> this is the DF
                // at (a0+0x10). RAM is 0x00000000-0x00FFFFFF for 8MB
                // (low aliases) and I/O is 0x50F00000 region. Either
                // way, NOT 0x4xxxxxxx. Good enough.
                iowait_data_addr      <= cpuAddr;
                prev_was_iowait_fetch <= 1'b0;
            end
        end
    end

    // PIOA disabled for build #27 to free routing budget for PFPD (FPU
    // detection probe). The Welcome-hang IOWait investigation is closed
    // (bug #1 RESOLVED); PIOA/PIOC aren't load-bearing for bug #6 FPU
    // detection work.
    // altsource_probe #(
    //     .instance_id ("PIOA"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pioa (.probe(iowait_data_addr), .source(), .source_clk(clk), .source_ena(1'b1));

    reg [31:0] pioc_r;
    always @(posedge clk) pioc_r <= {16'd0, iowait_iter_cnt};
    // PIOC disabled for build #27 (same rationale as PIOA above).
    // altsource_probe #(
    //     .instance_id ("PIOC"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pioc (.probe(pioc_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PIR1: writes to $0000_03B4 (= IORB.ioResult at Mac low-mem "Params").
    //   [31:16] last 16-bit value the CPU wrote to $3B4
    //   [15:0]  wrap16 count of writes to $3B4
    // If count grows -> driver IS completing I/Os (the OS issues many of
    // them and IOWait briefly exits each time). If count stays 0 -> the
    // driver NEVER calls IODone; one single I/O is wedged.
    reg [15:0] ior_last;
    reg [15:0] ior_wr_cnt;
    initial begin ior_last = 16'd0; ior_wr_cnt = 16'd0; end
    always @(posedge clk) begin
        // Catch the write at the falling edge of AS (start of bus cycle)
        // with the right address and RW=0. cpuAddr[1]=0 for the word write.
        if (cpuAS_n_d && !cpuAS_n && !cpuRW &&
            cpuAddr == 32'h0000_03B4) begin
            ior_last   <= cpu_dout;
            ior_wr_cnt <= ior_wr_cnt + 16'd1;
        end
    end
    reg [31:0] pir1_r;
    always @(posedge clk) pir1_r <= {ior_last, ior_wr_cnt};

    // PIR1 disabled for build #14 to free fit budget for PFRR (FPU Response CIR
    // confirm). Build #13 found the Welcome hang is an FPU FRESTORE protocol
    // stall, not an IOWait spin — $3B4 has been frozen at 449 writes for many
    // builds and isn't load-bearing now that PIR2 watches the dynamic IORB.
    // altsource_probe #(
    //     .instance_id ("PIR1"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pir1 (.probe(pir1_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PIR2: writes to whatever address PIOA most recently captured.
    // PIOA's iowait_data_addr tracks (a0+0x10) at IOWait -- i.e. the ioResult
    // field of whichever IORB the OS is currently polling. As the OS
    // transitions between IORBs (e.g. fixed Params $3A4 -> dynamic $21FF6),
    // the trigger address follows automatically. So PIR1 watches the fixed
    // Params ioResult ($3B4) and PIR2 watches the CURRENTLY-polled IORB's
    // ioResult, whatever it is. Same layout as PIR1:
    //   [31:16] last 16-bit value the CPU wrote to that address
    //   [15:0]  wrap16 count of writes to that address
    //
    // Decision tree at the Phase-2 hang:
    //   PIR2.cnt grows during a 1-min observation
    //     => the dynamic-IORB driver IS completing; hang is deeper than
    //        IOWait spin (interrupt? VIA timer? sw-loop delay?).
    //   PIR2.cnt == 0 after a 1-min observation
    //     => the driver NEVER calls IODone; one single I/O is wedged.
    //        Identify which driver via ioRefNum at IORB+0x18 (PIOA-0x10+0x18
    //        = PIOA+0x08), then look up the refnum (-33 .Sony, -36 .Sound,
    //        -38 .SCSI, etc.).
    //
    // Guard with (iowait_data_addr != 0) so we don't catch the cold-RAM
    // clear's writes to $0 before PIOA has captured anything real.
    reg [15:0] ior2_last;
    reg [15:0] ior2_wr_cnt;
    initial begin ior2_last = 16'd0; ior2_wr_cnt = 16'd0; end
    always @(posedge clk) begin
        if (cpuAS_n_d && !cpuAS_n && !cpuRW &&
            (iowait_data_addr != 32'h0) &&
            cpuAddr == iowait_data_addr) begin
            ior2_last   <= cpu_dout;
            ior2_wr_cnt <= ior2_wr_cnt + 16'd1;
        end
    end
    reg [31:0] pir2_r;
    always @(posedge clk) pir2_r <= {ior2_last, ior2_wr_cnt};

    altsource_probe #(
        .instance_id ("PIR2"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pir2 (.probe(pir2_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PIR3: CPU READS at (iowait_data_addr + 0x08) = (IORB + 0x18) = ioRefNum.
    // The Mac IO Manager looks up the driver via IORB.ioRefNum at dispatch
    // time, NOT during IOWait spin. So this probe fires whenever the OS
    // touches that field of the CURRENTLY-tracked IORB; the latched 16-bit
    // value is the driver refnum.
    //
    //   [31:16] last 16-bit value the CPU READ at (iowait_data_addr + 0x08)
    //   [15:0]  wrap16 count of reads at that address
    //
    // Mac driver refnums (16-bit signed):
    //   -33 (0xFFDF) .Sony     -34 (0xFFDE) .Print     -35 (0xFFDD) .Sound (early)
    //   -36 (0xFFDC) .Sound    -38 (0xFFDA) .SCSI      -50 (0xFFCE) AppleTalk async
    //   -51 (0xFFCD) AppleTalk sync   -67 (0xFFBD) .XPP
    //
    // Decision flow once Phase 2 is reached (PIR2.cnt frozen):
    //   PIR3.cnt > 0 + last_value = refnum  -> we KNOW which driver owns the
    //                                          wedged IORB. Probe THAT driver.
    //   PIR3.cnt = 0                        -> OS hasn't re-fetched the field;
    //                                          dispatch happened before
    //                                          iowait_data_addr captured this
    //                                          IORB. Next move: snapshot the
    //                                          last cpuAddr in [iorb..iorb+0x40)
    //                                          range to find ANY read into the
    //                                          IORB header.
    //
    // Same guard as PIR2: require iowait_data_addr != 0 so cold-RAM-clear
    // reads at $00000008 don't get captured as fake refnums.
    // Trigger: latch when (a) the bus cycle's address matches IORB+0x18,
    // (b) it's a READ, and (c) the read data has actually been muxed onto
    // the CPU's input bus (mac_dout_valid). We catch the address on the
    // falling-edge sample but the data on the SAME cycle as mac_dout_valid
    // — they will hold together for the duration of the cycle.
    reg [15:0] ior3_last;
    reg [15:0] ior3_rd_cnt;
    reg        ior3_addr_match;   // set on the falling AS edge, cleared at the data-valid cycle
    initial begin ior3_last = 16'd0; ior3_rd_cnt = 16'd0; ior3_addr_match = 1'b0; end
    wire ior3_trigger = cpuAS_n_d && !cpuAS_n && cpuRW &&
                        (iowait_data_addr != 32'h0) &&
                        cpuAddr == (iowait_data_addr + 32'h8);
    always @(posedge clk) begin
        if (ior3_trigger) ior3_addr_match <= 1'b1;
        // mac_dout_valid pulses when the read data is on cpu_data_in.
        if (ior3_addr_match && mac_dout_valid) begin
            ior3_last       <= cpu_din;
            ior3_rd_cnt     <= ior3_rd_cnt + 16'd1;
            ior3_addr_match <= 1'b0;
        end
        // If AS goes high again before mac_dout_valid (e.g. a different
        // bus cycle for some reason), drop the pending match so we don't
        // latch unrelated data.
        if (ior3_addr_match && !cpuAS_n_d && cpuAS_n) begin
            ior3_addr_match <= 1'b0;
        end
    end
    reg [31:0] pir3_r;
    always @(posedge clk) pir3_r <= {ior3_last, ior3_rd_cnt};

    // PIR3 disabled for build #14 to free fit budget for PFRW (FPU Restore-CIR
    // write confirm). Build #13 reframed $22000-$2200F as FPU CIR space, not
    // RAM IORB; the "ioRefNum" reading was meaningless data residue and not
    // load-bearing for the FPU-FRESTORE-hang investigation.
    // altsource_probe #(
    //     .instance_id ("PIR3"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pir3 (.probe(pir3_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== IRQ-delivery probe (PIPL) ========================================
    // Diagnose the post-Phase-1 busy-loop. The long-soak capture
    // (scratch/build6_pir2_longsoak_findings.md) showed the CPU spends 24%
    // of time at PC bucket 0x22000 and ~13% at 0x7FEA00, with scattered
    // I/O reads. That's a polling loop. If it's waiting for an interrupt
    // that never fires, IPL stays at 3'b111 forever.
    //
    //   [31:24] ipl_levels_ever_seen  -- bit n => CPU ever saw IPL level n
    //                                    (lvl0=any, lvl1=VIA1, lvl2=VIA2,
    //                                     lvl4=SCC, lvl6=NMI on Mac II)
    //   [23:16] iack_cnt              -- wrap-8 count of IACK bus cycles
    //                                    (cpuFC == 3'b111 = CPU spaces)
    //   [15:0]  ipl_active_cycles     -- wrap-16 count of clk cycles where
    //                                    cpuIPL_n != 3'b111 (= IRQ pending)
    //
    // Decision tree:
    //   ipl_active_cycles grows + iack_cnt grows => IRQs delivered and
    //     serviced. Hang is in the handler or elsewhere; PIPL is done its
    //     job ruling out the delivery path.
    //   ipl_active_cycles grows + iack_cnt = 0 => IRQs asserted but CPU
    //     masking them (SR I-bit too high). Why? -- next probe.
    //   ipl_active_cycles = 0 + iack_cnt = 0 => NO peripheral asserts any
    //     IRQ. The hang is in the peripheral RTL side -- e.g. ASC FIFO
    //     refill_irq only fires in FIFO mode (asc_mode==1), or a VIA
    //     timer not counting down.
    reg [7:0]  ipl_seen_bm;
    reg [7:0]  pipl_iack_cnt;
    reg [3:0]  pipl_last_iack_lvl;
    reg [15:0] pipl_active_cyc;
    reg        pipl_in_iack_d;
    wire [2:0] pipl_lvl_now = ~cpuIPL_n;          // active-low decode (111 -> 000)
    wire       pipl_in_iack = (cpuFC == 3'b111);   // 68k IACK cycle
    initial begin
        ipl_seen_bm        = 8'd0;
        pipl_iack_cnt      = 8'd0;
        pipl_last_iack_lvl = 4'd0;
        pipl_active_cyc    = 16'd0;
        pipl_in_iack_d     = 1'b0;
    end
    always @(posedge clk) begin
        pipl_in_iack_d <= pipl_in_iack;
        // Mark this IPL level as ever-seen (only when an IRQ is actually
        // asserted; 3'b111 = no IRQ).
        if (cpuIPL_n != 3'b111)
            ipl_seen_bm[pipl_lvl_now] <= 1'b1;
        // Free-running cycle counter while any IRQ pending.
        if (cpuIPL_n != 3'b111)
            pipl_active_cyc <= pipl_active_cyc + 16'd1;
        // Count rising edges of IACK function code.
        if (pipl_in_iack && !pipl_in_iack_d) begin
            pipl_iack_cnt      <= pipl_iack_cnt + 8'd1;
            // 68k IACK cycle puts the IRQ level in cpuAddr[3:1].
            pipl_last_iack_lvl <= {1'b0, cpuAddr[3:1]};
        end
    end
    reg [31:0] pipl_r;
    always @(posedge clk)
        pipl_r <= {ipl_seen_bm, pipl_iack_cnt, {1'b0, pipl_last_iack_lvl[2:0]}, pipl_active_cyc};

    // PIPL disabled for build #22 to free routing congestion for PCAK
    // (Control CIR ACK observability). PIPL was the post-Phase-1 IRQ
    // delivery probe; the SCC/Phase-2 investigation it served has long
    // since concluded. Re-enable if IRQ delivery becomes relevant again.
    // altsource_probe #(
    //     .instance_id ("PIPL"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pipl (.probe(pipl_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== Per-IRQ-source edge counters (PIRQ) ============================
    // PIPL showed IRQs flow normally in Phase 2 (ipl_active_cyc wraps 16
    // bits per ~200 ms sample), but `levels_seen` revealed SCC stops being
    // asserted in Phase 2 while VIA1/VIA2 keep firing.  PIRQ counts each
    // source independently so we can see assertion-rate deltas between
    // Phase 1 and Phase 2.  Edges are detected on the active-low signal
    // going low (assertion).
    //
    //   [31:24] via1_irq_cnt  (wrap-8): _viaIrq  falling edges
    //   [23:16] via2_irq_cnt  (wrap-8): _via2Irq falling edges
    //   [15:8]  scc_irq_cnt   (wrap-8): _sccIrq  falling edges
    //   [7:0]   reserved      (= 0)
    //
    // Decision:
    //   via1 grows, via2 grows, scc stops growing in P2 => SCC dies in P2.
    //     Likely cause: AppleTalk init disables SCC IRQ, OR SCC RTL has a
    //     bug where after some specific access pattern it stops asserting.
    //   any source stops growing entirely => that peripheral is the wedge.
    //   all three steady, very high rates => the loop IS being serviced;
    //     hang is in the handler logic / OS state machine.
    reg via1_irq_d, via2_irq_d, scc_irq_d;
    reg [7:0] via1_irq_cnt, via2_irq_cnt, scc_irq_cnt;
    initial begin
        via1_irq_d   = 1'b1; via2_irq_d   = 1'b1; scc_irq_d   = 1'b1;
        via1_irq_cnt = 8'd0; via2_irq_cnt = 8'd0; scc_irq_cnt = 8'd0;
    end
    always @(posedge clk) begin
        via1_irq_d <= via1_irq_n;
        via2_irq_d <= via2_irq_n;
        scc_irq_d  <= scc_irq_n;
        if (via1_irq_d && !via1_irq_n) via1_irq_cnt <= via1_irq_cnt + 8'd1;
        if (via2_irq_d && !via2_irq_n) via2_irq_cnt <= via2_irq_cnt + 8'd1;
        if (scc_irq_d  && !scc_irq_n ) scc_irq_cnt  <= scc_irq_cnt  + 8'd1;
    end
    reg [31:0] pirq_r;
    always @(posedge clk)
        pirq_r <= {via1_irq_cnt, via2_irq_cnt, scc_irq_cnt, 8'd0};

    // PIRQ disabled for build #22 to free routing congestion for PCAK.
    // The SCC/Phase-2 per-source IRQ counters proved their point and
    // aren't load-bearing for the FPU CIR ACK investigation.
    // altsource_probe #(
    //     .instance_id ("PIRQ"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pirq (.probe(pirq_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== SCC access probe (PSCC) =========================================
    // Build #9's PIRQ proved scc_irq_cnt = 0 across the entire boot. SCC
    // never asserts an IRQ. Now: does the OS even talk to SCC?  If no
    // CPU cycles ever hit selectSCC, the boot ROM didn't initialize SCC --
    // possibly because XPRAM SPValid magic bytes are wrong (rtl/rtc.v) and
    // it skipped AppleTalk init entirely. If the CPU DOES talk to SCC,
    // then SCC RTL or wr9[3] (MIE) is the wedge.
    //
    //   [31]    selectSCC_ever_seen  (sticky)
    //   [30]    selectASC_ever_seen  (sticky, for context)
    //   [29]    selectVIA_ever_seen  (sticky, sanity check)
    //   [28]    selectVIA2_ever_seen (sticky, sanity check)
    //   [27:24] reserved
    //   [23:16] scc_wr_cnt (wrap-8)
    //   [15:8]  scc_rd_cnt (wrap-8)
    //   [7:0]   last_scc_low_addr (low 8 bits of cpuAddr on last SCC access)
    reg pscc_scc_ever, pscc_asc_ever, pscc_via_ever, pscc_via2_ever;
    reg [7:0] pscc_wr_cnt, pscc_rd_cnt;
    reg [7:0] pscc_last_low;
    initial begin
        pscc_scc_ever = 1'b0; pscc_asc_ever = 1'b0;
        pscc_via_ever = 1'b0; pscc_via2_ever = 1'b0;
        pscc_wr_cnt = 8'd0; pscc_rd_cnt = 8'd0;
        pscc_last_low = 8'd0;
    end
    wire pscc_bus_cycle = cpuAS_n_d && !cpuAS_n;
    always @(posedge clk) begin
        if (selectSCC ) pscc_scc_ever  <= 1'b1;
        if (selectASC ) pscc_asc_ever  <= 1'b1;
        if (selectRAM ) ; // ignore: too common to be useful here
        if (selectROM ) ; // ignore: also too common
        if (pscc_bus_cycle && selectSCC) begin
            pscc_last_low <= cpuAddr[7:0];
            if (cpuRW)  pscc_rd_cnt <= pscc_rd_cnt + 8'd1;
            else        pscc_wr_cnt <= pscc_wr_cnt + 8'd1;
        end
    end
    // Sample selectVIA/VIA2 stickies via the existing selectNuBus path proxy
    // -- since dbg_min doesn't currently take selectVIA/VIA2 directly, use
    // the indirect indicators we DO have: PSCS already tracked select via
    // its inputs, but PSCS is disabled. For build #10 we leave VIA/VIA2
    // ever-seen at 0 in PSCC's bits 29/28 (decoder will treat 0 as "n/a").
    reg [31:0] pscc_r;
    always @(posedge clk)
        pscc_r <= {pscc_scc_ever, pscc_asc_ever, pscc_via_ever, pscc_via2_ever,
                   4'd0,
                   pscc_wr_cnt, pscc_rd_cnt, pscc_last_low};

    // PSCC disabled for build #13 to free fit budget for PIFA (IF-only PC
    // sampler). Build #10 ruled out SCC entirely; values are frozen at
    // 30/35 throughout Phase 2 and re-enabling adds no information.
    // altsource_probe #(
    //     .instance_id ("PSCC"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pscc (.probe(pscc_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== I/O peripheral access histogram (PIOH) ===========================
    // Build #10 PSCC showed SCC accesses are static at 30/36 -- not being
    // polled. PIOH counts CPU bus cycles per peripheral so we can identify
    // which one IS being hit by the post-Phase-1 busy-loop. ASC was already
    // in the existing PASC probe (asc_wr_cnt); here we add VIA1, VIA2, IWM,
    // and re-count ASC for symmetry. All wrap-8.
    //
    //   [31:24] via1_acc_cnt  (wrap-8): any cpu cycle to selectVIA  region
    //   [23:16] via2_acc_cnt  (wrap-8): any cpu cycle to selectVIA2 region
    //   [15:8]  asc_acc_cnt   (wrap-8): any cpu cycle to selectASC  region
    //   [7:0]   iwm_acc_cnt   (wrap-8): any cpu cycle to selectIWM  region
    //
    // The peripheral whose counter wraps fastest is what the loop hits
    // most. If VIA1 dominates -> the loop is polling VIA1 IFR (interrupt
    // flag register) for a bit that never sets. If ASC dominates -> the
    // Sound Manager is polling ASC. Etc.
    reg [7:0] pioh_via1_cnt, pioh_via2_cnt, pioh_asc_cnt, pioh_iwm_cnt;
    initial begin
        pioh_via1_cnt = 8'd0; pioh_via2_cnt = 8'd0;
        pioh_asc_cnt  = 8'd0; pioh_iwm_cnt  = 8'd0;
    end
    always @(posedge clk) begin
        if (pscc_bus_cycle && selectVIA ) pioh_via1_cnt <= pioh_via1_cnt + 8'd1;
        if (pscc_bus_cycle && selectVIA2) pioh_via2_cnt <= pioh_via2_cnt + 8'd1;
        if (pscc_bus_cycle && selectASC ) pioh_asc_cnt  <= pioh_asc_cnt  + 8'd1;
        if (pscc_bus_cycle && selectIWM ) pioh_iwm_cnt  <= pioh_iwm_cnt  + 8'd1;
    end
    reg [31:0] pioh_r;
    always @(posedge clk)
        pioh_r <= {pioh_via1_cnt, pioh_via2_cnt, pioh_asc_cnt, pioh_iwm_cnt};

    altsource_probe #(
        .instance_id ("PIOH"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pioh (.probe(pioh_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== Passive memory snoop (PMEM / PMEM2) ============================
    // Build #11 PIOH proved Phase 2 has ZERO bus cycles to VIA1/VIA2/ASC/IWM/SCC.
    // The CPU is in a pure RAM+FPU compute loop at PC bucket 0x22000.
    // PMEM passively latches cpu_din whenever the CPU READS at fixed
    // addresses 0x22000-0x22007 (= 4 words, 8 bytes). The instruction-fetch
    // cycles at the loop's PC hit these addresses constantly, so the
    // latches fill within the first few microseconds.
    //
    //   PMEM:  [31:16] word at 0x22000 / [15:0] word at 0x22002
    //   PMEM2: [31:16] word at 0x22004 / [15:0] word at 0x22006
    //
    // Reading both probes together gives the first 8 bytes of code at
    // 0x22000 -- enough to disassemble the loop's first 2-4 instructions
    // and confirm whether it's an infinite computation loop, a polling
    // loop on an unmapped peripheral, or something else.
    reg [15:0] mem_22000_r, mem_22002_r, mem_22004_r, mem_22006_r;
    reg        mem_22000_p, mem_22002_p, mem_22004_p, mem_22006_p;
    initial begin
        mem_22000_r = 16'd0; mem_22002_r = 16'd0;
        mem_22004_r = 16'd0; mem_22006_r = 16'd0;
        mem_22000_p = 1'b0; mem_22002_p = 1'b0;
        mem_22004_p = 1'b0; mem_22006_p = 1'b0;
    end
    wire mem_bus_rd = cpuAS_n_d && !cpuAS_n && cpuRW;
    always @(posedge clk) begin
        // Arm pending flags on the bus cycle.
        // Verilog hex literals ignore underscores: 32'h0000_2000 = 0x00002000
        // (RAM, NOT the FPU CIR base). The FPU is at 0x00022000-0x00023FFF
        // (see fpuAddrMatch in LBMacTwo.sv:472). Use the correct constant.
        if (mem_bus_rd && cpuAddr == 32'h00022000) mem_22000_p <= 1'b1;
        if (mem_bus_rd && cpuAddr == 32'h00022002) mem_22002_p <= 1'b1;
        if (mem_bus_rd && cpuAddr == 32'h00022004) mem_22004_p <= 1'b1;
        if (mem_bus_rd && cpuAddr == 32'h00022006) mem_22006_p <= 1'b1;
        // Latch on mac_dout_valid.
        if (mem_22000_p && mac_dout_valid) begin
            mem_22000_r <= cpu_din;
            mem_22000_p <= 1'b0;
        end
        if (mem_22002_p && mac_dout_valid) begin
            mem_22002_r <= cpu_din;
            mem_22002_p <= 1'b0;
        end
        if (mem_22004_p && mac_dout_valid) begin
            mem_22004_r <= cpu_din;
            mem_22004_p <= 1'b0;
        end
        if (mem_22006_p && mac_dout_valid) begin
            mem_22006_r <= cpu_din;
            mem_22006_p <= 1'b0;
        end
    end
    reg [31:0] pmem_r, pmem2_r;
    always @(posedge clk) begin
        pmem_r  <= {mem_22000_r, mem_22002_r};
        pmem2_r <= {mem_22004_r, mem_22006_r};
    end

    // PMEM / PMEM2 disabled for build #24 retry to free routing for the
    // cpSAVE latch-timing fix (TG68 cp_save_decode now reads data_in
    // directly, which added fanout). These probes snooped writes around
    // $22000 during the FRESTORE-wedge investigation (build #12-#15),
    // which is closed. PFRR + PFRW + PFST cover the same address space.
    // altsource_probe #(
    //     .instance_id ("PMEM"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pmem (.probe(pmem_r), .source(), .source_clk(clk), .source_ena(1'b1));
    //
    // altsource_probe #(
    //     .instance_id ("PMEM2"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pmem2 (.probe(pmem2_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PFLT: floppy track / step / side / live diskImageData.
    //   [31]    flp_disk_data != 0 (live byte staged)
    //   [30:24] flp_track[6:0]    (driveTrack — which track encoded RIGHT NOW)
    //   [23]    flp_side          (driveSide)
    //   [22:16] iwm_arm_high[6:0] (top 7 bits of readDataArmDelay[11:5])
    //   [15:0]  flp_step_cnt      (STEP register-write count, wrap16)
    reg [31:0] pflt_r;
    always @(posedge clk)
        pflt_r <= {(flp_disk_data != 8'h00), flp_track, flp_side,
                   iwm_arm_high, flp_step_cnt};

    // PFLT disabled for build #16 to free fit budget for PFST (FPU CIR
    // FSM state probe).  Floppy track / step / side info has been frozen
    // at driveTrack=22 for many builds — Phase-2 IWM isn't load-bearing
    // for the FRESTORE-protocol investigation.
    // altsource_probe #(
    //     .instance_id ("PFLT"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pflt (.probe(pflt_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PSLT: Slot-E REGISTER write monitor (filters out VRAM writes).
    //   MDC824 register space: cpuAddr[31:24]==$FE (slot E) AND
    //   cpuAddr[23:16]==$20 (register window 0x200000-0x20FFFF).
    //   Useful registers: 0x013C = vblank_enable, 0x0148 = irq_clear.
    //
    //   Layout:
    //     [31]    = sticky: at least one register write to addr_low16 == 0x0148
    //     [30:24] = saturating count of writes to 0x013C (vblank_enable)
    //     [23:16] = saturating count of writes to 0x0148 (irq_clear)
    //     [15:0]  = low 16 bits of last REGISTER write address
    //
    //   If [23:16] stays at 0 while vbl_count is stuck at 1, the Mac is never
    //   writing the IRQ-clear register and the slot driver isn't installed.
    //   If [23:16] climbs but vbl_count stays at 1, our irq_clear decode is
    //   wrong (or vblank_enable was disabled and writes don't help).
    reg cpuAS_n_d2;
    reg sticky_148;
    reg [6:0] cnt_13c;   // saturating
    reg [7:0] cnt_148;   // saturating
    reg [15:0] last_reg_addr;
    wire slot_e_reg_write = !cpuAS_n && cpuAS_n_d2 &&
                            selectNuBus && !cpuRW &&
                            (cpuAddr[31:24] == 8'hFE) &&
                            (cpuAddr[23:16] == 8'h20);
    initial begin
        cpuAS_n_d2 = 1'b1;
        sticky_148 = 1'b0;
        cnt_13c = 7'd0;
        cnt_148 = 8'd0;
        last_reg_addr = 16'd0;
    end
    always @(posedge clk) begin
        cpuAS_n_d2 <= cpuAS_n;
        if (slot_e_reg_write) begin
            last_reg_addr <= cpuAddr[15:0];
            // 0x0148 byte write or 0x0148 word write (both halves)
            if (cpuAddr[15:1] == 15'h00A4) begin
                sticky_148 <= 1'b1;
                if (cnt_148 != 8'hFF) cnt_148 <= cnt_148 + 8'd1;
            end
            // 0x013C: vblank_enable
            if (cpuAddr[15:1] == 15'h009E) begin
                if (cnt_13c != 7'h7F) cnt_13c <= cnt_13c + 7'd1;
            end
        end
    end
    reg [31:0] slt_r;
    always @(posedge clk)
        slt_r <= {sticky_148, cnt_13c, cnt_148, last_reg_addr};

    // PSLT disabled to free JTAG-routing headroom for the cold-boot RAM-clear logic.
    // altsource_probe #(
    //     .instance_id ("PSLT"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pslt (.probe(slt_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PADP: ADB Poll-distribution monitor.
    //   Edge-detects cmd_valid 0->1 in adb.sv (= a fresh command byte has
    //   just been latched) and counts which command byte we got. We
    //   especially care whether ROM sends cmd_byte 0x3C (= addr 3 Talk
    //   reg 0 = Apple Mouse data poll) at all. If kbd_poll_cnt grows but
    //   mouse_poll_cnt stays at 0, ROM enumerated the mouse but is not
    //   polling it. If both grow but cursor still doesn't move, the bug
    //   is in the Talk reg 0 response delivery.
    //
    //   Source bits in dbg_adb (set in dataController_top.sv):
    //     [10] = cmd_valid     (edge 0->1 = new cmd byte captured)
    //     [9:8] = adb_st       (00 = ST_COMMAND)
    //     [7:0] = cmd_byte     (the just-latched command)
    //
    //   Layout (32 bits):
    //     [31:24] last_cmd        — most recent cmd_byte
    //     [23:16] last_cmd_prev   — second-most-recent distinct cmd_byte
    //     [15:8]  mouse_poll_cnt  — count of cmd_byte == 0x3C (saturating)
    //     [7:0]   kbd_poll_cnt    — count of cmd_byte == 0x2C (saturating)
    reg        cv_prev;
    reg [7:0]  last_cmd;
    reg [7:0]  last_cmd_prev;
    reg [7:0]  mouse_poll_cnt;
    reg [7:0]  kbd_poll_cnt;
    initial begin
        cv_prev        = 1'b0;
        last_cmd       = 8'h00;
        last_cmd_prev  = 8'h00;
        mouse_poll_cnt = 8'd0;
        kbd_poll_cnt   = 8'd0;
    end
    always @(posedge clk) begin
        cv_prev <= dbg_adb[10];
        if (!cv_prev && dbg_adb[10]) begin
            // cmd_valid 0->1 — adb.sv just latched a new cmd byte.
            // dbg_adb[7:0] now reflects the new cmd_byte (assigned same edge,
            // visible NEXT cycle in NBA semantics — but cv_prev edge detection
            // also fires NEXT cycle, so timing lines up).
            if (dbg_adb[7:0] != last_cmd) begin
                last_cmd_prev <= last_cmd;
            end
            last_cmd <= dbg_adb[7:0];
            case (dbg_adb[7:0])
                8'h3C: if (mouse_poll_cnt != 8'hFF) mouse_poll_cnt <= mouse_poll_cnt + 8'd1;
                8'h2C: if (kbd_poll_cnt   != 8'hFF) kbd_poll_cnt   <= kbd_poll_cnt   + 8'd1;
                default: ; // ignore
            endcase
        end
    end
    reg [31:0] padp_r;
    always @(posedge clk)
        padp_r <= {last_cmd, last_cmd_prev, mouse_poll_cnt, kbd_poll_cnt};

    // PADP disabled for build #13 to free fit budget for PIFC (IF cycle
    // counter). ADB cmd-histogram showed both kbd_polls and mouse_polls
    // saturated at 255 -- mouse/kbd path is healthy; not load-bearing
    // for the Welcome-hang investigation.
    // altsource_probe #(
    //     .instance_id ("PADP"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_padp (.probe(padp_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PSRR / PSRL: SR byte sequences (newest byte in [7:0]).
    //   PSRR = what the CPU READ from the SR (what ROM actually receives).
    //   PSRL = what the shim LOADED into the SR (shift-in path).
    // With the forced mouse response (0x83,0x85), a healthy path shows
    // alternating 83/85 in BOTH. If PSRL alternates but PSRR repeats or
    // shows 0x3C (the cmd byte), the SR is corrupted between load and read.
    // PSRR/PSRL disabled to free fit budget — the SR byte-sequence diagnosis
    // is done (confirmed stale 00/3C reads before the real response). Re-enable
    // by uncommenting if byte-level SR debugging is needed again.
    // reg [31:0] psrr_r, psrl_r;
    // always @(posedge clk) begin
    //     psrr_r <= dbg_adb3;
    //     psrl_r <= dbg_adb4;
    // end
    // altsource_probe #(
    //     .instance_id ("PSRR"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psrr (.probe(psrr_r), .source(), .source_clk(clk), .source_ena(1'b1));
    // altsource_probe #(
    //     .instance_id ("PSRL"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psrl (.probe(psrl_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== Instruction-fetch sampler (PIFA / PIFC) -- build #13 =============
    // The PADR probe samples cpuAddr every clock, so any cycle where AS is
    // high and the address bus holds the previous cycle's address pollutes
    // the histogram with residue. PIR2 hammers $22006 with writes ~50k/sample,
    // so PADR's 24% $22006 bucket is mostly write residue, NOT execution.
    //
    // PIFA captures cpuAddr ONLY at the instant of a real instruction-fetch
    // bus cycle: AS falling edge, cpuRW=1 (read), and cpuFC in {2,6} =
    // {user program, super program}. That filters out data reads, IACK
    // (FC=7), and CP cycles. Sample PIFA multiple times per round (rapid
    // overwrite at ~1 M IF/sec) and build a histogram offline. PIFC tracks
    // the IF cycle count + last FC for sanity.
    //
    //   PIFA: cpuAddr at last IF cycle
    //   PIFC: [31:24] reserved=0
    //         [23:16] count of IF cycles at cpuFC=6 (super prog) wrap8
    //         [15:8]  count of IF cycles at cpuFC=2 (user prog) wrap8
    //         [7:0]   total IF cycle count wrap8
    //
    // Decision tree once PIFA is sampled:
    //   PIFA ~constant at one address -> tight inner loop; that's the PC
    //   PIFA scattered across a small range -> short loop body
    //   PIFA bouncing $40xxxxxx + $00xxxxxx -> ROM + RAM code mixed
    //   PIFA never at $00022xxx -> the $22000 bucket really was residue
    //
    // Note: AS-falling-edge is detected via cpuAS_n_d (already declared
    // for the as_cycles counter at the top of dbg_min).
    wire pifa_if_cycle = cpuAS_n_d && !cpuAS_n && cpuRW &&
                         (cpuFC == 3'b010 || cpuFC == 3'b110);
    reg [31:0] pifa_r;
    reg [7:0]  pifc_total, pifc_user, pifc_super;
    initial begin
        pifa_r     = 32'd0;
        pifc_total = 8'd0;
        pifc_user  = 8'd0;
        pifc_super = 8'd0;
    end
    always @(posedge clk) begin
        if (pifa_if_cycle) begin
            pifa_r     <= cpuAddr;
            pifc_total <= pifc_total + 8'd1;
            if (cpuFC == 3'b010) pifc_user  <= pifc_user  + 8'd1;
            if (cpuFC == 3'b110) pifc_super <= pifc_super + 8'd1;
        end
    end
    reg [31:0] pifc_r;
    always @(posedge clk)
        pifc_r <= {8'd0, pifc_super, pifc_user, pifc_total};

    altsource_probe #(
        .instance_id ("PIFA"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pifa (.probe(pifa_r), .source(), .source_clk(clk), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("PIFC"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pifc (.probe(pifc_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== FPU CIR Response/Restore probes (PFRR / PFRW) -- build #14 =======
    // Build #13 found PIFA frozen at $4000D612 (FRESTORE opcode at $D60E)
    // and PMEM showed Response CIR ($22000) consistently returning 0x8000
    // (high bit = "Come Again" = BUSY-like). PFRR confirms the FPU's
    // Response CIR returns CA=1 forever, and PFRW confirms the OS is
    // pushing a FRESTORE frame into Restore CIR ($22006) indefinitely.
    //
    // Both probes filter on cpuFC == 3'b111 (CPU space, FPU is in CPU
    // space) so we don't catch any false hits from RAM cycles at the
    // same virtual address.
    //
    //   PFRR (Response CIR reads at $00022000, FC=7):
    //     [31:16] last 16-bit value the CPU read at $22000 (Response prim)
    //     [15:8]  wrap8 count of CIR-Response reads
    //     [7:0]   wrap8 count of CIR-Control writes at $22002 (sanity)
    //
    //   PFRW (Restore CIR writes at $00022006, FC=7):
    //     [31:16] last 16-bit value the CPU wrote at $22006 (frame word)
    //     [15:8]  wrap8 count of CIR-Restore writes
    //     [7:0]   wrap8 count of CIR-OpWord writes at $22008 (sanity)
    //
    // Expected reading once Phase 2 reached:
    //   PFRR.last_resp == 0x8000 (or 0x8900 if real BUSY prim)
    //   PFRR.read_cnt wraps fast — OS polling Response heavily
    //   PFRW.last_restore = a frame word from the FPU state being pushed
    //   PFRW.write_cnt wraps fast — frame transfer in progress
    //   Sanity counts (Control / OpWord) low — the FRESTORE protocol
    //     doesn't use those registers.
    // FPU CIR base is 0x00022000, NOT 0x00002000 (Verilog hex literals
    // ignore underscores so 32'h0000_2000 is RAM, not FPU). Use the full
    // 0x00022xxx literal so the address comparator actually fires on
    // FPU CIR cycles.
    wire pfrr_resp_rd  = cpuAS_n_d && !cpuAS_n &&  cpuRW &&
                         (cpuFC == 3'b111) && (cpuAddr == 32'h00022000);
    wire pfrr_ctrl_wr  = cpuAS_n_d && !cpuAS_n && !cpuRW &&
                         (cpuFC == 3'b111) && (cpuAddr == 32'h00022002);
    wire pfrw_rest_wr  = cpuAS_n_d && !cpuAS_n && !cpuRW &&
                         (cpuFC == 3'b111) && (cpuAddr == 32'h00022006);
    wire pfrw_opw_wr   = cpuAS_n_d && !cpuAS_n && !cpuRW &&
                         (cpuFC == 3'b111) && (cpuAddr == 32'h00022008);
    // Latch the read VALUE on mac_dout_valid (same idiom as PIR3).
    reg pfrr_pending;
    reg [15:0] pfrr_last_resp;
    reg [7:0]  pfrr_resp_rd_cnt;
    reg [7:0]  pfrr_ctrl_wr_cnt;
    initial begin
        pfrr_pending     = 1'b0;
        pfrr_last_resp   = 16'd0;
        pfrr_resp_rd_cnt = 8'd0;
        pfrr_ctrl_wr_cnt = 8'd0;
    end
    // Build #28 PFRR fix: FPU reads use DSACK, not the SDRAM arbiter, so
    // mac_dout_valid never fires for FPU accesses and the old code would
    // never capture last_resp. Latch cpu_din on AS rising edge — for FPU
    // reads, the LBMacTwo.sv data mux routes fpu_data_out to cpu_data_in
    // (cpu_din) for the whole cycle, so the value visible at end-of-cycle
    // is the response data TG68 actually clocked.
    always @(posedge clk) begin
        if (pfrr_resp_rd) begin
            pfrr_pending     <= 1'b1;
            pfrr_resp_rd_cnt <= pfrr_resp_rd_cnt + 8'd1;
        end
        if (pfrr_pending && !cpuAS_n_d && cpuAS_n) begin
            // AS rising edge: bus cycle ends. Capture the data the CPU saw.
            pfrr_last_resp <= cpu_din;
            pfrr_pending   <= 1'b0;
        end
        if (pfrr_ctrl_wr) pfrr_ctrl_wr_cnt <= pfrr_ctrl_wr_cnt + 8'd1;
    end
    reg [31:0] pfrr_r;
    always @(posedge clk)
        pfrr_r <= {pfrr_last_resp, pfrr_resp_rd_cnt, pfrr_ctrl_wr_cnt};

    reg [15:0] pfrw_last_rest;
    reg [7:0]  pfrw_rest_wr_cnt;
    reg [7:0]  pfrw_opw_wr_cnt;
    initial begin
        pfrw_last_rest    = 16'd0;
        pfrw_rest_wr_cnt  = 8'd0;
        pfrw_opw_wr_cnt   = 8'd0;
    end
    always @(posedge clk) begin
        if (pfrw_rest_wr) begin
            pfrw_last_rest   <= cpu_dout;
            pfrw_rest_wr_cnt <= pfrw_rest_wr_cnt + 8'd1;
        end
        if (pfrw_opw_wr) pfrw_opw_wr_cnt <= pfrw_opw_wr_cnt + 8'd1;
    end
    reg [31:0] pfrw_r;
    always @(posedge clk)
        pfrw_r <= {pfrw_last_rest, pfrw_rest_wr_cnt, pfrw_opw_wr_cnt};

    altsource_probe #(
        .instance_id ("PFRR"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pfrr (.probe(pfrr_r), .source(), .source_clk(clk), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("PFRW"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pfrw (.probe(pfrw_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== FPU CIR FSM state probe (PFST) -- build #16 =====================
    // Pass-through of the packed dbg_cir_state vector from mc68881_top:
    //   [31:16] cir_response_prim
    //   [15:11] current cir_state_reg position (0=CIR_IDLE)
    //   [10:6]  max state position ever reached (sticky)
    //   [5]     opword-written sticky
    //   [4]     command-written sticky
    //   [3]     restore-trigger-seen sticky
    //   [2]     exception-state-seen sticky
    //   [1]     restore-frame-state-seen sticky
    //   [0]     cir_active (live)
    //
    // Read this together with PIR2 (writes at $22006) to determine which
    // protocol step is stalled: if max_state stays at CIR_IDLE (=0) the
    // CPU never wrote opword to OPSEL; if max_state reaches CIR_RESTORE_FORMAT
    // but never CIR_RESTORE_FRAME, the FORMAT word path is broken; if max
    // state reaches CIR_EXCEPT_PRE/MID/POST, the FORMAT word was invalid.
    reg [31:0] pfst_r;
    always @(posedge clk) pfst_r <= fpu_dbg_cir_state;

    altsource_probe #(
        .instance_id ("PFST"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pfst (.probe(pfst_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== Coprocessor Control CIR ACK probe (PCAK) -- build #22 ===========
    // Diagnoses whether the bug-#3 fix (cp_except_ack/cp_except_trap path
    // writing 0x0001 to Control CIR at $00022002) actually produces a bus
    // write the FPU can see, and whether bit 0 of that write is 1.
    //
    // Read together with PFST:
    //   - If PCAK[31:24] = 0 AND PFST max_state reached EXCEPT_PRE: my
    //     microstate sequence never generated the bus write. The flow from
    //     cp_idle_resp -> cp_except_ack -> cp_except_trap is broken.
    //   - If PCAK[31:24] > 0 AND PCAK last_din bit 0 = 0: my write reaches
    //     the FPU but with the wrong data (sndOPC bleed-through or muxing
    //     bug). data_write_tmp <= 0x0001 clause isn't firing in time.
    //   - If PCAK[23:16] > 0 (one or more writes with bit 0 = 1) AND PFST
    //     current state STILL = EXCEPT_PRE: the FPU received the ACK but
    //     its CIR_EXCEPT_PRE -> CIR_IDLE transition isn't firing (FPU-side
    //     issue, possibly cir_mode_reg = 0 or another guard).
    //   - If PCAK[23:16] > 0 AND PFST current state = CIR_IDLE: the
    //     protocol works end-to-end; the bench wedge has a different root.
    //
    // Packed layout:
    //   [31:24] total Control CIR writes seen on bus (saturating 8-bit)
    //   [23:16] count of those writes where cpu_dout[0] = 1 (saturating)
    //   [15:0]  last cpu_dout[15:0] captured on a Control CIR write event
    //
    // Trigger: falling edge of cpuAS_n (bus-cycle start) AND the access is
    // a write to Control CIR — cpuFC=111 (CPU space), cpuAddr[31:16]=0x0002,
    // cpuAddr[15:13]=001, cpuAddr[5:1]=00001, cpuRW=0 (write).
    wire pcak_event =
        (cpuAS_n_d && !cpuAS_n)           // falling edge of _cpuAS
        && (cpuFC == 3'b111)
        && (cpuAddr[31:16] == 16'h0002)
        && (cpuAddr[15:13] == 3'b001)
        && (cpuAddr[5:1]   == 5'b00001)
        && !cpuRW;
    reg [7:0]  pcak_total_cnt;
    reg [7:0]  pcak_ack_cnt;
    reg [15:0] pcak_last_din;
    always @(posedge clk) begin
        if (pcak_event) begin
            pcak_last_din <= cpu_dout;
            if (pcak_total_cnt != 8'hFF) pcak_total_cnt <= pcak_total_cnt + 8'd1;
            if (cpu_dout[0] && pcak_ack_cnt != 8'hFF) pcak_ack_cnt <= pcak_ack_cnt + 8'd1;
        end
    end
    reg [31:0] pcak_r;
    always @(posedge clk)
        pcak_r <= {pcak_total_cnt, pcak_ack_cnt, pcak_last_din};

    altsource_probe #(
        .instance_id ("PCAK"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pcak (.probe(pcak_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== FPU detection probe (PFPD) — build #27, bug #6 ===================
    // Diagnoses bug #6 "coprocessor not installed" bomb. supermario's
    // OS/Universal.a:TestForFPU shows Mac OS detects the FPU at ROM boot by
    // executing FNOP and checking whether the F-line trap fires; the result
    // is written to HWCfgFlags bit 12 (hwCbFPU). Later code (apps, INITs,
    // SANE) reads that bit but never re-probes. So the dialog 7 min into
    // boot fires when an FPU instruction takes an F-line trap — either
    // because (a) HWCfgFlags bit got cleared at boot (TestForFPU's FNOP
    // F-lined and the OS recorded "no FPU"), or (b) a different FPU op
    // path our FPU doesn't service correctly fires later.
    //
    // PFPD layout (packed 32 bits):
    //   [31:24] total FPU bus cycles in CPU space (saturating 8-bit).
    //           Should grow steadily as the OS uses the FPU. =0 means the
    //           CPU is not even trying to touch the FPU.
    //   [23:16] cpuAddr[7:0] of the last FPU access. Wraps fast; sample
    //           several times to see the access pattern. Mac OS typical
    //           CIR offsets: $00 Response, $02 Control, $04 Save, $06
    //           Restore, $08 OpWord, $0A Command, $0E Condition, $10
    //           Operand, $18 InstAddr, $1C OpAddr.
    //   [15:8]  count of FPU accesses where cpuAddr[5:1] is NOT in
    //           {0,2,3} — i.e. NOT touched by the LBMacTwo.sv:484-487
    //           remap. These cover OpWord/Command/Condition/Operand/etc.
    //           writes — the "cpGEN-style traffic" of normal FPU
    //           instructions including FNOP. If this stays at 0 while
    //           [31:24] grows, the OS is only reading Response/Save and
    //           never issuing real FPU ops (suggests it already concluded
    //           "no FPU" via Universal.a's FNOP probe).
    //   [7:0]   count of WRITES to $2200E = Condition CIR (cpuAddr[7:0]=$0E
    //           AND cpuRW=0). Build #27 used this slot for Save-CIR reads,
    //           but the data captured in build #27 already confirmed Save-rd
    //           works (=1). Build #28 repurposes it to count cpBcc/cpScc/
    //           cpDBcc/cpTRAPcc Condition writes — these include FNOP, which
    //           is structurally cpBcc-word with cond=FBF. If this stays at 0
    //           while opword_seen=1, the OS issued OpWord writes for cpSAVE/
    //           cpRESTORE only; NO FBcc protocol ran => HWCfgFlags FPU bit
    //           never got tested by an FNOP detection. If it's > 0, FNOP/
    //           FBcc detection DID run; bomb is from PFRR last_resp shape.
    //
    // Reading the probe at the bomb dialog:
    //   total grows but periph_like stays at 0  => Mac OS never issues
    //     a real FPU instruction. HWCfgFlags FPU bit must have been cleared
    //     at boot — FNOP detection failed. Look at what our FPU returned
    //     on the FNOP path (Response CIR for cpGEN).
    //   total grows, periph_like grows, save_rd_cnt grows => FPU
    //     instructions ARE flowing through CIR mode. The dialog comes from
    //     a specific op the FPU doesn't handle correctly. Probably a
    //     missing cpGEN response shape.
    //   total = 0 entirely => the OS isn't touching the FPU at all. The
    //     dialog is from a different mechanism (peripheral-mode probe,
    //     bus-error from a stray pointer, etc.) — Theory 2 or 3
    //     reconsidered.
    wire pfpd_fpu_cycle = (cpuAS_n_d && !cpuAS_n)
        && (cpuFC == 3'b111)
        && (cpuAddr[31:16] == 16'h0002)
        && (cpuAddr[15:13] == 3'b001);
    wire pfpd_remap_target = (cpuAddr[5:1] == 5'd0)
                          || (cpuAddr[5:1] == 5'd2)
                          || (cpuAddr[5:1] == 5'd3);
    // Build #28: cond_wr_evt counts writes to $2200E (Condition CIR) —
    // confirms whether FBcc/FNOP detection actually fires.
    wire pfpd_cond_wr_evt = pfpd_fpu_cycle && !cpuRW
                         && (cpuAddr[7:0] == 8'h0E);
    reg [7:0] pfpd_total;
    reg [7:0] pfpd_periph_like;
    reg [7:0] pfpd_cond_wr_cnt;
    reg [7:0] pfpd_last_low;
    initial begin
        pfpd_total        = 8'd0;
        pfpd_periph_like  = 8'd0;
        pfpd_cond_wr_cnt  = 8'd0;
        pfpd_last_low     = 8'd0;
    end
    always @(posedge clk) begin
        if (pfpd_fpu_cycle) begin
            pfpd_last_low <= cpuAddr[7:0];
            if (pfpd_total != 8'hFF) pfpd_total <= pfpd_total + 8'd1;
            if (!pfpd_remap_target && pfpd_periph_like != 8'hFF)
                pfpd_periph_like <= pfpd_periph_like + 8'd1;
        end
        if (pfpd_cond_wr_evt && pfpd_cond_wr_cnt != 8'hFF)
            pfpd_cond_wr_cnt <= pfpd_cond_wr_cnt + 8'd1;
    end
    reg [31:0] pfpd_r;
    always @(posedge clk)
        pfpd_r <= {pfpd_total, pfpd_last_low, pfpd_periph_like, pfpd_cond_wr_cnt};

    altsource_probe #(
        .instance_id ("PFPD"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pfpd (.probe(pfpd_r), .source(), .source_clk(clk), .source_ena(1'b1));

endmodule
