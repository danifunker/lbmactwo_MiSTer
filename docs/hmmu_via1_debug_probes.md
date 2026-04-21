# HMMU / VIA1 dispatch debug probes

Reusable `$display` instrumentation used to diagnose the HMMU 32-bit
I/O mistranslation bug (fixed in commit
`hmmu: pass through genuine 32-bit addresses unchanged`). The probes
target the Mac II ROM's level-1 IRQ dispatcher at `$40806080` and the
dispatch table at RAM `$018E`.

Each probe is independent — drop in the ones you need, inside the
`` `ifdef SIMULATION `` block near the end of `verilator/sim.v` (before
`endmodule`). All rely on signals already exported by the current
top-level: `last_fetch_pc`, `tg68_a`, `tg68_as_n`, `tg68_rw`, `cpuAddr`,
`cpuFC`, `memoryDataOut`, `_memoryUDS/_memoryLDS`, `_romOE`, `_ramOE`,
`ram_do`, `ram.mem[]`, `selectVIA`, `selectVIA2`, `memoryOverlayOn`,
`dataControllerDataOut`, `dc0.viaDataOut`, `dc0.via.irq_flags`,
`dc0.via.irq_mask`, `dbg_dumped`.

## What each probe tells you

| Probe | Question it answers |
|-------|---------------------|
| A | When does the ROM write handler-address pointers (words starting with `$4080`) into the dispatch table? At what `tg68_a` / `cpuAddr`? |
| B | After the dispatcher executes `JSR (A0)` at `$408060AA`, what sequence of PCs does it actually visit? (catches short RTS-only handlers) |
| C | What does the dispatch table at `RAM[$018E]` actually contain the moment the dispatcher reads it (`PC=$408060A8`)? |
| D | When the CPU reads `$00000190..$00000194`, is ROM or RAM responding, and what word does it see? |
| E | Does VIA1 actually see reads of IFR (`$1A00`) and IER (`$1C00`)? What does the CPU see on the bus, and what are the internal flags/mask? Also snapshots `RAM[$01D4]` (VIA1 base pointer used by the dispatcher). |

## Probe A — handler-address install watchpoint

```verilog
// Watch ALL memory writes whose data == $4080 (high word of a ROM-code
// pointer). These are installs of handler addresses into the dispatch
// table. Logs tg68_a (pre-HMMU) and cpuAddr (post-HMMU).
reg [31:0] probe_a_count;
always @(posedge clk_sys) begin
    if (!tg68_as_n && !tg68_rw && memoryDataOut == 16'h4080) begin
        if (probe_a_count < 64) begin
            $display("[PTR_WR] cyc=? PC=%08h tg68_a=%08h cpuAddr=%08h data=%04h ds=%b fc=%b",
                     last_fetch_pc, tg68_a, cpuAddr, memoryDataOut,
                     {~_memoryUDS, ~_memoryLDS}, cpuFC);
        end
        probe_a_count <= probe_a_count + 1;
    end
end

// Summary line — fires once after dbg_dumped transitions high.
reg probe_a_summary_done;
always @(posedge clk_sys) begin
    if (!probe_a_summary_done && dbg_dumped) begin
        $display("[PTR_SUMMARY] total $4080 writes seen BEFORE IER=03 enable: %0d",
                 probe_a_count);
        probe_a_summary_done <= 1'b1;
    end
end
```

## Probe B — PC-window trace after the dispatcher JSR

```verilog
// Log every unique PC in the 40-cycle window following the JSR (A0)
// at $408060AA. Needed because short RTS-only handlers blink through
// their entry PC in a single cycle.
reg [31:0] probe_b_last_pc;
reg [5:0]  probe_b_window;
always @(posedge clk_sys) begin
    if (last_fetch_pc == 32'h408060AA)
        probe_b_window <= 6'd40;
    else if (probe_b_window != 0)
        probe_b_window <= probe_b_window - 1;

    if (probe_b_window != 0 && last_fetch_pc != probe_b_last_pc) begin
        $display("[JSR_WIN] PC=%08h  (window=%0d)", last_fetch_pc, probe_b_window);
        probe_b_last_pc <= last_fetch_pc;
    end
end
```

## Probe C — dispatch-table RAM dump at dispatch time

```verilog
// Dump RAM[$0188..$019F] whenever dispatcher PC=$408060A8 (movea.l (A0),A0 —
// the table fetch). Gated to the first 4 dispatches to avoid flooding.
// ram.mem[] is word-addressed, so byte address $0188 is word index $00c4.
reg [31:0] probe_c_count;
reg        probe_c_last;
always @(posedge clk_sys) begin
    probe_c_last <= (last_fetch_pc == 32'h408060A8);
    if (last_fetch_pc == 32'h408060A8 && !probe_c_last && probe_c_count < 4) begin
        probe_c_count <= probe_c_count + 1;
        $display("[TABLE_DUMP] dispatch #%0d — memoryOverlayOn=%b  RAM[$0188..019F]:",
                 probe_c_count, memoryOverlayOn);
        $display("  byte[0188] = %04h (word[00c4])", ram.mem[22'h00c4]);
        $display("  byte[018a] = %04h (word[00c5])", ram.mem[22'h00c5]);
        $display("  byte[018c] = %04h (word[00c6])", ram.mem[22'h00c6]);
        $display("  byte[018e] = %04h (word[00c7])", ram.mem[22'h00c7]);
        $display("  byte[0190] = %04h (word[00c8])", ram.mem[22'h00c8]);
        $display("  byte[0192] = %04h (word[00c9])", ram.mem[22'h00c9]);
        $display("  byte[0194] = %04h (word[00ca])", ram.mem[22'h00ca]);
        $display("  byte[0196] = %04h (word[00cb])", ram.mem[22'h00cb]);
        $display("  byte[0198] = %04h (word[00cc])", ram.mem[22'h00cc]);
        $display("  byte[019a] = %04h (word[00cd])", ram.mem[22'h00cd]);
        $display("  byte[019c] = %04h (word[00ce])", ram.mem[22'h00ce]);
        $display("  byte[019e] = %04h (word[00cf])", ram.mem[22'h00cf]);
    end
end
```

## Probe D — bus-read logger for `$0190..$0194`

```verilog
// Watch reads in the dispatch-table range. Reveals whether ROM overlay
// is still hiding RAM (selROM=1) or RAM is responding, plus the actual
// word returned on the bus.
reg [31:0] probe_d_count;
always @(posedge clk_sys) begin
    if (!tg68_as_n && tg68_rw
        && tg68_a >= 32'h00000190 && tg68_a <= 32'h00000194
        && probe_d_count < 16) begin
        $display("[BUS_RD] cyc_tick PC=%08h tg68_a=%08h cpuAddr=%08h selROM=%b selRAM=%b data=%04h",
                 last_fetch_pc, tg68_a, cpuAddr, !_romOE, !_ramOE, ram_do);
        probe_d_count <= probe_d_count + 1;
    end
end
```

## Probe E — VIA1 IFR/IER access logger

```verilog
// Log ANY bus cycle with tg68_a in the VIA1 range ($50F0xxxx). Use this
// first to verify the CPU is even hitting VIA1; if nothing shows up,
// the HMMU or decoder is mistranslating.
reg [31:0] probe_any_via1_count;
always @(posedge clk_sys) begin
    if (!tg68_as_n && tg68_a[31:16] == 16'h50F0 && probe_any_via1_count < 16) begin
        $display("[VIA1_RAW] PC=%08h tg68_a=%08h rw=%b selectVIA=%b selectVIA2=%b cpuAddr=%08h cpuFC=%b",
                 last_fetch_pc, tg68_a, tg68_rw, selectVIA, selectVIA2, cpuAddr, cpuFC);
        probe_any_via1_count <= probe_any_via1_count + 1;
    end
end

// Narrower: IFR (reg $D, offset $1A00) / IER (reg $E, offset $1C00) reads.
reg [31:0] probe_e_cnt;
always @(posedge clk_sys) begin
    if (!tg68_as_n && tg68_rw && selectVIA &&
        (tg68_a[12:9] == 4'hD || tg68_a[12:9] == 4'hE) &&
        probe_e_cnt < 32) begin
        $display("[VIA1_RD] PC=%08h tg68_a=%08h reg=%h data_cpu=%04h dc0.viaDataOut=%04h ifr=%02h ier=%02h",
                 last_fetch_pc, tg68_a, tg68_a[12:9],
                 dataControllerDataOut, dc0.viaDataOut,
                 dc0.via.irq_flags, dc0.via.irq_mask);
        probe_e_cnt <= probe_e_cnt + 1;
    end
end

// One-shot: dump RAM[$01D4..$01D7] (VIA1 base pointer used by the
// dispatcher) the first time PC hits $40806092.
reg probe_e_dumped;
always @(posedge clk_sys) begin
    if (!probe_e_dumped && last_fetch_pc == 32'h40806092) begin
        $display("[VIA1_BASE] RAM[$01D4] = word[00ea]=%04h word[00eb]=%04h (long=%04h%04h)",
                 ram.mem[22'h00ea], ram.mem[22'h00eb],
                 ram.mem[22'h00ea], ram.mem[22'h00eb]);
        probe_e_dumped <= 1'b1;
    end
end
```

## Notes

- `ram.mem[]` is indexed by 16-bit word (byte address >> 1).
- `last_fetch_pc` lags CPU execution by one instruction in some
  pipelines — interpret PC values within ±1 instruction.
- All counters cap themselves to avoid log flooding; bump the limits
  if you need a longer trace.
- Signal names assume the current `verilator/sim.v` hierarchy; if
  `dc0.via.irq_flags` / `irq_mask` are renamed, update Probe E.
