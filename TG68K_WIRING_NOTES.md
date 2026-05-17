# TG68K Wiring Notes

## Current Wrapper

The current Mac II core does not instantiate a bidirectional TG68K `DATA` bus
at the FPGA or Verilator top level. It uses the local Verilog wrapper in
`rtl/tg68k/tg68k.v`, which exposes separate read and write data ports:

```verilog
input  [15:0] din;
output [15:0] dout;
output reg [31:0] addr;
```

This is the expected structure for this FPGA design: internal bus ownership is
implemented with muxes, separate read/write data paths, registered latches, and
clock enables. There are no internal tri-states in the active CPU integration.

## Top-Level Data Path

The live top-level wiring is the same in `LBMacTwo.sv` and `verilator/sim.v`:

- `tg68k.dout` is the CPU write-data bus.
- `cpuDataOut` is assigned from `tg68k.dout`.
- `cpuDataOut` feeds memory/peripheral write-data inputs through
  `dataController_top.cpuDataIn`.
- `dataController_top.cpuDataOut` is the system read-data mux.
- `dataController_top.cpuDataOut` feeds `tg68k.din`, with the FPU and format-$B
  bus-error inhibit paths muxed in where needed.

The CPU wrapper samples `din` into an internal register late in the bus cycle
before passing it to `TG68KdotC_Kernel.data_in`. CPU write data comes from
`TG68KdotC_Kernel.data_write` through `dout`.

## Address Path

`tg68k.addr` first passes through `hmmu.v` unless the cycle is CPU-space
(`FC == 3'b111`). The translated address is then decoded by `addrDecoder.v`.

Mac II 32-bit I/O is decoded at `$50Fxxxxx` in this core. The HMMU therefore
translates 24-bit `$Fxxxxx` I/O references into `$50Fxxxxx`, matching the
physical decoder. MAME represents the same devices at `$500xxxxx` with a
`$00F00000` mirror, so MAME also accepts `$50Fxxxxx`.

## Obsolete Wiring Pattern

Older notes for an inout-style `TG68K.vhd` wrapper showed wiring like this:

```verilog
wire [15:0] tg68_data_bidir;
assign tg68_data_bidir = tg68_rw ? 16'hzzzz : cpuDataOut;
```

That is not correct for the current branch. Do not add internal tri-state bus
logic to the active Mac II top level; use the existing `din`/`dout` split bus.
