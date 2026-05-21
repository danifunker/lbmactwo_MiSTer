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
    input wire        mac_dout_valid
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

endmodule
