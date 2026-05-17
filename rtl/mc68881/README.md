# MC68881 FPU Integration

## Source

Verilog is auto-generated from the canonical VHDL sources in the
[68881-fpga](../../../68881-fpga) repository using `ghdl --synth`.

The file `fpu_lite/mc68881_top.v` uses the **fpu_lite** variant — MC68040
hardware subset (11 core ALU ops). All submodules are inlined into this single file.
Excludes trig engine, FSCALE/FSGLDIV/FSGLMUL, FMOD/FREM, FGETEXP/FGETMAN.
Saves ~45% LUTs and ~50% DSPs vs full MC68881. Unsupported ops return zero in 1 cycle.

## Updating

Generate Verilog in the upstream 68881-fpga repo, then copy:

```bash
cd ../68881-fpga
bash ./scripts/convert_to_verilog.sh
cp src/*.vhd                        ../lbmactwo_MiSTer/rtl/mc68881/vhdl/
cp verilog/fpu_lite/mc68881_top.v   ../lbmactwo_MiSTer/rtl/mc68881/fpu_lite/
# Strip ghdl-emitted $fatal assertions (VHDL `assert severity failure`)
# so the verilator bench doesn't abort on benign reset/init checks:
sed -i.bak 's/\$fatal(1, "assertion failure n[0-9]*");/;/g' \
    ../lbmactwo_MiSTer/rtl/mc68881/fpu_lite/mc68881_top.v
rm ../lbmactwo_MiSTer/rtl/mc68881/fpu_lite/mc68881_top.v.bak
```

**Important:** keep `rtl/mc68881/vhdl/` in sync with `68881-fpga/src/`.
The VHDL is the source of truth (Quartus uses it directly). If they
drift, the .v file generated from one will encode different opcode
IDs than the .vhd the other half of the project expects — see the
2026-05-16 incident where a stale `mc68881_pkg.vhd` had FMOVE
decode_id=0x05 (custom) instead of 0x00 (M68881 native), causing all
F-line FPU instructions dispatched from TG68K to silently decode as
NOP. Symptom: FPU returned Response=0x0000 immediately and never
requested operand data.

To switch to the full MC68881 (37 ALU ops), copy `verilog/mc68881_top.v` instead
and update `mc68881.qip` to point to it.

## Build

For Quartus 17.0.2 (MiSTer), the Verilog file is referenced via `mc68881.qip`.

## Integration Notes

- The FPU operates in **CIR dialog mode** (authentic MC68881 coprocessor protocol)
- TG68K (68020 mode) drives the CIR protocol via FC=7 bus cycles
- The FPU's CIR register map uses non-standard addresses for registers that
  overlap with peripheral-mode registers. Address remapping is handled in
  `LBMacTwo.sv`:
  - Standard reg 0 (Response CIR) -> mc68881_top reg 13
  - Standard reg 2 (Save CIR)    -> mc68881_top reg 12
  - Standard reg 3 (Restore CIR) -> mc68881_top reg 28
- Data bus: 16-bit (TG68K word-sized CIR transfers), connected via d_in[15:0]
- sense_n is an inout driven by the FPU to indicate presence
- The FPU runs on clk_sys (~32.5 MHz), within the design target of 33 MHz
