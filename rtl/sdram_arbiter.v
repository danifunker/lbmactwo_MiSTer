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
    output [2:0]  dbg_vram_state
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
    // Mac quiescence detector
    //
    // The previous arbiter only checked mac_active at the instant a video
    // transaction would start.  That left a wide race window: Mac could
    // re-assert one cycle later and then sit on the SDRAM mux for the next
    // 4-9 cycles, during which the Mac CPU itself would latch sdram_dout
    // from the video's in-flight transaction (mac_dout is combinational).
    // Mac then executes a corrupted instruction, branches into the wrong
    // ROM path, programs the wrong card mode/palette, and the user sees a
    // moving palette-noise pattern rather than the proper desktop.
    //
    // Counter resets whenever Mac is active, and counts up otherwise.  We
    // only allow a new video transaction to start once Mac has been idle
    // for several cycles -- by then it is much less likely to re-assert
    // before our video read window completes.  Combined with the existing
    // video_clean tracking, this gives Mac near-absolute priority while
    // still letting video sneak in during genuine Mac gaps.
    // ------------------------------------------------------------------------
    reg [3:0] mac_idle_cnt;
    always @(posedge clk) begin
        if (reset || mac_active) begin
            mac_idle_cnt <= 4'd0;
        end else if (mac_idle_cnt != 4'hF) begin
            mac_idle_cnt <= mac_idle_cnt + 4'd1;
        end
    end
    // Three full cycles of Mac quiet before we'll try a video transaction.
    // At clk_sys = 32.5 MHz that is ~92 ns, comfortably less than a Mac
    // CPU bus cycle, so we don't starve video for long.
    wire mac_quiescent = (mac_idle_cnt >= 4'd3);

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

    // SDRAM signal muxes — Mac priority preserved, combinational as before.
    // Additionally gated on mac_quiescent so we don't start a video
    // transaction the instant before Mac re-asserts.
    wire grant_video = mac_quiescent & !mac_active & (vram_rd | vram_wr);

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
                    // dirty.  We don't abort early — we still ride out the
                    // wait so the SDRAM controller has time to finish whatever
                    // it started — but we won't latch the result.
                    if (mac_active) video_clean <= 1'b0;

                    if (vram_wait_cnt > 3'd0) begin
                        vram_wait_cnt <= vram_wait_cnt - 3'd1;
                    end else begin
                        if (video_clean && !mac_active) begin
                            // Clean transaction: capture data, signal ready
                            vram_din_reg     <= sdram_dout;
                            vram_ready_latch <= 1'b1;
                            vram_state       <= VRAM_READY;
                        end else begin
                            // Preempted: drop this transaction silently.
                            // Returning to IDLE without ready makes the
                            // video card hold vram_rd and retry next cycle.
                            vram_state <= VRAM_IDLE;
                        end
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

    // Debug exposures for JTAG instrumentation
    assign dbg_grant_video  = grant_video;
    assign dbg_video_clean  = video_clean;
    assign dbg_mac_idle_cnt = mac_idle_cnt;
    assign dbg_vram_state   = vram_state;

endmodule