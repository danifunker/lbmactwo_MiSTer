  What remains for full FPU integration (from the plan's "Other Files Needing Changes" section):

  1. tg68k.v — FC output is already exposed, should be ready
  2. addrDecoder.v — Needs a selectFPU signal: decode FC=7 + addr $0002_xxxx to select the FPU on the bus
  3. LBMacTwo.sv — Instantiate mc68881_top, connect data bus, handle DSACK timing
  4. dataController_top.sv — Add FPU to the data mux (or handle at top level)
  5. files.qip — Add mc68881.qip reference
  6. mc68881 sources — The VHDL-to-Verilog conversion is blocked (ghdl synth issues), but for Quartus FPGA the VHDL
  sources work directly via mc68881.qip
  7. sense_n inout port — The FPU's sense_n needs handling (directly active for our use case, likely tie low or
  connect to cpID decode)

