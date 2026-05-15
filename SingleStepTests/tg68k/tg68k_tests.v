// SingleStep bench wrapper for TG68KdotC_Kernel (raw, 68020 mode).
//
// The kernel runs one bus access per `clkena_in` pulse. The C++ harness owns
// RAM and inspects `busstate` each enabled cycle to drive `data_in` (reads)
// or capture `data_write` (writes). Byte lanes via nUDS/nLDS.
//
// busstate encoding (from TG68K source):
//   00 -> fetch code     10 -> read data
//   11 -> write data     01 -> no bus access (idle)

module tg68k_tests
  (
   input         clk,
   input         reset,           // active high
   input         clkena_in,
   input  [15:0] data_in,
   output [15:0] data_write,
   output [31:0] addr_out,
   output [1:0]  busstate,
   output        nWr,
   output        nUDS,
   output        nLDS,
   output        longword,
   output [2:0]  fc,
   output [31:0] vbr_out
   );

   TG68KdotC_Kernel cpu
     (
      .clk             (clk),
      .nReset          (~reset),
      .clkena_in       (clkena_in),
      .data_in         (data_in),
      .IPL             (3'b111),
      .IPL_autovector  (1'b0),
      .berr            (1'b0),
      .CPU             (2'b11),     // 68020 mode (VBR + stack frames)
      .addr_out        (addr_out),
      .data_write      (data_write),
      .nWr             (nWr),
      .nUDS            (nUDS),
      .nLDS            (nLDS),
      .busstate        (busstate),
      .longword        (longword),
      .nResetOut       (),
      .FC              (fc),
      .clr_berr        (),
      .cpu_halted      (),
      .berr_inhibit    (),
      .berr_data       (),
      .skipFetch       (),
      .regin_out       (),
      .CACR_out        (),
      .VBR_out         (vbr_out)
      );
endmodule
