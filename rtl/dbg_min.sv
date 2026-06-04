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
    // Build #69 additions for PSDH: 25-bit byte counter + 16-bit data word
    // so we can latch the first words of the F1 floppy download.
    input wire [24:0] ioctl_addr,
    input wire [15:0] ioctl_data,

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

    // PVBL RE-ENABLED for IORB-completion investigation (build #67).
    // Build #66 confirmed boot reaches Welcome dialog then hangs 5 min
    // before bomb. Mac OS drivers commonly schedule "I/O done" via VBL
    // tasks; if VBL stops firing during Welcome, drivers never complete
    // their IORBs, IOWait spins forever. PVBL counts card VBL IRQ
    // assertions — if card_irq_cnt freezes during the hang, that's
    // strong evidence VBL is the bottleneck.
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

    // PASC disabled build #35 — JTAG hub limit is ~20 ISSP/device for this
    // bitstream. Freed slot for PFPD/PFOQ/PFOV/PFLN (bug #6 FPU debug).
    // Not load-bearing for FPU bomb investigation.
    // altsource_probe #(
    //     .instance_id ("PASC"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pasc (.probe(pasc_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PAUD disabled build #35 — same fit-budget rationale as PASC above.
    // altsource_probe #(
    //     .instance_id ("PAUD"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_paud (.probe(paud_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PFLP RE-ENABLED for floppy-slowness investigation (per
    // scratch/floppy_slow_plan.md and scratch/snow_compare/baseline.md).
    // Snow baseline shows 57.8 KB/s sustained; LBMacTwo's 6-min boot
    // is ~7x slower, so PFLP's byte_cnt + miss_cnt are the primary
    // diagnostic — see the interpretation matrix in the plan.
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

    // PIWM disabled build #69 — confirmed healthy in builds #65-#68 (SDRAM
    // grants ~38k, byte deliveries growing). Frees budget for PIRE + PSDH.
    // PFLP still active as floppy sanity check.
    // altsource_probe #(
    //     .instance_id ("PIWM"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_piwm (.probe(piwm_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PIOA RE-ENABLED for IORB-completion investigation (build #66).
    // Floppy ruled out as slow (build #65 PFLP: 64 KB/s peak). Mac OS
    // is stuck in IOWait spin at PC=$40006C36 (per build #65 IF-PC
    // bursts). PIOA captures the (A0+$10) data address fetched right
    // after the C36 IF — that's the ioResult field of the IORB whose
    // driver never IODone's.
    altsource_probe #(
        .instance_id ("PIOA"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pioa (.probe(iowait_data_addr), .source(), .source_clk(clk), .source_ena(1'b1));

    reg [31:0] pioc_r;
    always @(posedge clk) pioc_r <= {16'd0, iowait_iter_cnt};
    // PIOC RE-ENABLED for IORB-completion investigation. Counts every
    // IF at $40006C36 (i.e. every IOWait poll iteration). Build #65
    // showed Mac OS spends most boot time spinning here; PIOC quantifies.
    altsource_probe #(
        .instance_id ("PIOC"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pioc (.probe(pioc_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PIR2 disabled build #70 — PIRE (added build #69) captures the same
    // address with a more useful filter (non-$0001 writes = actual driver
    // completions, instead of every write = mostly OS dispatches). Frees a
    // probe slot for PIRD (ioBuffer snoop) to verify the bytes Mac OS
    // actually receives match the disk-image content.
    // altsource_probe #(
    //     .instance_id ("PIR2"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pir2 (.probe(pir2_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PIR3 disabled build #71 — refnum was stable at $6B04 (positive,
    // file-refnum-like, not driver refnum) across all build #68-#70
    // captures. No further info to gain. Free a slot for the Mac OS
    // error-global probes (PERG/PERG2) so we can see WHY StandardLaunch
    // fails despite driver returning noErr.
    // altsource_probe #(
    //     .instance_id ("PIR3"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pir3 (.probe(pir3_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== IORB header probes (PIRH / PIRB / PIRR / PIRP) -- build #68 =======
    // Capture the OS-set fields of the .Sony IORB at the fixed low-memory
    // Params region anchored at $3A4. IORB layout (Mac IOParam):
    //   $00..$0F : queue, trap, completion, ...
    //   $10      : ioResult (16-bit)              <- IOWait poll at $3B4
    //   $18      : ioRefNum (16-bit)              <- -33 = .Sony
    //   $1A      : csCode   (16-bit)              <- WHAT operation?
    //   $20      : ioBuffer (32-bit)              <- WHERE to put data
    //   $24      : ioReqCount (32-bit)            <- HOW MUCH data
    //   $2E      : ioPosOffset (32-bit)           <- WHERE on disk
    //
    // The OS writes these fields BEFORE invoking the driver (so before the
    // IOWait spin starts and PIOA captures iowait_data_addr). Triggering on
    // writes to the STATIC $3A4-relative addresses catches the setup write
    // and latches it through the wedge. The probes hold the LATEST values,
    // which during the wedge are exactly the wedged operation's parameters.
    //
    // csCode meaning (Mac OS File Manager codes):
    //   $0001 = cmdRead   (.Sony asynchronous read)
    //   $0002 = cmdWrite  (.Sony asynchronous write)
    //   $0044 ($FF44 hex unsigned) = Reset / format-verify
    //   $0058 = DriveStatus
    //   $0001..0010 = generic Device Manager calls
    //
    // 32-bit fields (ioBuffer / ioReqCount / ioPosOffset) on a 16-bit data
    // port arrive as TWO consecutive 16-bit writes: HI at address+0, LO at
    // address+2. Each probe latches both halves separately and combines.
    //
    // Trigger: cpuAS_n falling edge AND !cpuRW AND cpuAddr matches.
    // Filter to RAM accesses (cpuFC != 3'b111 to exclude CPU/IACK space).

    wire pir_iorb_is_ram = (cpuFC != 3'b111);
    wire pir_aswr        = cpuAS_n_d && !cpuAS_n && !cpuRW && pir_iorb_is_ram;

    // PIRH: csCode (16-bit @ $3BE) + write count
    reg [15:0] pir_cscode;
    reg [15:0] pir_cscode_wr_cnt;
    initial begin pir_cscode = 16'd0; pir_cscode_wr_cnt = 16'd0; end
    always @(posedge clk) begin
        if (pir_aswr && cpuAddr == 32'h0000_03BE) begin
            pir_cscode        <= cpu_dout;
            pir_cscode_wr_cnt <= pir_cscode_wr_cnt + 16'd1;
        end
    end
    reg [31:0] pirh_r;
    always @(posedge clk) pirh_r <= {pir_cscode, pir_cscode_wr_cnt};

    altsource_probe #(
        .instance_id ("PIRH"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pirh (.probe(pirh_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PIRB: ioBuffer (32-bit @ $3C4/$3C6, longword as 2 16-bit writes)
    reg [15:0] pir_buf_hi;
    reg [15:0] pir_buf_lo;
    initial begin pir_buf_hi = 16'd0; pir_buf_lo = 16'd0; end
    always @(posedge clk) begin
        if (pir_aswr && cpuAddr == 32'h0000_03C4) pir_buf_hi <= cpu_dout;
        if (pir_aswr && cpuAddr == 32'h0000_03C6) pir_buf_lo <= cpu_dout;
    end
    reg [31:0] pirb_r;
    always @(posedge clk) pirb_r <= {pir_buf_hi, pir_buf_lo};

    altsource_probe #(
        .instance_id ("PIRB"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pirb (.probe(pirb_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PIRR: ioReqCount (32-bit @ $3C8/$3CA)
    reg [15:0] pir_req_hi;
    reg [15:0] pir_req_lo;
    initial begin pir_req_hi = 16'd0; pir_req_lo = 16'd0; end
    always @(posedge clk) begin
        if (pir_aswr && cpuAddr == 32'h0000_03C8) pir_req_hi <= cpu_dout;
        if (pir_aswr && cpuAddr == 32'h0000_03CA) pir_req_lo <= cpu_dout;
    end
    reg [31:0] pirr_r;
    always @(posedge clk) pirr_r <= {pir_req_hi, pir_req_lo};

    altsource_probe #(
        .instance_id ("PIRR"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pirr (.probe(pirr_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PIRP: ioPosOffset (32-bit @ $3D2/$3D4)
    reg [15:0] pir_pos_hi;
    reg [15:0] pir_pos_lo;
    initial begin pir_pos_hi = 16'd0; pir_pos_lo = 16'd0; end
    always @(posedge clk) begin
        if (pir_aswr && cpuAddr == 32'h0000_03D2) pir_pos_hi <= cpu_dout;
        if (pir_aswr && cpuAddr == 32'h0000_03D4) pir_pos_lo <= cpu_dout;
    end
    reg [31:0] pirp_r;
    always @(posedge clk) pirp_r <= {pir_pos_hi, pir_pos_lo};

    altsource_probe #(
        .instance_id ("PIRP"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pirp (.probe(pirp_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PIRE: ioResult completion-write probe (build #69) ================
    // PIR2 captures every write to $3B4 (the polled ioResult). In practice the
    // LAST write is always the OS's $0001 = "in progress" dispatch — so PIR2's
    // last_value is useless for diagnosing what the driver actually returns.
    //
    // PIRE filters: capture writes only when value != $0001. That value is
    // either the driver's COMPLETION (0 = noErr, or negative = error code) or
    // some other intermediate state. Layout:
    //   [31:16] last non-$0001 value seen at $3B4
    //   [15:0]  wrap16 count of such writes
    //
    // Sony driver error-code semantics (from SysErr.a):
    //   0          noErr
    //   -36 $FFDC  ioErr
    //   -66 $FFBE  noNybErr     (no transitions found)
    //   -67 $FFBD  noAdrMkErr   (no addr mark found)
    //   -68 $FFBC  dataVerErr   (read-verify compare failed)
    //   -69 $FFBB  badCksmErr   (addr mark checksum wrong)
    //   -70 $FFBA  badBtSlpErr  (bit-slip trailer wrong)
    //   -80 $FFB0  seekErr      (track number wrong)
    //   -81 $FFAF  sectNFErr    (sector not found)
    //
    // Filter to non-IACK cycles (cpuFC != 3'b111) for safety, same as PIRH/B/R/P.
    reg [15:0] pire_last_val;
    reg [15:0] pire_cnt;
    initial begin pire_last_val = 16'd0; pire_cnt = 16'd0; end
    always @(posedge clk) begin
        if (cpuAS_n_d && !cpuAS_n && !cpuRW && (cpuFC != 3'b111) &&
            cpuAddr == 32'h0000_03B4 && cpu_dout != 16'h0001) begin
            pire_last_val <= cpu_dout;
            pire_cnt      <= pire_cnt + 16'd1;
        end
    end
    reg [31:0] pire_r;
    always @(posedge clk) pire_r <= {pire_last_val, pire_cnt};

    altsource_probe #(
        .instance_id ("PIRE"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pire (.probe(pire_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PSDH / PSDI: HPS-download sanity check (build #69) ==============
    // The static audit confirmed the source-address mapping is correct on
    // paper (floppy.v's dskReadAddrInt=0 → SDRAM word 0x480000 = HPS F1
    // download word 0). PSDH captures the first 4 16-bit words actually
    // written by the HPS during F1 download — if they don't match the first
    // 8 bytes of Boot712.dsk (LK boot signature etc.), the HPS path is
    // corrupting bytes mid-download.
    //
    // dio_data has byte-swap: dio_data = {ioctl_data[7:0], ioctl_data[15:8]}.
    // So dio_data[15:8] = MSByte = file byte at even offset.
    //    dio_data[7:0]  = LSByte = file byte at odd offset.
    //
    // F1 (dio_index=1) → dio_a == {2'b01, dio_addr[18:0]} = 0x80000 + word_off
    // First 4 words → dio_addr[18:0] == 0, 1, 2, 3 → bytes 0..7 of Boot712.dsk
    //
    // PSDH layout: [31:16]=word_1 (bytes 2,3), [15:0]=word_0 (bytes 0,1)
    // PSDI layout: [31:16]=word_3 (bytes 6,7), [15:0]=word_2 (bytes 4,5)
    //
    // For HFS volumes:
    //   bytes 0..1 = boot signature ("LK" = 0x4C4B) if bootable
    //   bytes 2..3 = entry point offset
    //   bytes 4..5 = padding / version
    //   bytes 6..7 = padding
    // Boot712.dsk should show 0x4C4B in PSDH bytes 0..1.
    reg [15:0] psdh_w0, psdh_w1, psdh_w2, psdh_w3;
    initial begin psdh_w0=16'd0; psdh_w1=16'd0; psdh_w2=16'd0; psdh_w3=16'd0; end
    // ioctl_addr is the byte counter (25-bit). ioctl_addr[24:1] = word counter.
    // For F1 download (dio_index = 1), we want to latch words 0..3 of the file
    // (ignoring the dio_a base offset which is the SDRAM placement, not file
    // position). Since dio_addr[24:1] is monotonic across the download and
    // starts at 0 for each download instance, we use it directly.
    always @(posedge clk) begin
        if (ioctl_wr && (ioctl_idx == 8'd1)) begin
            // ioctl_data is little-endian (HPS pack convention); we byte-swap
            // to match dio_data's storage in SDRAM (MSByte = even file byte).
            //
            // BUILD #70 FIX: build #69 used case(ioctl_addr[3:1]) which wraps
            // every 16 bytes — every 16-byte boundary in the 800K download
            // overwrites psdh_w0..w3, so the FINAL 16 bytes (which are 0x00
            // for Boot712.dsk) won, producing all-zero captures. Compare the
            // FULL byte address now so each w-reg latches exactly once at
            // its target offset.
            if (ioctl_addr == 25'h00_00000) psdh_w0 <= {ioctl_data[7:0], ioctl_data[15:8]};
            if (ioctl_addr == 25'h00_00002) psdh_w1 <= {ioctl_data[7:0], ioctl_data[15:8]};
            if (ioctl_addr == 25'h00_00004) psdh_w2 <= {ioctl_data[7:0], ioctl_data[15:8]};
            if (ioctl_addr == 25'h00_00006) psdh_w3 <= {ioctl_data[7:0], ioctl_data[15:8]};
        end
    end
    reg [31:0] psdh_r;
    reg [31:0] psdi_r;
    always @(posedge clk) begin
        psdh_r <= {psdh_w1, psdh_w0};
        psdi_r <= {psdh_w3, psdh_w2};
    end

    altsource_probe #(
        .instance_id ("PSDH"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psdh (.probe(psdh_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PIRD: ioBuffer-write snoop (build #70) =========================
    // Build #69 PIRE confirmed driver completes reads with noErr (301
    // successful ops across 6-min boot). So the wedge isn't sector-level
    // decode — it's at the HFS layer. Hypothesis: the BYTES Mac OS receives
    // for a successfully-decoded sector don't match what Mac OS expects.
    //
    // PIRD snoops writes to the LAST captured ioBuffer address (from PIRB).
    // Each successful _Read populates ioBuffer..(ioBuffer+ioReqCount-1) with
    // the sector data. We capture the FIRST 4 16-bit words at the buffer
    // address = bytes 0..7 of the most-recently-completed read.
    //
    // For the t=360s wedge at ioPosOffset=$42200 (sector 529) with ioBuffer
    // =$6610: expected file bytes at $42200 are 5F 22 52 08 E9 00 02 00
    // (per scratch/build68_sector529_inspection.md).
    //
    // PIRD layout: [31:16] = word_1 at buffer+2 (bytes 2,3)
    //              [15:0]  = word_0 at buffer+0 (bytes 0,1)
    // PIRJ layout: [31:16] = word_3 at buffer+6 (bytes 6,7)
    //              [15:0]  = word_2 at buffer+4 (bytes 4,5)
    // (PIRJ omitted for now — fit budget; PIRD alone gives the first
    // distinguishing bytes.)
    //
    // The buffer address comes from the most-recently captured ioBuffer via
    // PIRB. pir_buf_hi+pir_buf_lo is the 32-bit address.
    wire [31:0] pird_target = {pir_buf_hi, pir_buf_lo};
    // Only snoop when pird_target is non-zero AND looks like a heap address
    // (low 24 bits, NOT high RAM/ROM area). Sanity guard against capturing
    // wild writes when ioBuffer has just been initialised.
    wire pird_valid_target = (pird_target != 32'h0) &&
                              (pird_target[31:24] == 8'h00) &&
                              (pird_target[23:20] != 4'hF);
    // Word-aligned match: cpuAddr in [pird_target, pird_target+8) AND
    // cpuAddr is word-aligned (cpuAddr[0]=0; word writes on 68020).
    wire pird_match = cpuAS_n_d && !cpuAS_n && !cpuRW &&
                      (cpuFC != 3'b111) && pird_valid_target &&
                      (cpuAddr[31:3] == pird_target[31:3]) &&
                      !cpuAddr[0];
    reg [15:0] pird_w0, pird_w1;
    initial begin pird_w0 = 16'd0; pird_w1 = 16'd0; end
    always @(posedge clk) begin
        if (pird_match) begin
            case (cpuAddr[2:1])
                2'd0: pird_w0 <= cpu_dout;   // bytes target+0..1
                2'd1: pird_w1 <= cpu_dout;   // bytes target+2..3
                default: ;                    // target+4..7 — bytes 4-7
            endcase
        end
    end
    reg [31:0] pird_r;
    always @(posedge clk) pird_r <= {pird_w1, pird_w0};

    // PIRD disabled build #71 — confirmed at t=360 sector 529 that the
    // EVEN bytes in ioBuffer match the file (5F, 52 = file content). Data
    // path is clean; wedge is at HFS/ProcessMgr layer. Free a slot.
    // altsource_probe #(
    //     .instance_id ("PIRD"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pird (.probe(pird_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PERG: Mac OS error globals (build #71) ==========================
    // Build #70 confirmed the data-path is clean: HPS download intact, driver
    // returns noErr 301×, ioBuffer bytes match the file. The wedge must be
    // at the HFS / Process Manager / Resource Manager level. The likely
    // failure point is StandardLaunch in ProcessMgr/SegmentLoaderPatches.c:
    //   rfn = HOpenResFile(...)
    //   launchResults->LaunchError = RESERR
    //   if (rfn == (-1)) return;
    // ResErr is at low-mem $A60 (per Interfaces/AIncludes/ToolUtils.a:169).
    // If the resource fork open fails, ResErr holds the underlying error
    // code (e.g., -39 = eofErr, -49 = opWrErr, -50 = paramErr, -108 =
    // memFullErr, -192 = resNotFound, -193 = resFNotFound, etc.).
    //
    // DskErr at $142 (SysEqu.a:1424) is the last disk routine result code.
    // Mirrors what the .Sony driver returned but at a system-wide level.
    //
    // Capture all writes to these two addresses with last_value + wrap16 cnt.
    //
    // Quartus truncates altsource_probe instance_id to 4 chars (per the
    // PMEM/PMEM2 → PMEM/MEM2 pattern). Use 4-char names PRSR and PDSE.
    //
    // PRSR layout:  [31:16] last_value @ $0A60 (ResErr)
    //               [15:0]  wr_cnt(wrap16)
    // PDSE layout:  [31:16] last_value @ $0142 (DskErr)
    //               [15:0]  wr_cnt(wrap16)
    wire perg_aswr = cpuAS_n_d && !cpuAS_n && !cpuRW && (cpuFC != 3'b111);

    reg [15:0] perg_reserr_last;
    reg [15:0] perg_reserr_cnt;
    initial begin perg_reserr_last = 16'd0; perg_reserr_cnt = 16'd0; end
    always @(posedge clk) begin
        if (perg_aswr && cpuAddr == 32'h0000_0A60) begin
            perg_reserr_last <= cpu_dout;
            perg_reserr_cnt  <= perg_reserr_cnt + 16'd1;
        end
    end
    reg [31:0] perg_r;
    always @(posedge clk) perg_r <= {perg_reserr_last, perg_reserr_cnt};

    altsource_probe #(
        .instance_id ("PRSR"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_prsr (.probe(perg_r), .source(), .source_clk(clk), .source_ena(1'b1));

    reg [15:0] perg2_dskerr_last;
    reg [15:0] perg2_dskerr_cnt;
    initial begin perg2_dskerr_last = 16'd0; perg2_dskerr_cnt = 16'd0; end
    always @(posedge clk) begin
        if (perg_aswr && cpuAddr == 32'h0000_0142) begin
            perg2_dskerr_last <= cpu_dout;
            perg2_dskerr_cnt  <= perg2_dskerr_cnt + 16'd1;
        end
    end
    reg [31:0] perg2_r;
    always @(posedge clk) perg2_r <= {perg2_dskerr_last, perg2_dskerr_cnt};

    // PDSE disabled build #72 — build #71 showed DskErr stuck at -65
    // (offLinErr) from the early external-drive probe. After 8 initial
    // writes, no further DskErr writes. No more info to extract.
    // altsource_probe #(
    //     .instance_id ("PDSE"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pdse (.probe(perg2_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PRSF: FILTERED ResErr probe (build #72) =========================
    // Build #71's PRSR showed Mac-ResErr last=$0000 with wr_cnt=727. So the
    // OS writes ResErr 727 times but the LAST write is noErr. That's
    // because Mac OS resets ResErr to 0 at the start of many Resource
    // Manager calls — these noErr-resets overwrite any error events.
    //
    // PRSF filters: capture writes only when cpu_dout != 0. That catches
    // the actual error events before they're overwritten.
    //
    // Same layout as PRSR:
    //   [31:16] last non-zero value written at $A60
    //   [15:0]  wrap16 count of such writes
    //
    // If PRSF.cnt = 0 across boot, ResErr never went non-zero -> Resource
    // Manager never saw an error. Bomb path must be FSMakeFSSpec (catalog
    // walk) failing, not HOpenResFile (resource fork open) failing.
    //
    // If PRSF.cnt > 0 + value = -192/-193/etc, we know exactly which
    // resource error propagated to launchResults->LaunchError.
    reg [15:0] prsf_last_val;
    reg [15:0] prsf_cnt;
    initial begin prsf_last_val = 16'd0; prsf_cnt = 16'd0; end
    always @(posedge clk) begin
        if (perg_aswr && cpuAddr == 32'h0000_0A60 && cpu_dout != 16'h0000) begin
            prsf_last_val <= cpu_dout;
            prsf_cnt      <= prsf_cnt + 16'd1;
        end
    end
    reg [31:0] prsf_r;
    always @(posedge clk) prsf_r <= {prsf_last_val, prsf_cnt};

    altsource_probe #(
        .instance_id ("PRSF"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_prsf (.probe(prsf_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PSDI (bytes 4..7 of file) deferred — keeping PSDH only to stay within
    // ~20-probe JTAG budget. PSDH bytes 0..3 catches the boot-signature
    // mismatch case, which is sufficient for first-pass HPS-download sanity.
    // Re-enable if PSDH shows correct bytes but we still suspect later-file
    // corruption.
    // altsource_probe #(
    //     .instance_id ("PSDI"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psdi (.probe(psdi_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PFLT (floppy version) RE-ENABLED for IORB-completion investigation
    // (build #67). If the .Sony floppy driver is the one not completing
    // its IORB, it might be either: (a) seeking the same track over and
    // over (CRC retry) — step_cnt grows; (b) stuck mid-sector searching
    // for an address mark — step_cnt static. flp_track + step_cnt tell
    // us which pattern.
    altsource_probe #(
        .instance_id ("PFLT"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pflt (.probe(pflt_r), .source(), .source_clk(clk), .source_ena(1'b1));

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
    // Build #35 PFRR upgrade: distinguish FBcc cond_word reads from prim
    // Response reads. Builds #28-#34 always showed last_resp=0x0000 — that's
    // the FBcc/FBF cond word (correctly evaluated false), not the prim path.
    // The prim Response value (cir_response_prim, currently 0x0900 NULL) is
    // what TG68's cp_idle_resp decodes — if the FPU sends a shape TG68 can't
    // recognize, it routes to F-line and System 6 bombs with dsLineFErr.
    //
    // Mechanism: track a sticky "cond-pending" flag. Set by any write to
    // Condition CIR ($0E). Cleared by the next Response CIR read. That read
    // is classified as "FBcc" (cond_word); all other Response reads are
    // "prim" reads.
    //
    // Layout:
    //   [31:16] pfrr_last_resp        — cpu_din at AS rising, any Response read
    //   [15]    pfrr_last_was_fbcc    — 1=last read was FBcc cond_word path
    //                                   0=last read was prim path
    //   [14:8]  pfrr_prim_rd_cnt      — 7-bit count of prim Response reads
    //                                   (FBcc reads counted via PFPD Cond-wr)
    //   [7:0]   pfrr_ctrl_wr_cnt      — Control CIR writes (kept from #28)
    wire pfrr_cond_wr  = cpuAS_n_d && !cpuAS_n && !cpuRW &&
                         (cpuFC == 3'b111) && (cpuAddr == 32'h0002200E);
    reg        pfrr_fbcc_pending;
    reg        pfrr_read_pending;
    reg        pfrr_read_was_fbcc;
    reg [15:0] pfrr_last_resp;
    reg        pfrr_last_was_fbcc;
    reg [6:0]  pfrr_prim_rd_cnt;
    reg [7:0]  pfrr_ctrl_wr_cnt;
    initial begin
        pfrr_fbcc_pending  = 1'b0;
        pfrr_read_pending  = 1'b0;
        pfrr_read_was_fbcc = 1'b0;
        pfrr_last_resp     = 16'd0;
        pfrr_last_was_fbcc = 1'b0;
        pfrr_prim_rd_cnt   = 7'd0;
        pfrr_ctrl_wr_cnt   = 8'd0;
    end
    always @(posedge clk) begin
        if (pfrr_cond_wr) pfrr_fbcc_pending <= 1'b1;
        if (pfrr_resp_rd) begin
            pfrr_read_pending  <= 1'b1;
            pfrr_read_was_fbcc <= pfrr_fbcc_pending;
            if (pfrr_fbcc_pending) begin
                pfrr_fbcc_pending <= 1'b0;
            end else begin
                if (pfrr_prim_rd_cnt != 7'h7F)
                    pfrr_prim_rd_cnt <= pfrr_prim_rd_cnt + 7'd1;
            end
        end
        if (pfrr_read_pending && !cpuAS_n_d && cpuAS_n) begin
            // AS rising edge: bus cycle ends. Capture data the CPU saw.
            pfrr_last_resp     <= cpu_din;
            pfrr_last_was_fbcc <= pfrr_read_was_fbcc;
            pfrr_read_pending  <= 1'b0;
        end
        if (pfrr_ctrl_wr) pfrr_ctrl_wr_cnt <= pfrr_ctrl_wr_cnt + 8'd1;
    end
    reg [31:0] pfrr_r;
    always @(posedge clk)
        pfrr_r <= {pfrr_last_resp, pfrr_last_was_fbcc,
                   pfrr_prim_rd_cnt, pfrr_ctrl_wr_cnt};

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

    // PFRR / PFRW disabled for build #68 — FPU confirmed healthy by Snow
    // checkpoint cross-check (bug #6 floppy pivot). Frees fit budget for the
    // IORB-header probes (PIRH/PIRB/PIRR/PIRP) that pin down what the .Sony
    // driver is actually doing during the Welcome hang.
    // altsource_probe #(
    //     .instance_id ("PFRR"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfrr (.probe(pfrr_r), .source(), .source_clk(clk), .source_ena(1'b1));
    //
    // altsource_probe #(
    //     .instance_id ("PFRW"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfrw (.probe(pfrw_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PFST disabled build #69 — FPU CIR FSM confirmed healthy by Snow
    // checkpoint cross-check. Frees budget for PIRE + PSDH.
    // altsource_probe #(
    //     .instance_id ("PFST"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfst (.probe(pfst_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PCAK retired for floppy-slow investigation: confirmed = 0 (CPU
    // never writes Control CIR $22002 in this boot phase). Freeing fit
    // budget for PFLP/PIWM.
    // altsource_probe #(
    //     .instance_id ("PCAK"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pcak (.probe(pcak_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    // PFPD retired for floppy-slow investigation: FPU detect protocol
    // confirmed working — Snow cross-check shows our lowmem agrees at
    // FPU detect checkpoint. Freeing fit budget for PFLP/PIWM.
    // altsource_probe #(
    //     .instance_id ("PFPD"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfpd (.probe(pfpd_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PFOQ: PC of last cpGEN-class OpWord write (build #35, bug #6) ====
    // PFBE retired — it always showed $40002430 (the SystemError dialog setup
    // epilogue, a fixed ROM address). Replace its slot with the PC of the
    // F-line instruction that issued the LAST write to OpWord CIR ($00022008).
    //
    // Approximation: the TG68's coprocessor microcode writes OpWord shortly
    // after fetching the F-line instruction. Latch the most recent supervisor
    // IF address (`pfoq_last_if_pc`), then snapshot it at each OpWord write.
    // That snapshot is a few cycles off but lands within the same instruction.
    //
    // Combined with PFOV (OpWord values), this names exactly which F-line
    // opcode in System 6 / System 7 was the last one before the bomb.
    //
    // Layout:
    //   [31:0] pfoq_opword_pc — IF-PC of the F-line instruction whose
    //                            OpWord write was most recently captured.
    //                            0 = no OpWord write seen yet.
    wire pfoq_is_if_super = cpuAS_n_d && !cpuAS_n && cpuRW
                         && (cpuFC == 3'b110);  // supervisor IF only
    reg [31:0] pfoq_last_if_pc;
    reg [31:0] pfoq_opword_pc;
    initial begin
        pfoq_last_if_pc = 32'h0;
        pfoq_opword_pc  = 32'h0;
    end
    always @(posedge clk) begin
        if (pfoq_is_if_super) pfoq_last_if_pc <= cpuAddr;
        if (pfrw_opw_wr)      pfoq_opword_pc  <= pfoq_last_if_pc;
    end
    reg [31:0] pfoq_r;
    always @(posedge clk)
        pfoq_r <= pfoq_opword_pc;

    // PFOQ disabled for build #68 — same rationale as PFRR/PFRW above.
    // altsource_probe #(
    //     .instance_id ("PFOQ"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfoq (.probe(pfoq_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PFOV: last 2 cpGEN-class OpWord VALUES (build #35, bug #6) =======
    // PFCS retired — build #33 confirmed only one $A9C9 fetch in entire boot
    // (at $400011DC, an unrelated ROM dispatcher), so the bomb does NOT use
    // the _SysError A-trap path. Repurpose its slot to capture the actual
    // OpWord values the CPU wrote to OpWord CIR ($00022008).
    //
    // For TG68/68020 coprocessor protocol the OpWord written to OpWord CIR
    // is the 1st extension word of the F-line instruction. Its encoding
    // identifies the FPU op class:
    //   FBcc / FNOP        — written to Condition CIR, NOT here. (FNOP =
    //                        FBF.W with op_byte=$01, cond=$00.)
    //   cpGEN math         — OpWord = "0000 cccc qqqq dddd" with op spec.
    //                        Followed by Command CIR write of full instr.
    //   cpSAVE             — OpWord = "0010 0aaa aaaa aaaa" (EA encoding).
    //   cpRESTORE          — OpWord = "0011 0aaa aaaa aaaa" (EA encoding).
    //
    // The bomb path in Sys 6 (dsLineFErr) probably routes through cp_idle_resp
    // after some OpWord. Seeing the LAST 2 OpWord values + PFOQ PC pinpoints
    // the responsible F-line instruction.
    //
    // Layout:
    //   [31:16] pfov_last — most recent OpWord write value
    //   [15:0]  pfov_prev — previous OpWord write value
    reg [15:0] pfov_last;
    reg [15:0] pfov_prev;
    initial begin
        pfov_last = 16'd0;
        pfov_prev = 16'd0;
    end
    always @(posedge clk) begin
        if (pfrw_opw_wr) begin
            pfov_prev <= pfov_last;
            pfov_last <= cpu_dout;
        end
    end
    reg [31:0] pfov_r;
    always @(posedge clk)
        pfov_r <= {pfov_last, pfov_prev};

    // PFOV retired for floppy-slow investigation: opwords confirmed as
    // $F35F/$F327 (both cpBcc.L) across builds. Freeing fit budget for
    // PFLP/PIWM.
    // altsource_probe #(
    //     .instance_id ("PFOV"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfov (.probe(pfov_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PHWC: HWCfgFlags ($0B22) write tracker (build #37, bug #6) =======
    // ROM disassembly at $4000D604 (FRESTORE guard) reveals: Mac II ROM
    // tests bit 12 (= byte bit 4 of high byte at $0B22 — hwCbFPU) before
    // doing FRESTORE during context-clear. Build #36 capture confirmed
    // FRESTORE executes => hwCbFPU IS SET at that point.
    //
    // But the bomb still fires later. So either:
    //   (a) hwCbFPU gets cleared by some later code (rare but possible if
    //       an init/driver thinks FPU is broken)
    //   (b) The bomb path uses a DIFFERENT detection than HWCfgFlags
    //
    // PHWC catches case (a). Tracks any byte write to $00000B22 (the high
    // byte of HWCfgFlags word — that's where bit 12 lives). Captures the
    // writer's IF-PC and the byte value written.
    //
    // Layout:
    //   [31:24] phwc_count       — sat-8 count of writes to $0B22
    //   [23:0]  phwc_last_pc[23:0] — writer PC (high byte $40 for ROM,
    //                                 $00 for RAM, inferable from value)
    //   ... but we ALSO want the value. Pack differently:
    //   Actually: 2 reads — keep this probe focused on PC + count + bit4.
    //
    // Better layout:
    //   [31:8] phwc_last_pc[23:0] — writer PC
    //   [7:0]  composite          — bit7=bit4 of last value (hwCbFPU),
    //                              bits[6:0] = sat-7 count
    wire phwc_event = cpuAS_n_d && !cpuAS_n && !cpuRW
                   && (cpuFC == 3'b101)            // supervisor data write
                   && (cpuAddr == 32'h0000_0B22);  // HWCfgFlags high byte
    reg [31:0] phwc_last_pc;
    reg [31:0] phwc_pending_pc;
    reg        phwc_pending_armed;
    reg [6:0]  phwc_count;
    reg        phwc_last_bit4;
    reg [7:0]  phwc_last_val;
    initial begin
        phwc_last_pc        = 32'h0;
        phwc_pending_pc     = 32'h0;
        phwc_pending_armed  = 1'b0;
        phwc_count          = 7'd0;
        phwc_last_bit4      = 1'b0;
        phwc_last_val       = 8'd0;
    end
    // Reuse pfoq_last_if_pc / pfoq_is_if_super for writer PC (latest super IF).
    always @(posedge clk) begin
        if (phwc_event) begin
            phwc_pending_pc    <= pfoq_last_if_pc;
            phwc_pending_armed <= 1'b1;
            if (phwc_count != 7'h7F) phwc_count <= phwc_count + 7'd1;
        end
        // Capture data at AS rising edge (when bus cycle completes)
        if (phwc_pending_armed && !cpuAS_n_d && cpuAS_n) begin
            phwc_last_pc       <= phwc_pending_pc;
            // cpu_dout high byte for byte write at $0B22 — TG68 places byte
            // on the appropriate bus lane based on UDS/LDS. For byte write
            // to even address $0B22, the data is on UDS (cpu_dout[15:8]).
            // Actually $0B22 = 32'b0000_..._1011_0010_0010 -> LSB of addr=0
            // bit 0 = 0 => even byte = UDS active = upper byte
            phwc_last_val      <= cpu_dout[15:8];
            phwc_last_bit4     <= cpu_dout[12];  // bit 12 of WORD = bit 4 of HIGH BYTE
            phwc_pending_armed <= 1'b0;
        end
    end
    reg [31:0] phwc_r;
    always @(posedge clk)
        phwc_r <= {phwc_last_pc[23:0], phwc_last_bit4, phwc_count};

    // PHWC retired build #63 — answered (hwCbFPU bit consistently = 1 across
    // many builds; no new info from continued monitoring). Slot freed for
    // PFLT (F-line trap source PC capture).
    // altsource_probe #(
    //     .instance_id ("PHWC"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_phwc (.probe(phwc_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PSFW: FPU Save-CIR read capture (build #45, bug #6) ==============
    // Captures fpu_data_out[15:0] every time the CPU does a bus read of the
    // FPU Save CIR (cpuAddr[5:1]==2). This is the format word the CPU
    // physically receives from the FPU during FSAVE. Snow trace shows Mac
    // OS at $00014072 does CMPI.W #$1F18, D0 — so this probe should show
    // $1F18 in [31:16] if our FPU correctly delivers the format word.
    // Anything else (e.g., $0000, $00B4, $1FB4) explains the bomb.
    //
    // Layout:
    //   [31:16] psfw_last_val   — last cpu_din[15:0] at Save CIR read (the
    //                              actual word the CPU received from FPU)
    //   [15:8]  psfw_last_pc[7:0] — low byte of writer PC for context (low
    //                              byte of $1406C is $6C, of $4000D612 is $12)
    //   [7:0]   psfw_count       — sat-8 count of Save CIR reads
    //
    // NOTE: capture at AS rising edge (end of bus cycle) so cpu_din has
    // the settled read result. Capturing during cycle catches in-progress
    // bus state which may be undefined.
    wire psfw_in_cycle = !cpuAS_n && cpuRW && selectFPU
                      && (cpuAddr[5:1] == 5'd2);
    reg psfw_in_cycle_d;
    reg [15:0] psfw_last_val;
    reg [7:0]  psfw_last_pc_lo;
    reg [7:0]  psfw_count;
    initial begin
        psfw_in_cycle_d = 1'b0;
        psfw_last_val   = 16'h0;
        psfw_last_pc_lo = 8'h0;
        psfw_count      = 8'h0;
    end
    always @(posedge clk) begin
        psfw_in_cycle_d <= psfw_in_cycle;
        // Capture at FALLING edge of psfw_in_cycle (AS rising = end of
        // bus cycle), so cpu_din has the settled value.
        if (!psfw_in_cycle && psfw_in_cycle_d) begin
            psfw_last_val   <= cpu_din;
            psfw_last_pc_lo <= pfoq_last_if_pc[7:0];
            if (psfw_count != 8'hFF) psfw_count <= psfw_count + 8'd1;
        end
    end
    reg [31:0] psfw_r;
    always @(posedge clk)
        psfw_r <= {psfw_last_val, psfw_last_pc_lo, psfw_count};

    // PSFW disabled for build #49 — FPU side confirmed correct (delivered
    // $1F18); freeing fit budget for widened PMTY. Re-enable if needed.
    // altsource_probe #(
    //     .instance_id ("PSFW"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psfw (.probe(psfw_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PSFM: FPU FSAVE format-word write capture (build #46, bug #6) ====
    // Build #45 version saturated at 65535 with any-stack-write filter.
    // Build #46: capture WRITES whose value == $1F18 (the expected format
    // word). This value is rare in normal traffic — if it fires, it's
    // almost certainly the FSAVE format-word write. Captures the address
    // of the write so we know WHERE the format word landed in memory.
    //
    // Also captures the LAST write address overall (sat-8 count) as a
    // sanity check that the CPU IS doing many writes.
    //
    // Layout:
    //   [31:16] psfm_1f18_addr_lo  — low 16 bits of the address where the
    //                                most recent $1F18 write went. Snow's
    //                                A7_post is $003FFBBC so we expect
    //                                low16 == $FBBC if FSAVE put $1F18
    //                                in the format-word slot.
    //   [15:8]  psfm_1f18_count    — sat-8 count of $1F18 writes
    //   [7:0]   psfm_writes_count  — sat-8 count of ANY stack write
    wire psfm_any_write = !cpuAS_n && !cpuRW
                       && (cpuAddr[31:16] == 16'h003F);
    wire psfm_1f18_event = psfm_any_write
                       && (cpu_dout[15:0] == 16'h1F18);
    reg psfm_any_d, psfm_1f18_d;
    reg [15:0] psfm_1f18_addr_lo;
    reg [7:0]  psfm_1f18_count;
    reg [7:0]  psfm_writes_count;
    initial begin
        psfm_any_d         = 1'b0;
        psfm_1f18_d        = 1'b0;
        psfm_1f18_addr_lo  = 16'h0;
        psfm_1f18_count    = 8'h0;
        psfm_writes_count  = 8'h0;
    end
    always @(posedge clk) begin
        psfm_any_d  <= psfm_any_write;
        psfm_1f18_d <= psfm_1f18_event;
        if (psfm_1f18_event && !psfm_1f18_d) begin
            psfm_1f18_addr_lo <= cpuAddr[15:0];
            if (psfm_1f18_count != 8'hFF) psfm_1f18_count <= psfm_1f18_count + 8'd1;
        end
        if (psfm_any_write && !psfm_any_d) begin
            if (psfm_writes_count != 8'hFF) psfm_writes_count <= psfm_writes_count + 8'd1;
        end
    end
    reg [31:0] psfm_r;
    always @(posedge clk)
        psfm_r <= {psfm_1f18_addr_lo, psfm_1f18_count, psfm_writes_count};

    // PSFM disabled for build #49 — FPU side confirmed correct (104 $1F18
    // stack writes counted); freeing fit budget for widened PMTY.
    // altsource_probe #(
    //     .instance_id ("PSFM"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_psfm (.probe(psfm_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PMTY: $0D28 trap-pointer writer (build #57, bug #6 phase 12) =====
    // Snow's $0D28 = $40806486 (ROM pointer). LBMacTwo's $0D28 = $00008CD8
    // (string-area pointer). The dispatcher at $4D40 does
    // MOVEA.L ($0D28).W, A0; JMP (A0) — wrong pointer → jump into string.
    //
    // Capture cpu_dout high word at last write to $0D28 + writer PC high.
    // This tells us:
    //   - If high word = $4080: write was correct ($4080 6486 ROM addr) →
    //     SDRAM byte path is corrupting on read.
    //   - If high word = $0000: write itself was bad ($0000 8CD8 was the
    //     written value) → caller has bad data, look at disasm.
    //
    // Layout:
    //   [31:16] = cpu_dout[15:0] at last write to $0D28-$0D29 (high word
    //             of 32-bit value being written)
    //   [15:0]  = pfoq_last_if_pc[15:0] (low 16 bits of writer PC)
    wire pmty_d28_write = !cpuAS_n && !cpuRW
                       && (cpuAddr == 32'h0000_0D28);
    reg pmty_d28_d;
    reg [15:0] pmty_d28_hword, pmty_d28_pc_lo;
    initial begin
        pmty_d28_d      = 1'b0;
        pmty_d28_hword  = 16'h0;
        pmty_d28_pc_lo  = 16'h0;
    end
    always @(posedge clk) begin
        pmty_d28_d <= pmty_d28_write;
        if (pmty_d28_write && !pmty_d28_d) begin
            pmty_d28_hword <= cpu_dout[15:0];
            pmty_d28_pc_lo <= pfoq_last_if_pc[15:0];
        end
    end
    reg [31:0] pmty_r;
    always @(posedge clk)
        pmty_r <= {pmty_d28_hword, pmty_d28_pc_lo};

    // PMTY retired build #59 — purpose (verify $0D28 write goes through) is
    // fully answered by PD28 read probe + Snow comparison in build #58. Slot
    // freed for PFCS (_SysError caller capture).
    // altsource_probe #(
    //     .instance_id ("PMTY"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pmty (.probe(pmty_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PFLN: F-line vector fetch detector (build #35, bug #6) ===========
    // RETIRED build #37 — build #36 confirmed PFLN.count = 8 (constant) across
    // boot, so F-line trap entry is not the bomb mechanism. Freed slot for PHWC.
    /*
    // PFTR retired — its FC=5+addr<$400 filter caught low-mem global reads
    // (MBState @ $172, IORB ioResult @ $3B4) too aggressively, drowning real
    // vector fetches in noise. Replace with a TIGHT filter: only the F-line
    // vector address ($000000B0 / $000000B2 — vector 11, the exception that
    // System 6's dsLineFErr bomb is the unhandled form of). Plus keep berr
    // counter (smaller — was useful at zero across all bug-#6 builds).
    //
    // Mechanism: 68020 with VBR=0 fetches the F-line handler address from
    // $000000B0 (longword) on F-line exception entry. TG68 splits longword
    // reads into two 16-bit accesses at $B0 then $B2; this fires on both
    // and captures the LAST cpu_din (which is $B2 — low 16 of handler addr).
    //
    // Layout:
    //   [31:24] pfln_count    — sat-8 count of $B0+$B2 reads. count>0 means
    //                            the F-line exception entry path was taken.
    //                            Compare across rounds: increment between
    //                            T+5min and T+7min = bomb is via F-line.
    //   [23:16] pfln_berr_cnt — sat-8 count of berr rising edges.
    //   [15:0]  pfln_last_din — last cpu_din from $B0/$B2 (low 16 of handler
    //                            address — usually $4xxx for ROM handler or
    //                            $00xx for installed RAM handler).
    wire pfln_vec_b0_rd = cpuAS_n_d && !cpuAS_n && cpuRW
                       && (cpuFC == 3'b101)             // supervisor data
                       && (cpuAddr[31:2] == 30'h0000002C); // $B0 or $B2

    reg [7:0]  pfln_count;
    reg [7:0]  pfln_berr_cnt;
    reg        pfln_berr_d;
    reg [15:0] pfln_last_din;
    reg        pfln_pending;
    initial begin
        pfln_count    = 8'd0;
        pfln_berr_cnt = 8'd0;
        pfln_berr_d   = 1'b0;
        pfln_last_din = 16'd0;
        pfln_pending  = 1'b0;
    end
    always @(posedge clk) begin
        pfln_berr_d <= berr;
        if (pfln_vec_b0_rd) begin
            pfln_pending <= 1'b1;
            if (pfln_count != 8'hFF) pfln_count <= pfln_count + 8'd1;
        end
        if (pfln_pending && !cpuAS_n_d && cpuAS_n) begin
            pfln_last_din <= cpu_din;
            pfln_pending  <= 1'b0;
        end
        if (berr && !pfln_berr_d && pfln_berr_cnt != 8'hFF)
            pfln_berr_cnt <= pfln_berr_cnt + 8'd1;
    end
    reg [31:0] pfln_r;
    always @(posedge clk)
        pfln_r <= {pfln_count, pfln_berr_cnt, pfln_last_din};

    // altsource_probe #(
    //     .instance_id ("PFLN"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfln (.probe(pfln_r), .source(), .source_clk(clk), .source_ena(1'b1));
    */

    // ==== PD24 / PD28: low-mem longword read capture (build #58, bug #6) ====
    // Step 1 of SDRAM-corruption diagnostic from coprocessor_missing_handoff.md.
    //   PD28: longword at $00000D28 — known bad (reads $00008CD8, should be
    //         Snow's $40806486). Sanity-check the bad read directly.
    //   PD24: longword at $00000D24 — Snow says $000028FC. If we match Snow
    //         here, the corruption is SPECIFIC to $0D28 (aliasing/coincidence).
    //         If different, the corruption is SYSTEMIC across low-mem
    //         longwords (likely SDRAM controller bug — addr not latched at
    //         T=0, so column phase at T=3 uses changed addr).
    //
    // Each probe latches cpu_din at AS-rising (end of bus cycle) for both
    // halves of the longword. cpuAddr+0 -> high16, cpuAddr+2 -> low16.
    // Layout: {high16, low16} = full 32-bit longword value.
    //
    // Filter: cpuRW=1 (read). No FC filter — both supervisor data (FC=5)
    // and trap-dispatcher reads through the indirect MOVEA.L (...).W path
    // hit these low-mem globals; we want to see them all.

    // PD28: longword read of $00000D28-$00000D2B
    wire pd28_hi_in = !cpuAS_n && cpuRW && (cpuAddr == 32'h0000_0D28);
    wire pd28_lo_in = !cpuAS_n && cpuRW && (cpuAddr == 32'h0000_0D2A);
    reg  pd28_hi_d, pd28_lo_d;
    reg [15:0] pd28_hi, pd28_lo;
    initial begin
        pd28_hi_d = 1'b0; pd28_lo_d = 1'b0;
        pd28_hi   = 16'h0; pd28_lo   = 16'h0;
    end
    always @(posedge clk) begin
        pd28_hi_d <= pd28_hi_in;
        pd28_lo_d <= pd28_lo_in;
        // Latch at falling edge of in_cycle (AS-rising = end of bus cycle):
        // cpu_din has the settled read result by then.
        if (!pd28_hi_in && pd28_hi_d) pd28_hi <= cpu_din;
        if (!pd28_lo_in && pd28_lo_d) pd28_lo <= cpu_din;
    end
    reg [31:0] pd28_r;
    always @(posedge clk) pd28_r <= {pd28_hi, pd28_lo};

    // PD28 retired build #62 — SDRAM corruption disproven in #58 + reconfirmed
    // in #59-#61. Slot freed for PVCF (F-line vector RAM read).
    // altsource_probe #(
    //     .instance_id ("PD28"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pd28 (.probe(pd28_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // PD24: longword read of $00000D24-$00000D27
    wire pd24_hi_in = !cpuAS_n && cpuRW && (cpuAddr == 32'h0000_0D24);
    wire pd24_lo_in = !cpuAS_n && cpuRW && (cpuAddr == 32'h0000_0D26);
    reg  pd24_hi_d, pd24_lo_d;
    reg [15:0] pd24_hi, pd24_lo;
    initial begin
        pd24_hi_d = 1'b0; pd24_lo_d = 1'b0;
        pd24_hi   = 16'h0; pd24_lo   = 16'h0;
    end
    always @(posedge clk) begin
        pd24_hi_d <= pd24_hi_in;
        pd24_lo_d <= pd24_lo_in;
        if (!pd24_hi_in && pd24_hi_d) pd24_hi <= cpu_din;
        if (!pd24_lo_in && pd24_lo_d) pd24_lo <= cpu_din;
    end
    reg [31:0] pd24_r;
    always @(posedge clk) pd24_r <= {pd24_hi, pd24_lo};

    // PD24 retired build #60 — corruption hypothesis already disproven in #58;
    // value is correct ($000028FC) and the probe re-confirms every run.
    // Slot freed for PBCP (bomb caller PC capture).
    // altsource_probe #(
    //     .instance_id ("PD24"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pd24 (.probe(pd24_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PFCS: _SysError ($A9C9) instruction-fetch capture (build #59) ====
    // Build #58 invalidated the SDRAM-$0D28-corruption pivot — PD28/PD24
    // both read Snow-correct values at bomb time (scratch/build58_findings.md).
    // The bomb still fires though, so SOMEONE is calling _SysError(dsNoFPU=90).
    //
    // $A9C9 is the only A-trap that yields the System-Error dialog. This
    // probe catches the supervisor-program instruction-fetch bus cycle whose
    // read data is $A9C9. Captures the FETCH PC (cpuAddr) at AS-rising, plus
    // a saturating count. Sample at bomb time; the most recent PC is the
    // immediate caller of _SysError (often a ROM trampoline that the actual
    // System-file caller jumped through).
    //
    // Build #33 tried this with a different filter (cpu_din captured at
    // AS-falling, which is stale) and saw only $400011DC, an unrelated
    // dispatcher. This rev uses AS-rising data so cpu_din is settled, and
    // counts BOTH ROM and RAM fetches (no FC restriction beyond "super
    // program") so trampolines aren't lost.
    //
    // Layout:
    //   [31:8] pfcs_last_pc[31:8] — top 24 bits of fetch PC
    //   [7:0]  composite — sat-8 count of $A9C9 fetches (bits[6:0]),
    //                       bit 7 = pfcs_last_pc[7] (preserves the
    //                       full PC for ROM/RAM disambiguation).
    //
    // The low byte of PC is approximated by bit 7; the full PC's low 8 bits
    // are lost. Acceptable: A-trap instructions are 2-byte word-aligned, so
    // PC LSB is always 0 and the bit-7 alignment gives 256-byte resolution
    // — enough to find the calling routine, even if not the exact insn.
    // Build #61: ARM unconditionally on every super-prog IF cycle. The
    // build-#59 design required cpu_din==$A9C9 at AS-falling but cpu_din
    // isn't settled yet at that edge — count stuck at 0 even though ROM
    // has 21 $A9C9 instructions. Check $A9C9 only at AS-rising when data
    // is settled.
    wire pfcs_arm = cpuAS_n_d && !cpuAS_n && cpuRW
                 && (cpuFC == 3'b110);                 // super prog IF
    reg pfcs_pending;
    reg [31:0] pfcs_fetch_pc_pending;
    reg [31:0] pfcs_last_pc;
    reg [6:0]  pfcs_count;
    initial begin
        pfcs_pending           = 1'b0;
        pfcs_fetch_pc_pending  = 32'h0;
        pfcs_last_pc           = 32'h0;
        pfcs_count             = 7'd0;
    end
    always @(posedge clk) begin
        if (pfcs_arm) begin
            pfcs_pending          <= 1'b1;
            pfcs_fetch_pc_pending <= cpuAddr;
        end
        if (pfcs_pending && !cpuAS_n_d && cpuAS_n) begin
            if (cpu_din == 16'hA9C9) begin
                pfcs_last_pc <= pfcs_fetch_pc_pending;
                if (pfcs_count != 7'h7F)
                    pfcs_count <= pfcs_count + 7'd1;
            end
            pfcs_pending <= 1'b0;
        end
    end
    reg [31:0] pfcs_r;
    always @(posedge clk)
        pfcs_r <= {pfcs_last_pc[31:8], pfcs_last_pc[7], pfcs_count};

    // PFCS retired for IORB-completion investigation: _SysError fetch_pc
    // confirmed as $40001180 across builds #61/#64/#65. The bomb caller
    // is fully characterized; PFCS adds nothing new. Freeing fit budget
    // for PIOA/PIOC.
    // altsource_probe #(
    //     .instance_id ("PFCS"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfcs (.probe(pfcs_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PBCP: bomb-caller PC capture (build #60, bug #6) =================
    // Build #59 ruled out the _SysError ($A9C9) A-trap path. The bomb dialog
    // at $40002400-$400024FF is entered by direct JSR/JMP/Bxx from
    // somewhere — most likely ROM, possibly via a RAM trampoline.
    //
    // Captures the supervisor-program IF PC immediately before the FIRST
    // entry into the bomb-dialog range. Sticky after first capture.
    //
    // Edge detection: tracks "currently in bomb range" across consecutive
    // super-IFs. On the false→true transition, the *previous* super-IF PC
    // is the caller — that's the instruction that branched/jumped into
    // the bomb routine.
    //
    // Build #53 (PFBE) tried this but with the next-PC-after-entry, which
    // captured operand fetches inside the dialog routine (false positive
    // at $400023FE). PBCP captures the PC BEFORE entry, sticky-locked
    // after the first edge, so subsequent in-range IFs (including the
    // bomb wait loop's own re-fetches) don't overwrite.
    //
    // Layout: pbcp_r[31:0] = bomb_caller_pc (sticky, 32-bit super-IF PC).
    wire pbcp_is_super_if = cpuAS_n_d && !cpuAS_n && cpuRW
                         && (cpuFC == 3'b110);
    // Build #61: widen filter to $400023C0-$400024FF (covers the dialog
    // routine entry at $400023E4 + rendering loop + post-loop + wait).
    // Build #60's narrower $40002400-$400024FF caught only the BSR.W
    // displacement-word fetch inside the dialog, missing the actual entry.
    wire pbcp_in_bomb_range = (cpuAddr[31:8] == 24'h400024)
                           || ((cpuAddr[31:8] == 24'h400023) && cpuAddr[7:6] == 2'b11);
    // The second clause matches $400023C0-$400023FF (bits 7:6 = 11).
    reg [31:0] pbcp_prev_pc;
    reg [31:0] pbcp_caller_pc;
    reg        pbcp_armed;
    reg        pbcp_in_range_prev;
    initial begin
        pbcp_prev_pc       = 32'h0;
        pbcp_caller_pc     = 32'h0;
        pbcp_armed         = 1'b0;
        pbcp_in_range_prev = 1'b0;
    end
    always @(posedge clk) begin
        if (pbcp_is_super_if) begin
            // Detect false→true transition AND not yet armed.
            if (pbcp_in_bomb_range && !pbcp_in_range_prev && !pbcp_armed) begin
                pbcp_caller_pc <= pbcp_prev_pc;
                pbcp_armed     <= 1'b1;
            end
            pbcp_prev_pc       <= cpuAddr;
            pbcp_in_range_prev <= pbcp_in_bomb_range;
        end
    end
    reg [31:0] pbcp_r;
    always @(posedge clk) pbcp_r <= pbcp_caller_pc;

    // PBCP retired build #62 — captures inside-dialog false positives
    // (the dialog rendering routine spans both inside and outside the
    // filter range, and sequential execution across the boundary trips
    // the edge detector). Doesn't identify the actual JSR/JMP caller.
    // Slot freed for PFLN (F-line trap counter, reborn from build #37).
    // altsource_probe #(
    //     .instance_id ("PBCP"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pbcp (.probe(pbcp_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PVCF: F-line vector RAM read (build #62) ============================
    // Build #61's PFCS catch + System.rsrc DSAT decode revealed the bomb's
    // visible "coprocessor not installed" text comes from index 10 of DSAT 2's
    // exception-name table — index 10 maps to 68k vector 11 = Line F. The
    // dialog reads the exception vector from the supervisor stack frame; that
    // frame is populated by the runtime F-line trap handler.
    //
    // ROM's cold vector at \$0000_002C is \$0064_0000 but Mac OS PATCHES that
    // during boot to a runtime handler (probably in ROM around \$4000_DXXX or
    // in System file). PVCF captures the longword the CPU currently reads at
    // address \$0000_00B0 (which is where the 68020 with VBR=0 fetches the
    // F-line handler address on exception entry). Latches at AS-rising for
    // both halves of the longword.
    //
    // Layout: pvcf_r[31:16] = high16 = data at \$00B0, [15:0] = data at \$00B2.
    // Together they form the installed F-line handler address.
    wire pvcf_hi_in = !cpuAS_n && cpuRW && (cpuAddr == 32'h0000_00B0);
    wire pvcf_lo_in = !cpuAS_n && cpuRW && (cpuAddr == 32'h0000_00B2);
    reg pvcf_hi_d, pvcf_lo_d;
    reg [15:0] pvcf_hi, pvcf_lo;
    initial begin
        pvcf_hi_d = 1'b0; pvcf_lo_d = 1'b0;
        pvcf_hi = 16'h0; pvcf_lo = 16'h0;
    end
    always @(posedge clk) begin
        pvcf_hi_d <= pvcf_hi_in;
        pvcf_lo_d <= pvcf_lo_in;
        if (!pvcf_hi_in && pvcf_hi_d) pvcf_hi <= cpu_din;
        if (!pvcf_lo_in && pvcf_lo_d) pvcf_lo <= cpu_din;
    end
    reg [31:0] pvcf_r;
    always @(posedge clk) pvcf_r <= {pvcf_hi, pvcf_lo};

    // PVCF retired for floppy-slow investigation: F-line vector at $00B0
    // reads as garbage $6DB6DB6D because Mac OS POST left a test pattern
    // there (proven build #64). Vector value is meaningless. Freeing fit
    // budget for PFLP/PIWM.
    // altsource_probe #(
    //     .instance_id ("PVCF"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pvcf (.probe(pvcf_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PFLN: F-line trap entry counter (build #62, was retired in #37) =====
    // Counts vector-fetch reads at \$0000_00B0 / \$0000_00B2 with cpuFC=101
    // (supervisor data, used during 68k exception vector fetch). Prior session
    // had this at "count = 8 across the entire boot" but with bomb mechanism
    // now identified as F-line driven, the trap count IS load-bearing —
    // compare delta from boot-start to bomb-time. Also tracks last cpu_din
    // (low 16 of handler address — sanity check vs PVCF).
    //
    // Layout:
    //   [31:24] pfln_count    sat-8 F-line vector reads
    //   [23:16] reserved (=0)
    //   [15:0]  pfln_last_din last cpu_din from \$B0/\$B2 read
    wire pfln_vec_rd = cpuAS_n_d && !cpuAS_n && cpuRW
                    && (cpuFC == 3'b101)
                    && (cpuAddr[31:2] == 30'h0000002C);  // \$B0 or \$B2
    reg pfln_pending;
    reg [7:0]  pfln_count;
    reg [15:0] pfln_last_din;
    initial begin
        pfln_pending  = 1'b0;
        pfln_count    = 8'd0;
        pfln_last_din = 16'd0;
    end
    always @(posedge clk) begin
        if (pfln_vec_rd) begin
            pfln_pending <= 1'b1;
            if (pfln_count != 8'hFF) pfln_count <= pfln_count + 8'd1;
        end
        if (pfln_pending && !cpuAS_n_d && cpuAS_n) begin
            pfln_last_din <= cpu_din;
            pfln_pending  <= 1'b0;
        end
    end
    reg [31:0] pfln_r;
    always @(posedge clk)
        pfln_r <= {pfln_count, 8'd0, pfln_last_din};

    // PFLN retired for floppy-slow investigation: build #64 showed the
    // "F-line trap reads" were Mac OS RAM scanning $00B0 and hitting
    // the $6DB6DB6D test pattern, not real F-line exceptions. The
    // count of 8 was a probe artifact. Freeing fit budget for PFLP/PIWM.
    // altsource_probe #(
    //     .instance_id ("PFLN"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfln (.probe(pfln_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ==== PFLT: F-line trap source PC (build #63) =============================
    // Tracks the most recent supervisor IF PC continuously, and snapshots it
    // (sticky) at the moment of the FIRST F-line vector fetch (\$00B0 read
    // with cpuFC=101). That snapshot is the PC of the instruction whose
    // execution triggered the F-line exception — i.e., the F-line instruction
    // itself.
    //
    // Build #62's PFLN counted 8 F-line vector reads. PFLT identifies the
    // FIRST one's source — which is likely the FPU instruction that our
    // implementation can't handle correctly. Combined with the byte at that
    // PC (which is the F-line opcode), this pinpoints the exact instruction
    // that needs implementing or fixing in mc68881 / TG68 cp_idle_resp.
    //
    // Layout: pflt_r[31:0] = pfts_first_flt_pc (sticky, 32-bit super-IF PC).
    // Build #64: PFTS is now NON-STICKY — captures the LAST F-line trap
    // source PC (not the first). The first trap is the ROM boot's FPU-
    // detection FNOP probe (captured at $40803778 in build #63, inside a
    // SUBQ-BNE loop due to prefetch overshoot). The LAST trap is more
    // likely the bomb-relevant one, since the LAST F-line exception's
    // frame is what the bomb dialog reads to pick the second-line string.
    reg [31:0] pfts_last_super_if_pc;
    reg [31:0] pfts_last_flt_pc;
    initial begin
        pfts_last_super_if_pc = 32'h0;
        pfts_last_flt_pc      = 32'h0;
    end
    wire pflt_is_super_if = cpuAS_n_d && !cpuAS_n && cpuRW
                         && (cpuFC == 3'b110);
    always @(posedge clk) begin
        if (pflt_is_super_if) pfts_last_super_if_pc <= cpuAddr;
        // Latch on EVERY F-line vector fetch (non-sticky) so the final
        // sample shows the LAST trap's source PC.
        if (pfln_vec_rd) begin
            pfts_last_flt_pc <= pfts_last_super_if_pc;
        end
    end
    reg [31:0] pfts_r;
    always @(posedge clk) pfts_r <= pfts_last_flt_pc;

    // PFTS retired for floppy-slow investigation: was the F-line source PC
    // probe but PFLN's "8 traps" turned out to be RAM-scan reads, not
    // real F-line, so PFTS's PC ($40803788) is meaningless. Freeing
    // fit budget for PFLP/PIWM.
    // altsource_probe #(
    //     .instance_id ("PFTS"),
    //     .probe_width (32),
    //     .source_width(1),
    //     .sld_auto_instance_index ("YES")
    // ) cp_pfts (.probe(pfts_r), .source(), .source_clk(clk), .source_ena(1'b1));

endmodule
