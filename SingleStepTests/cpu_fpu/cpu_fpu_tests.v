// Integrated TG68K + mc68881_top bench for FPU instruction testing.
//
// Uses the bus wrapper `tg68k.v` (not raw kernel) so DTACK handshaking
// works correctly for the multi-cycle FPU response. Address decode +
// DTACK arbitration mirrors verilator/sim.v.

module cpu_fpu_tests
  (
   input         clk,             // single clock; bus wrapper uses phi1/phi2 enables
   input         reset,           // active high
   input         phi1,
   input         phi2,

   // Bus visible to host C harness for RAM-backed accesses.
   input  [15:0] data_in,
   output [15:0] data_write,
   output [31:0] addr_out,
   output        as_n,
   output        uds_n,
   output        lds_n,
   output        rw_n,
   output        longword,
   output [2:0]  fc,
   output        fpu_select,      // active when CPU is talking to FPU

   // FPU debug visibility.
   output        fpu_status_valid,
   output [31:0] fpu_d_out_obs,
   output        fpu_dsack0_n_obs,
   output        fpu_dsack1_n_obs,

   // CPU internal taps for FPU dispatch debugging.
   output [7:0]  dbg_micro_state,
   output [31:0] dbg_cp_xfer_data,
   output [31:0] dbg_data_write_tmp,
   output [2:0]  dbg_cp_xfer_cnt,
   output [31:0] dbg_d0,
   output [31:0] dbg_d1,
   output [31:0] dbg_data_write_muxin,
   output [15:0] dbg_data_in,
   output [31:0] dbg_last_data_read,
   output [31:0] dbg_data_read,
   output [1:0]  dbg_state
   );

   // Hierarchical taps into the TG68K kernel inside the bus wrapper.
   // Path: cpu_fpu_tests → cpu (tg68k.v) → tg68k (TG68KdotC_Kernel).
   // micro_state is an enum; ghdl-synth lowers it to a small int.
   assign dbg_micro_state    = cpu.tg68k.micro_state;
   assign dbg_cp_xfer_data   = cpu.tg68k.cp_xfer_data;
   assign dbg_data_write_tmp = cpu.tg68k.data_write_tmp;
   assign dbg_cp_xfer_cnt    = 3'b000;  // cnt removed (per-word states now)
   // Regfile is split high/low per the TG68K split-array convention.
   assign dbg_d0 = ({cpu.tg68k.regfile_n2[0], 8'h00} | {24'h0, cpu.tg68k.regfile_n1[0]});
   assign dbg_d1 = ({cpu.tg68k.regfile_n2[1], 8'h00} | {24'h0, cpu.tg68k.regfile_n1[1]});
   assign dbg_data_write_muxin = cpu.tg68k.data_write_muxin;
   assign dbg_data_in = cpu.tg68k.data_in;
   assign dbg_last_data_read = cpu.tg68k.last_data_read;
   assign dbg_data_read = cpu.tg68k.data_read;
   assign dbg_state = cpu.tg68k.state;

   // -------------------- CPU bus signals --------------------------------
   wire [31:0] cpu_addr;
   wire [15:0] cpu_dout;
   wire        cpu_rw_n, cpu_as_n, cpu_uds_n, cpu_lds_n;
   wire        cpu_longword;
   wire [2:0]  cpu_fc;

   // Data presented back to the CPU: comes from FPU when fpu_select is
   // asserted, otherwise from external RAM (driven by host harness).
   wire [31:0] fpu_d_out;
   wire [15:0] cpu_din_mux = fpu_select ? fpu_d_out[15:0] : data_in;

   // -------------------- FPU address decode -----------------------------
   wire fpu_addr_match = (cpu_fc == 3'b111)
                       && (cpu_addr[31:16] == 16'h0002)
                       && (cpu_addr[15:13] == 3'b001);
   wire fpu_cs = fpu_addr_match && !cpu_as_n;
   assign fpu_select = fpu_cs;

   // -------------------- FPU DSACK → DTACK ------------------------------
   wire fpu_dsack0_n, fpu_dsack1_n;
   wire fpu_acked = !fpu_dsack0_n || !fpu_dsack1_n;
   // dtack_n is active-low; assert (=0) when FPU acks OR for plain RAM
   // accesses (RAM is always ready). The wrapper handles VPA separately.
   wire cpu_dtack_n = fpu_addr_match ? (fpu_dsack0_n & fpu_dsack1_n) : 1'b0;

   // -------------------- TG68K bus wrapper ------------------------------
   tg68k cpu (
      .clk        (clk),
      .reset      (reset),
      .phi1       (phi1),
      .phi2       (phi2),
      .cpu        (2'b11),
      .dtack_n    (cpu_dtack_n),
      .rw_n       (cpu_rw_n),
      .as_n       (cpu_as_n),
      .uds_n      (cpu_uds_n),
      .lds_n      (cpu_lds_n),
      .fc         (cpu_fc),
      .reset_n    (),
      .E          (),
      .E_div      (1'b1),
      .E_PosClkEn (),
      .E_NegClkEn (),
      .vma_n      (),
      .vpa_n      (1'b1),     // never assert VPA in this bench
      .br_n       (1'b1),
      .bg_n       (),
      .bgack_n    (1'b1),
      .ipl        (3'b111),
      .berr       (1'b0),
      .cpu_halted (),
      .din        (cpu_din_mux),
      .dout       (cpu_dout),
      .longword   (cpu_longword),
      .addr       (cpu_addr),
      .VBR_out    (),
      .berr_inhibit (),
      .berr_data    ()
   );

   assign addr_out   = cpu_addr;
   assign data_write = cpu_dout;
   assign as_n       = cpu_as_n;
   assign uds_n      = cpu_uds_n;
   assign lds_n      = cpu_lds_n;
   assign rw_n       = cpu_rw_n;
   assign longword   = cpu_longword;
   assign fc         = cpu_fc;

   // -------------------- mc68881_top instance ---------------------------
   wire sense_n;
   assign sense_n = 1'bz;

   // CIR register address remapping — mirrors LBMacTwo.sv. mc68881_top
   // uses non-standard addresses for the CIR regs that collide with
   // peripheral-mode addresses 0/2/3.
   wire [4:0] fpu_addr_remapped = (cpu_addr[5:1] == 5'd0) ? 5'd13 :
                                  (cpu_addr[5:1] == 5'd2) ? 5'd12 :
                                  (cpu_addr[5:1] == 5'd3) ? 5'd28 :
                                                            cpu_addr[5:1];

   // Size encoding: derive from longword + UDS/LDS.
   wire [1:0] fpu_size_n =
       cpu_as_n                   ? 2'b11 :  // idle
       cpu_longword               ? 2'b00 :  // .L
       (!cpu_uds_n && !cpu_lds_n) ? 2'b10 :  // .W
                                    2'b01;   // .B

   assign fpu_d_out_obs    = fpu_d_out;
   assign fpu_dsack0_n_obs = fpu_dsack0_n;
   assign fpu_dsack1_n_obs = fpu_dsack1_n;

   mc68881_top fpu
     (
      .a_in         (fpu_addr_remapped),
      .d_in         ({16'h0000, cpu_dout}),
      .d_out        (fpu_d_out),
      .size_n       (fpu_size_n),
      .as_n         (cpu_as_n),
      .cs_n         (~fpu_addr_match),
      .rw           (cpu_rw_n),                 // 1=read, 0=write
      .ds_n         (cpu_uds_n & cpu_lds_n),
      .dsack0_n     (fpu_dsack0_n),
      .dsack1_n     (fpu_dsack1_n),
      .reset_n      (~reset),
      .clk          (clk),
      .sense_n      (sense_n),
      .status_valid (fpu_status_valid)
      );
endmodule
