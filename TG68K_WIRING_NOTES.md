# TG68K VHDL Wrapper Wiring Guide

## Overview
This document explains how the TG68K VHDL wrapper (TG68K.vhd) is wired in the Mac II core for 68030 operation.

## CPU Configuration

### Generic Parameters
```verilog
TG68K #(
    .CPU(2'b11),        // 68030 mode (00=68000, 01=68010, 10=68020, 11=68030)
    .FPU_Enable(1)      // FPU enabled (0=disabled, 1=enabled)
)
```

## Port Connections

### Clock and Reset
- **CLK**: Main system clock (clk_sys)
- **RESET**: Bidirectional reset (inout) - connected to _cpuReset
- **HALT**: Bidirectional halt (inout) - connected to _cpuReset
- **BERR**: Bus error input - tied to 0 (not used)

### Interrupts
- **IPL[2:0]**: Interrupt Priority Level input - from interrupt controller

### Address and Data
- **ADDR[31:0]**: 32-bit address bus output
- **DATA[15:0]**: 16-bit bidirectional data bus (inout)
- **FC[2:0]**: Function code output (supervisor/user, program/data)

### Asynchronous Bus Control
- **AS**: Address Strobe output (active low)
- **UDS**: Upper Data Strobe output (active low)
- **LDS**: Lower Data Strobe output (active low)
- **RW**: Read/Write output (1=read, 0=write)
- **DTACK**: Data Transfer Acknowledge input (active low)

### Synchronous Bus Control (6800 Peripheral Mode)
- **E**: E clock output for 6800-style peripherals (VIA)
- **VPA**: Valid Peripheral Address input (active low)
- **VMA**: Valid Memory Address output (active low)

### 68030 Cache Interface
The 68030 has an internal cache system with the following interface:

- **cache_req**: Cache request output
- **cache_addr[31:0]**: Cache memory address
- **cache_data[15:0]**: Cache data input (from external memory)
- **cache_ack**: Cache acknowledge input
- **cache_burst**: Cache burst mode indicator
- **cache_burst_len[2:0]**: Cache burst length (number of words)
- **cache_hit**: Cache hit indicator output
- **cache_miss**: Cache miss indicator output

**Current Status**: Cache interface is not yet implemented. All inputs are tied to safe defaults:
- cache_data = 16'h0000
- cache_ack = 1'b0

## Bidirectional Data Bus Handling

The TG68K VHDL entity uses a true bidirectional `DATA` port (inout). This requires special handling:

```verilog
// Bidirectional DATA bus
wire [15:0] tg68_data_bidir;
assign tg68_data_bidir = tg68_rw ? 16'hzzzz : cpuDataOut;  // Tri-state when reading
```

When RW=1 (reading), the CPU tri-states its output, allowing external devices to drive the bus.
When RW=0 (writing), the CPU drives the bus with data from cpuDataOut.

## E Clock Edge Detection

The TG68K outputs a synchronous E clock for 6800-style peripherals (like the VIA). The Mac needs rising and falling edge signals:

```verilog
reg tg68_E_d;
always @(posedge clk_sys) begin
    if (clk8_en_p) begin
        tg68_E_d <= tg68_E;
    end
end
assign tg68_E_rising  = clk8_en_p && !tg68_E_d &&  tg68_E;
assign tg68_E_falling = clk8_en_p &&  tg68_E_d && !tg68_E;
```

## Important Notes

1. **No phi1/phi2 Clocking**: Unlike some CPU wrappers, the TG68K VHDL entity uses internal clock generation. It only needs the main CLK input.

2. **Bidirectional Reset/Halt**: These are inout ports that can be driven by external reset circuits or the CPU itself during certain operations.

3. **68030 Features**: 
   - Full 32-bit addressing
   - Instruction and data caches (not yet implemented in memory system)
   - FPU support (enabled via generic parameter)
   - PMMU support (present in CPU core)

4. **Cache Implementation**: Currently disabled by tying inputs to safe values. Future implementation would require:
   - Cache memory (separate from main RAM)
   - Burst transfer support
   - Cache line management
   - Cache invalidation handling

5. **CPU Mode Selection**: The CPU mode is set via the `CPU` generic parameter at compile time, not via a runtime port.

## Future Enhancements

1. **Cache Support**: Implement external cache memory and burst transfer logic
2. **PMMU Support**: Add memory management unit support for virtual memory
3. **Bus Arbitration**: Add BR/BG/BGACK signals for DMA support (currently commented out in entity)
4. **Better Reset Handling**: Use separate reset signals instead of tying RESET and HALT together

## References

- TG68K.vhd: Main VHDL wrapper entity
- TG68KdotC_Kernel: Core CPU implementation
- Motorola 68030 User's Manual: Official CPU documentation
