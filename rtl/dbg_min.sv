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
    input wire        sd_buff_wr
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

    altsource_probe #(
        .instance_id ("PSC4"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psc4 (.probe(scsi4_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // Bus-reset count + completion flags (survive scsi_rst).
    reg [31:0] scsi5_r;
    always @(posedge clk)
        scsi5_r <= {16'd0, scsi_dbg4};

    altsource_probe #(
        .instance_id ("PSC5"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psc5 (.probe(scsi5_r), .source(), .source_clk(clk), .source_ena(1'b1));

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

    altsource_probe #(
        .instance_id ("PSC6"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psc6 (.probe(scsi6_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // Raw disk-data capture: the first two 16-bit words the HPS writes into
    // each sector buffer (sd_buff_addr 0 and 1).  A Mac disk block 0 (Driver
    // Descriptor Map) begins with the signature 0x4552 ('ER').  If PSC8 shows
    // 0x5245 the bytes are swapped; garbage means the data path is corrupt.
    // disk_wr_cnt counts sd_buff_wr strobes so we can tell if any data flows.
    reg [15:0] disk_word0, disk_word1;
    reg [15:0] disk_wr_cnt;
    always @(posedge clk) begin
        if (sd_buff_wr) begin
            disk_wr_cnt <= disk_wr_cnt + 16'd1;
            if (sd_buff_addr == 8'd0) disk_word0 <= sd_buff_dout;
            if (sd_buff_addr == 8'd1) disk_word1 <= sd_buff_dout;
        end
    end
    reg [31:0] disk_r;
    reg [31:0] disk_cnt_r;
    always @(posedge clk) begin
        disk_r     <= {disk_word1, disk_word0};
        disk_cnt_r <= {16'd0, disk_wr_cnt};
    end

    altsource_probe #(
        .instance_id ("PSC8"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psc8 (.probe(disk_r), .source(), .source_clk(clk), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("PSC9"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psc9 (.probe(disk_cnt_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ---- Interrupt-path diagnosis (PSCA) ----------------------------------
    // The Mac boot spins at ROM 0x2432 waiting on low-mem Ticks(0x16A), which
    // is bumped only by the VIA1 60Hz interrupt service routine.  Determine
    // whether (a) the VIA ever REQUESTS an interrupt (cpuIPL_n leaves 111) and
    // (b) the CPU ever ACKNOWLEDGES one (a CPU-space bus cycle, cpuFC==7, that
    // is not an FPU coprocessor access -> autovectored IACK).
    //   irq_seen : sticky, VIA/SCC ever asserted IPL
    //   ipl_min  : sticky lowest cpuIPL_n observed (highest-priority request)
    //   iack_cnt : count of interrupt-acknowledge bus cycles
    //   iack_lvl : interrupt level of the most recent IACK (cpuAddr[3:1])
    wire is_iack = (cpuFC == 3'b111) && !selectFPU;
    reg        irq_seen;
    reg [2:0]  ipl_min;
    reg [15:0] iack_cnt;
    reg [2:0]  iack_lvl;
    reg        iack_as_d;
    initial begin irq_seen = 1'b0; ipl_min = 3'b111; iack_cnt = 16'd0; iack_lvl = 3'd0; iack_as_d = 1'b0; end
    always @(posedge clk) begin
        if (cpuIPL_n != 3'b111) irq_seen <= 1'b1;
        if (cpuIPL_n < ipl_min) ipl_min <= cpuIPL_n;
        iack_as_d <= (is_iack && !cpuAS_n);
        if (is_iack && !cpuAS_n && !iack_as_d) begin   // new IACK bus cycle
            iack_cnt <= iack_cnt + 16'd1;
            iack_lvl <= cpuAddr[3:1];
        end
    end
    reg [31:0] irq_r;
    always @(posedge clk)
        irq_r <= {5'd0, iack_lvl, 3'd0, irq_seen, ipl_min, cpuIPL_n, iack_cnt};

    altsource_probe #(
        .instance_id ("PSCA"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_psca (.probe(irq_r), .source(), .source_clk(clk), .source_ena(1'b1));

    // ---- Bus-error capture (PSCB/PSCC/PSCD) -------------------------------
    // berr_out fires when a CPU bus cycle hits no decoded select for ~8us.
    // NOTE: empty NuBus slots bus-error BY DESIGN -- the Mac II Slot Manager
    // probes slots 9-E and expects (and recovers from) berrs on empty ones.
    // So the diagnostic berr is one at a NON-slot address, or the most recent
    // berr before the hang.  We capture:
    //   PSCB = last_berr_addr : most recent faulting address (likely the fatal
    //                           one, since the SCC monitor poll itself decodes)
    //   PSCD = susp_berr_addr : first faulting address that is NOT NuBus slot
    //                           space -> an I/O/RAM access that should respond
    //   PSCC = {berr_cnt, susp_seen, susp_fc, last_fc}
    // A NuBus slot address: A[31:28]=9..E (standard) or A[31:28]=F & A[27:24]=9..E.
    wire is_slot_addr = ((cpuAddr[31:28] >= 4'h9 && cpuAddr[31:28] <= 4'hE) ||
                         (cpuAddr[31:28] == 4'hF && cpuAddr[27:24] >= 4'h9 && cpuAddr[27:24] <= 4'hE));
    reg        berr_d;
    reg [31:0] last_berr_addr;
    reg [31:0] susp_berr_addr;
    reg [2:0]  last_berr_fc;
    reg [2:0]  susp_berr_fc;
    reg [15:0] berr_cnt;
    reg        susp_seen;
    initial begin
        last_berr_addr = 32'd0; susp_berr_addr = 32'd0;
        last_berr_fc = 3'd0; susp_berr_fc = 3'd0;
        berr_cnt = 16'd0; susp_seen = 1'b0; berr_d = 1'b0;
    end
    always @(posedge clk) begin
        berr_d <= berr;
        if (berr && !berr_d) begin            // rising edge of berr_out
            berr_cnt       <= berr_cnt + 16'd1;
            last_berr_addr <= cpuAddr;
            last_berr_fc   <= cpuFC;
            if (!is_slot_addr && !susp_seen) begin
                susp_seen      <= 1'b1;
                susp_berr_addr <= cpuAddr;
                susp_berr_fc   <= cpuFC;
            end
        end
    end
    reg [31:0] berr_last_r, berr_susp_r, berr_cnt_r;
    always @(posedge clk) begin
        berr_last_r <= last_berr_addr;
        berr_susp_r <= susp_berr_addr;
        berr_cnt_r  <= {berr_cnt, 6'd0, susp_seen, susp_berr_fc, 1'b0, last_berr_fc};
    end

    altsource_probe #(
        .instance_id ("PSCB"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pscb (.probe(berr_last_r), .source(), .source_clk(clk), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("PSCC"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pscc (.probe(berr_cnt_r), .source(), .source_clk(clk), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("PSCD"),
        .probe_width (32),
        .source_width(1),
        .sld_auto_instance_index ("YES")
    ) cp_pscd (.probe(berr_susp_r), .source(), .source_clk(clk), .source_ena(1'b1));

endmodule
