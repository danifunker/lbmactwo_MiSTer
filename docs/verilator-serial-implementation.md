# Plan: SCC Serial Terminal for Verilator Simulator

## Context

The Mac II ROM's test manager outputs diagnostic info over SCC Channel A serial when boot errors occur. Currently the serial pins are tied to idle in the sim (`verilator/sim.v:188-192`), so we can't see this output or interact with diagnostics. Adding a serial terminal UI lets us observe ROM diagnostics and send input — critical for debugging the RAM test failure and other boot issues.

The design is split into a **reusable core-agnostic component** (soft UART + terminal widget) and **minimal core-specific wiring**, so this can be applied to other MiSTer cores.

## Implementation Status

### DONE - Files Created
- `verilator/sim/sim_serial.h` — SoftUART + SimSerialTerminal class declarations
- `verilator/sim/sim_serial.cpp` — Full implementation of both classes

### DONE - Files Modified
- `verilator/sim.v` — Added `serial_txd` output and `serial_rxd` input ports; unwired serial idle ties; `serialOut` now driven by SCC, `serialIn` driven by `serial_rxd`
- `verilator/sim_main.cpp` — Added `#include "sim_serial.h"`, global `SimSerialTerminal serialTerminal`, tick logic in rising edge block, ImGui Draw call, baud config auto-update from `baud_divid_speed_a`
- `verilator/Makefile` — Added `sim/sim_serial.cpp` to C_SRC

### DONE - Build
- Compiles and links cleanly (`make clean && make`)
- Verilator generates `serial_txd` as output port, correctly assigned from `emu__DOT__dc0__DOT__s__DOT__tx_internal_a`

### DONE - Baud rate config
- `uart_setup_tx_a` (31-bit wire) is NOT exposed by Verilator — had to use `baud_divid_speed_a` (24-bit reg) directly instead
- Using `UpdateConfigDirect(baud_div, 8, 1, false, false)` — hardcoded 8N1 which matches Mac II ROM usage
- Default baud divider is 3385 (~9600 baud at 32.5MHz), confirmed by SCC_SERIAL_IN byte timing (33861 clocks between bytes = 3386 cpb)

### DONE - RAM test investigation (pre-serial-terminal work)
- `sim_ram.v` RAM range expanded from 1MB to 4MB (matching `configRAMSize=2'b10`)
- WLCS skip marker at $0CFC confirmed working for 2nd/3rd RAM tests
- First RAM test at ROM $B6 runs unconditionally (no WLCS gate) — this was causing failure with 1MB sim RAM
- With 4MB, first test passes (720 cycles), but a second test still fails and triggers ERROR1HANDLER

## Current Blocker: `serial_txd` Pin Not Toggling

The soft UART receives no data because `serial_txd` never transitions from idle (high).

**Evidence:**
- SCC_SERIAL_OUT messages confirm the TX UART *internally* completes byte transmissions (at cycles 6M and 14M)
- SCC_SERIAL_IN at cycle 35M shows "TESTIN..." received via loopback
- But a pin-transition debug log (`SERIAL_TXD: 0->1 / 1->0`) in sim_main.cpp produces NO output — the pin is stuck at 1

**Verilator generated code confirms correct wiring:**
```cpp
// In Vemu___024root__2.cpp:
vlSelfRef.serial_txd = vlSelfRef.emu__DOT__dc0__DOT__s__DOT__tx_internal_a;
```

**Hypothesis to investigate next session:**
1. `tx_internal_a` might be evaluated in a different Verilator scheduling region than where we read `serial_txd` — the combinational assignment may not propagate before we sample it
2. The SCC TX UART might initialize to idle=1 and the bytes it "sends" (0x00) may not actually toggle the pin if the TX enable (WR5 bit 3) isn't set — the UART would complete internally but the output mux might hold txd high
3. The timing of when sim_main.cpp reads `serial_txd` relative to eval() might matter — currently it's read AFTER eval on rising edges, which should be correct, but worth double-checking

**Next step:** Add `$display` in scc.v to print `tx_internal_a` transitions, confirming whether the issue is in the Verilog or the C++ readback.

## Architecture (for reference / portability)

### Approach: Bit-Level Serial
Soft UART in C++ watches SCC's `txd` output pin and drives `rxd` input at the wire level. Tests full serial path.

### Portability to Other Cores
To reuse in another core's Verilator sim:
1. Copy `sim/sim_serial.h` and `sim/sim_serial.cpp` (unchanged)
2. Add `serial_txd` output and `serial_rxd` input to that core's sim wrapper
3. In sim_main.cpp: call `Tick()` each clock, read baud config from that core's UART registers (or use `UpdateConfigDirect()` for non-wbuart32 UARTs)

### Verification (once pin issue resolved)
1. **Idle state**: no garbage in terminal when SCC hasn't been configured yet
2. **Baud tracking**: stderr log when config changes
3. **RX display**: run sim past boot errors — test manager output should appear as ASCII text in the terminal
4. **TX input**: type a character, verify SCC `rx_wr_a` fires
5. **Loopback**: ROM diagnostic SCC loopback test should work with terminal echo

## Also: Debug instrumentation to clean up
- `sim_ram.v`: WLCS read/write watchpoints (lines ~89-107) — temporary, can remove
- `sim_main.cpp`: RAM_TEST ENTRY/EXIT watchpoints, RAMTEST_BUS logging, SERIAL_TXD transition debug — temporary
- `sim_serial.cpp`: SERIAL_RX fprintf in AddReceivedChar — temporary, remove once working
