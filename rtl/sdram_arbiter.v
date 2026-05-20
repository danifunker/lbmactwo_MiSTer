//
// sdram_arbiter.v
//
// SDRAM arbiter for Macintosh Plus MiSTer core
// Shares SDRAM between Mac system and NuBus video card
//
// Mac system has priority, NuBus video uses idle cycles
//

module sdram_arbiter (
    // System
    input         clk,           // System clock (same as clk_sys)
    input         clk8_en_p,     // 1-cycle pulse at clk_8 rising edge — used
                                 //   to align video transactions to SDRAM
                                 //   cycle boundaries.  Pass 1'b0 to skip
                                 //   alignment (legacy behaviour).
    input         reset,

    // Mac System Port (high priority)
    input  [24:0] mac_addr,
    input  [15:0] mac_din,
    output [15:0] mac_dout,
    input   [1:0] mac_ds,
    input         mac_we,
    input         mac_oe,
    
    // NuBus Video Port (low priority)
    input  [24:0] vram_addr,
    input  [15:0] vram_dout,
    output [15:0] vram_din,
    input         vram_rd,
    input         vram_wr,
    output        vram_ready,
    
    // SDRAM Controller Port
    output [24:0] sdram_addr,
    output [15:0] sdram_din,
    input  [15:0] sdram_dout,
    output  [1:0] sdram_ds,
    output        sdram_we,
    output        sdram_oe,

    // Debug outputs (for JTAG ISSP probes / SignalTap)
    output        dbg_grant_video,
    output        dbg_video_clean,
    output [3:0]  dbg_mac_idle_cnt,
    output [2:0]  dbg_vram_state,

    // Stall request to Mac CPU: high while video has the SDRAM committed
    // and Mac is trying to read.  Used to delay _cpuDTACK so Mac latches
    // the *real* sdram_dout for its own access, not the in-flight video
    // word.  Without this, Mac can pick up garbage and execute corrupted
    // code (the BERR at PC=$40806A0E -> Error1Handler -> Test Manager
    // poll loop the project's docs/new-scc.md describes).
    output        mac_stall,

    // Mac READ data-valid handshake (the real coherency fix).
    //
    // The SDRAM controller samples oe/addr only at t=0 of its 8-state cycle
    // (marked by clk8_en_p) and the read word lands in sdram_dout at t=5.
    // The Mac's old "turbo" DTACK asserted immediately on AS, which is only
    // safe when the Mac wins every SDRAM slot -- but video steals ~50% of
    // them, so the Mac latched the video word ~half the time.
    //
    // Because grant_video = !mac_active, the Mac wins the *next* t=0 slot
    // the instant it asserts a read, and keeps winning while it waits.  So
    // we count clk8_en_p edges while a Mac read is asserted: the first edge
    // latches the Mac command into the SDRAM, by the second edge sdram_dout
    // holds the Mac word and is stable.  mac_dout_valid then rises and the
    // CPU DTACK is allowed to assert.  Guaranteed to release (the Mac always
    // wins the slot), so it cannot wedge the CPU the way the blanket
    // mac_stall did.
    output        mac_dout_valid
);

    // ------------------------------------------------------------------------
    // Mac vs Video arbitration
    //
    // The previous implementation made grant_video a combinational signal:
    //     grant_video = !mac_active & (vram_rd | vram_wr);
    //     vram_din    = sdram_dout;               // combinational
    // This created a race that is harmless in Verilator (the sim wires the
    // video card to a private sim_vram, so the arbiter is never exercised)
    // but lethal on real hardware:
    //   T0: video request, Mac idle -> grant_video=1, sdram_addr=vram_addr
    //   Tx: Mac asserts mac_we/mac_oe mid-transaction -> grant_video=0,
    //       sdram_addr immediately switches to mac_addr.  The SDRAM controller
    //       continues the read it already started, but at the end of the
    //       wait window vram_din latches whatever sdram_dout currently is --
    //       which may be data from an unrelated Mac read that came in after.
    // On hardware (with the Mac actively booting and hitting DRAM constantly)
    // this fires every few microseconds and the framebuffer ends up loaded
    // with random Mac DRAM contents -> cyan/black noise on screen.
    //
    // Fix: once we grant the video, lock the grant in a registered signal
    // and hold the SDRAM mux on the video port for the entire transaction.
    // Capture sdram_dout into a register at the cycle when the SDRAM data
    // is known stable, and feed that register out to the video card instead
    // of the bare SDRAM bus.  Mac access is briefly stalled during the
    // ~185ns video window, which is well within Mac bus-cycle tolerance.
    // ------------------------------------------------------------------------

    wire mac_active = mac_we | mac_oe;

    // ------------------------------------------------------------------------
    // Mac idle counter (kept for debug visibility; no longer gates video).
    //
    // Earlier we required mac_quiescent (>=3 idle cycles) before starting a
    // video transaction.  Real ISSP captures showed Mac CPU is bus-active
    // ~57% of the time during boot, so the 3-cycle quiet gap rarely opens
    // -- video reads succeeded only ~2% of the time (4/200 captures saw
    // vram_ready=1).  Drop the gate; rely on video_clean tracking + Mac
    // priority on the mux to keep things correct without starving video.
    // ------------------------------------------------------------------------
    reg [3:0] mac_idle_cnt;
    always @(posedge clk) begin
        if (reset || mac_active) begin
            mac_idle_cnt <= 4'd0;
        end else if (mac_idle_cnt != 4'hF) begin
            mac_idle_cnt <= mac_idle_cnt + 4'd1;
        end
    end

    // ------------------------------------------------------------------------
    // Mac vs Video arbitration
    //
    // History: the original implementation had a combinational grant_video and
    // wired vram_din directly to sdram_dout.  Verilator wires the video card
    // to a private sim_vram (so the arbiter is never exercised in sim and the
    // bug is invisible there) but on real hardware the combinational grant
    // produced visible noise on screen: video would start a read while Mac
    // was idle, Mac would re-assert mid-transaction, sdram_addr would
    // instantly flip to mac_addr, and at the end of the 6-cycle wait
    // vram_din would latch a Mac word.  Framebuffer ends up filled with
    // random Mac DRAM contents -> cyan/black noise pattern.
    //
    // A first attempt locked grant_video for the full transaction window so
    // Mac couldn't preempt.  That fixed the video side but starved the Mac:
    // its bus cycles were silently extended past 68020 DTACK tolerance and
    // Mac CPU reads returned the video's data instead, wedging boot before
    // anything was written to VRAM -> pure black screen.
    //
    // This version keeps Mac priority (the SDRAM mux is still combinational,
    // Mac never gets blocked) but tracks whether the in-flight video
    // transaction was preempted at any point.  Only uncontested transactions
    // are latched into vram_din_reg; preempted ones are silently dropped and
    // the video card retries on its next prefetch cycle.  The video card
    // already tolerates missed fetches via its prefetch + cache logic, so
    // intermittent retries are harmless.
    // ------------------------------------------------------------------------

    // SDRAM signal muxes — Mac priority preserved (mac_active blocks video).
    // No quiescence gating: empirically that starved video almost entirely.
    wire grant_video = !mac_active & (vram_rd | vram_wr);

    assign sdram_addr = grant_video ? vram_addr : mac_addr;
    assign sdram_din  = grant_video ? vram_dout : mac_din;
    assign sdram_ds   = grant_video ? 2'b11 : mac_ds;
    assign sdram_we   = grant_video ? vram_wr : mac_we;
    assign sdram_oe   = grant_video ? vram_rd : mac_oe;

    // Mac sees the SDRAM bus directly.  Latching mac_dout sounded right but
    // gave Mac STALE data during video transactions (the held value is from
    // before video started, not Mac's actual current request), which broke
    // Mac boot harder than the race did.  Mac's bus protocol is too tightly
    // coupled to immediate sdram_dout availability for a held-value scheme
    // to work without also stalling the CPU via DTACK -- that's a bigger
    // change than we want to attempt here.
    assign mac_dout = sdram_dout;

    // Video reads the latched (clean-transaction-only) word
    reg [15:0] vram_din_reg;
    assign vram_din = vram_din_reg;

    // ------------------------------------------------------------------------
    // Video transaction state machine
    //
    // SDRAM operations complete in ~5-6 clk_sys cycles (one clk_8 SDRAM cycle
    // at 8 MHz plus alignment margin).  We track preemption with video_clean:
    // it starts at 1 when the transaction begins and clears the moment Mac
    // preempts.  At the end of the wait we only latch sdram_dout if the
    // transaction stayed clean throughout AND Mac is still idle on the
    // capture cycle itself.  Otherwise we abandon and the video card retries.
    // ------------------------------------------------------------------------

    reg [2:0] vram_state;
    reg [2:0] vram_wait_cnt;
    reg vram_ready_latch;
    reg video_clean;

    localparam VRAM_IDLE  = 3'd0;
    localparam VRAM_WAIT  = 3'd1;
    localparam VRAM_READY = 3'd2;

    // Wait count: SDRAM cmd issued at T0, data latched into sdram_dout at T5
    // (~78 ns later, ~2.5 clk_sys cycles).  Worst case alignment adds one
    // SDRAM cycle (~4 clk_sys) if we land between T0 boundaries.  Use 6
    // cycles -- matches the original arbiter budget and keeps the
    // contention window as narrow as we can manage.  Previous experiments
    // with clk8_en_p alignment and a 9-cycle wait starved video because
    // Mac CPU bus cycles also begin at clk_8 rising, so the
    // (!mac_active && clk8_en_p) gate almost never fired.
    localparam WAIT_COUNT = 3'd6;

    always @(posedge clk) begin
        if (reset) begin
            vram_state       <= VRAM_IDLE;
            vram_wait_cnt    <= 3'd0;
            vram_ready_latch <= 1'b0;
            video_clean      <= 1'b0;
            vram_din_reg     <= 16'd0;
        end else begin
            case (vram_state)
                VRAM_IDLE: begin
                    vram_ready_latch <= 1'b0;
                    // Start whenever Mac is idle.  No clk_8 alignment --
                    // SDRAM naturally waits for its next T0 boundary if we
                    // assert mid-cycle, and aligning on clk8_en_p was
                    // colliding with Mac's bus-cycle alignment.
                    if (grant_video) begin
                        video_clean   <= 1'b1;
                        vram_state    <= VRAM_WAIT;
                        vram_wait_cnt <= WAIT_COUNT;
                    end
                end

                VRAM_WAIT: begin
                    // If Mac preempts at any point, mark the transaction
                    // dirty.  We ride out the full wait so the SDRAM
                    // controller finishes whatever it started.
                    if (mac_active) video_clean <= 1'b0;

                    if (vram_wait_cnt > 3'd0) begin
                        vram_wait_cnt <= vram_wait_cnt - 3'd1;
                    end else begin
                        // ALWAYS complete the transaction.  This is critical:
                        // the video card's FSM blocks in S_VIDEO_WAIT until
                        // vram_ready, and that same FSM also services Mac's
                        // NuBus CPU accesses from S_IDLE.  If we ever WITHHELD
                        // vram_ready (the old "preempted -> back to IDLE
                        // without ready" path), a run of Mac-preempted video
                        // reads could hang the FSM in S_VIDEO_WAIT, the card
                        // would stop ACKing Mac's NuBus cycles, and the Mac
                        // CPU would stall -> black screen / no boot.
                        //
                        // On a CLEAN transaction we capture fresh data.  On a
                        // preempted (dirty) one we KEEP the previous
                        // vram_din_reg value -- stale framebuffer data is far
                        // less harmful than latching an unrelated Mac word,
                        // and we never deadlock.
                        if (video_clean && !mac_active) begin
                            vram_din_reg <= sdram_dout;
                        end
                        vram_ready_latch <= 1'b1;
                        vram_state       <= VRAM_READY;
                    end
                end

                VRAM_READY: begin
                    if (!vram_rd && !vram_wr) begin
                        vram_ready_latch <= 1'b0;
                        vram_state       <= VRAM_IDLE;
                    end
                end

                default: vram_state <= VRAM_IDLE;
            endcase
        end
    end

    assign vram_ready = vram_ready_latch;

    // Stall Mac when video has the SDRAM bus committed AND for several
    // cycles afterwards.  The "afterwards" tail is critical: when
    // vram_state returns to IDLE the SDRAM cycle that produced video's
    // data is *just* ending; sdram_dout is still video's word and will
    // remain so until the next SDRAM cycle completes Mac's read at the
    // following T5.  If we dropped mac_stall the instant vram_state
    // hit IDLE the Mac CPU would happily latch the video's data on
    // sdram_dout and execute it as an instruction or use it as an
    // address (leading to the BERR at PC=$40806A0E -> Test Manager
    // hang described in docs/new-scc.md).
    //
    // Hold for POST_VIDEO_HOLD clk_sys cycles after vram_state drops.
    // SDRAM cycle = 8 clk_64 = ~4 clk_sys, alignment slop adds up to
    // another 4 -- so 8 is conservative for worst-case Mac latch.
    localparam POST_VIDEO_HOLD = 4'd8;
    reg [3:0] post_video_cnt;
    always @(posedge clk) begin
        if (reset) begin
            post_video_cnt <= 4'd0;
        end else if (vram_state != VRAM_IDLE) begin
            post_video_cnt <= POST_VIDEO_HOLD;
        end else if (post_video_cnt != 4'd0) begin
            post_video_cnt <= post_video_cnt - 4'd1;
        end
    end
    assign mac_stall = ((vram_state != VRAM_IDLE) || (post_video_cnt != 4'd0))
                       & mac_active;

    // ------------------------------------------------------------------------
    // Mac READ data-valid handshake (coherency fix -- see port comment).
    //
    // While the Mac holds a read (mac_oe), count clk8_en_p edges (SDRAM t=0
    // boundaries).  grant_video = !mac_active, so every t=0 reached while the
    // Mac waits serves the Mac's address.  The first edge latches the Mac
    // command; by the second edge sdram_dout holds the Mac word (latched at
    // t=5 of the first slot) and is stable.  Assert valid then.  Writes do
    // not need this (Mac latches no read data); they keep the fast path.
    // The counter resets the moment the read deasserts, so the next read
    // starts fresh and the handshake always releases.
    // ------------------------------------------------------------------------
    reg [1:0] mac_rd_t0_cnt;
    reg       mac_dout_valid_r;
    always @(posedge clk) begin
        if (reset) begin
            mac_rd_t0_cnt    <= 2'd0;
            mac_dout_valid_r <= 1'b0;
        end else if (!mac_oe) begin
            // No read in progress -- arm for the next one.
            mac_rd_t0_cnt    <= 2'd0;
            mac_dout_valid_r <= 1'b0;
        end else begin
            // Mac read asserted: advance on each SDRAM cycle boundary.
            if (clk8_en_p && mac_rd_t0_cnt != 2'd2)
                mac_rd_t0_cnt <= mac_rd_t0_cnt + 2'd1;
            if (mac_rd_t0_cnt == 2'd2)
                mac_dout_valid_r <= 1'b1;
        end
    end
    assign mac_dout_valid = mac_dout_valid_r;

    // Debug exposures for JTAG instrumentation
    assign dbg_grant_video  = grant_video;
    assign dbg_video_clean  = video_clean;
    assign dbg_mac_idle_cnt = mac_idle_cnt;
    assign dbg_vram_state   = vram_state;

endmodule