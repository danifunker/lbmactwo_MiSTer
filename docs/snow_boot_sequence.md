       Comprehensive Analysis of Snow ROM Boot Behavior

       Based on thorough investigation of the Snow Mac II emulator codebase, here are the answers to your key questions:

       1. ROM Tracing and Logging Capabilities

       Snow has built-in instruction history export but no pre-configured ROM address annotations:

       - Instruction History: Located in /Users/dani/repos/snow/core/src/cpu_m68k/cpu.rs
         - HistoryEntry struct tracks PC, raw instruction, cycles, register state
         - HistoryEntryInstruction stores initial_regs before execution
         - Can be enabled/disabled via cpu.enable_history(bool)
       - Export Capability: /Users/dani/repos/snow/frontend_egui/src/widgets/instruction_history.rs
         - Exports history as pipe-separated CSV with columns: PC|Raw|Cycles|Instruction|D0-D7|A0-A7|SR
         - No built-in ROM routine naming/annotations
         - ROM addresses like $6DD8 and $26CA8 would need manual lookup in the ROM

       2. Offset 0x015D Search Results

       No direct reference to 0x015D or 0x15D found in Snow codebase. However, this offset is relative to A3 in the ROM
       code, making it:
       - Likely a structure field offset within a data block pointed to by A3
       - Could be in a Mac II-specific initialization structure (not a VIA register offset, which are at fixed
       addresses)

       3. Bit 5 Testing and ADB State Machine

       The bit 5 test (BTST #5, $015D(A3)) is NOT directly ADB-related in Snow's VIA implementation:

       VIA Register B Bit Assignments (from /Users/dani/repos/snow/core/src/mac/via.rs, lines 75-88):
       Bit 3: adb_int (ADB interrupt status) - INPUT for ADB models
       Bit 4: adb_st0 (ADB State 0)          - OUTPUT to ADB
       Bit 5: adb_st1 (ADB State 1)          - OUTPUT to ADB
       Bit 6: scsi_int (SCSI interrupt)      - INPUT (SE+ models)

       ADB State Transitions (from /Users/dani/repos/snow/core/src/mac/adb/transceiver.rs):
       - Idle (ST0=1, ST1=1)
       - Command (ST0=0, ST1=0) - CPU writes shift register
       - Data1 (ST0=1, ST1=0) - Response phase
       - Data2 (ST0=0, ST1=1) - Alternative response phase

       The ROM code at $6DD8 is NOT polling ADB directly; it's polling something from a structure at A3+$15D (likely a
       control/status block, possibly related to initialization tables or device detection).

       4. ADB Transceiver INT Line Implementation

       The ADB INT line behavior is well-defined and state-dependent:

       Signaling in each phase (from transceiver.rs, lines 65-78):
       match self.state {
           Command => INT = false,          // Never asserted during command
           Data1   => INT = (cmd.is_empty && response.is_empty),  // COMPLETION signal
           Data2   => INT = device_has_srq(),                      // SRQ pending
           Idle    => INT = device_has_srq(),                      // SRQ pending
       }

       Critical Detail: In Data1 phase, INT signals command/response completion:
       - TRUE = Response fully clocked out OR device didn't respond (e.g., keyboard Talk with no events)
       - FALSE = More data to clock
       - This is why ADB responses must be even-length (to maintain proper INT timing)

       5. VIA1 Shift Register Completion Signaling

       The keyboard ready interrupt (IFR bit 2, kbdready) is the key:

       Shift Register Timing (from via.rs lines 567-587):
       SHIFT_DELAY = (ONESEC_TICKS * 3 / 1000) ≈ 2,350 ticks
                     ≈ 144 microseconds at E-clock speed

       Completion Flow:
       1. ROM writes data to Shift Register + sets ACR keyboard mode
       2. VIA waits SHIFT_DELAY ticks
       3. When timer expires:
         - For shift-OUT: calls adb.data_in(byte) or keyboard.cmd(byte)
         - For shift-IN: loads response into SR, sets IFR.kbdready=true
       4. ROM reads IFR and polls bit 2 (kbdready)

       No automatic SR interrupt flag bit 2 setting occurs on VIA1 in Mac II—it's explicitly set by the shift register
       completion timer.

       6. Delay Loop (DBF) Handling

       Snow has NO special fastpath optimizations for delay loops:

       DBF Instruction Implementation (from cpu.rs, lines 2845+):
       fn op_dbcc(&mut self, instr: &Instruction) -> Result<()> {
           if !self.cc(instr.get_cc()) {
               let dn = self.regs.read_d::<Word>(instr.get_op2()).wrapping_sub(1);
               self.regs.write_d::<Word>(instr.get_op2(), dn);

               if dn != 0xFFFF {
                   // Branch taken - loop continues
                   self.advance_cycles(2)?;
                   // ... branch to displacement address
               } else {
                   // Loop terminates (dn wrapped to 0xFFFF)
                   self.advance_cycles(4)?;
               }
           } else {
               // Condition true - exit loop
               self.advance_cycles(2)?;
           }
       }

       No cycle-skipping for tight delay loops—each DBF iteration executes fully with full cycle accounting.

       7. Boot-Time Logging Output

       Snow produces NO special boot-time logging by default. The history system is:
       - opt-in via UI/config (enable_history flag)
       - not automatically logging ROM execution
       - Must be explicitly exported from the frontend UI

       To trace boot ROM execution, you'd need to:
       1. Enable instruction history in the emulator UI
       2. Run until the loop
       3. Export history to CSV
       4. Manual search for PC addresses $6DD8/$26CA8

       Key Architectural Findings

       For the FPGA implementation, the critical understanding:

       1. Loop 1 at $6DD8 (BTST #5, $015D(A3)) is NOT polling VIA Register B bit 5 (adb_st1)—it's polling a ROM
       structure field that happens to be offset $15D from wherever A3 is loaded with
       2. Loop 2 at $26CA8 (DBF D0/$D5) is a pure delay loop executing full CPU cycles with no fastpath—Snow will
       execute it in real-time without optimization
       3. Shift Register Completion: The ROM must poll IFR bit 2 (kbdready), not a VIA Register B input bit. This is set
        by the completion timer in via.rs
       4. VIA ADB State Outputs (ST0/ST1 bits 4-5 of Register B) must be properly managed as the ROM writes them to
       control ADB bus state machine transitions

       Critical Implementation Notes for LBMacTwo FPGA

       - The offset $15D from A3 likely refers to a Mac II startup parameter block or device detection table—research
       the Mac II ROM structure, not ADB directly
       - Bit 5 that's being tested is not an ADB input; ADB inputs are VIA Register A (model sense bits) and Register B
       bit 3 (adb_int)
       - VIA Register B bits 4-5 are outputs to ADB (ST0/ST1 state machine control)
       - The delay loop will execute at real CPU speed without fastpath optimization

       File Paths for Reference

       - VIA implementation: /Users/dani/repos/snow/core/src/mac/via.rs (lines 16-649)
       - ADB transceiver: /Users/dani/repos/snow/core/src/mac/adb/transceiver.rs (lines 8-208)
       - DBF instruction: /Users/dani/repos/snow/core/src/cpu_m68k/cpu.rs (line 2845+)
       - Instruction history export: /Users/dani/repos/snow/frontend_egui/src/widgets/instruction_history.rs (lines