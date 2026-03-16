# TG68K Coprocessor Protocol Implementation Plan

## Goal
Enable TG68K to execute F-line coprocessor instructions by implementing the M68020 CIR
(Coprocessor Interface Register) bus dialog protocol. This allows an external MC68881 FPU
to work with TG68K.

## Target Files
- `rtl/tg68k/TG68K_Pack.vhd`, `rtl/tg68k/TG68KdotC_Kernel.vhd`
- `rtl/tg68k/TG68K_Pack.sv` (Verilator mirror)

## Architecture Summary (TG68K internals)

### State machine
- `state` (2 bits): "00"=fetch, "01"=idle, "10"=read data, "11"=write data
- `busstate` = `state` (directly drives bus)
- `setstate` (combinational) sets `state` on next clock edge
- `micro_state` (enum): sequences multi-cycle operations
- `next_micro_state` (combinational) sets `micro_state` on next `clkena_lw`

### FC (Function Code) generation
- FC[2]: supervisor bit (from FlagsSR[5])
- FC[1:0]: generated from setstate and PCbase
- CPU space = FC="111"

### CIR Address Format
```
addr[31:16] = $0002
addr[15:13] = cpID (from opcode[11:9], FPU=001)
addr[12:6]  = 0000000
addr[5:1]   = CIR register number
addr[0]     = 0 (word aligned)
```

### CIR Registers (from mc68881_pkg.vhd)
| Name       | Reg# | Addr   | Access | Purpose                    |
|------------|------|--------|--------|----------------------------|
| Response   | 0    | $00    | R      | Status/response primitives |
| Control    | 1    | $02    | W      | Exception acknowledge      |
| Save       | 2    | $04    | R      | Format word (cpSAVE)       |
| Restore    | 3    | $06    | W      | Format word (cpRESTORE)    |
| OpWord     | 4    | $08    | W      | Instruction type/opcode    |
| Command    | 5    | $0A    | W      | Source format, reg indices  |
| Condition  | 7    | $0E    | W      | Condition predicate        |
| Operand    | 8    | $10    | R/W    | Data transfer              |
| RegSelect  | 10   | $14    | R      | FP register list           |
| InstAddr   | 12   | $18    | W      | FPIAR snapshot             |
| OpAddr     | 14   | $1C    | R      | EA address                 |

### Response Word Format (bits [15:13])
| Bits | Primitive                  | Action                              |
|------|----------------------------|-------------------------------------|
| 000  | Busy                       | Re-read Response CIR                |
| 001  | Null                       | Instruction complete                |
| 010  | Supervisor Check           | Verify SVmode                       |
| 011  | Transfer to Coprocessor    | CPU sends data via Operand CIR      |
| 100  | Transfer from Coprocessor  | CPU reads data from Operand CIR     |
| 101  | Pre-instruction Exception  | Take exception before execution     |
| 110  | Mid-instruction Exception  | Take exception during execution     |
| 111  | Post-instruction Exception | Take exception after execution      |

### F-line Opcode Encoding
```
15..12 = 1111
11..9  = cpID (001=FPU)
 8..6  = type:
         000 = cpGEN (FADD, FMUL, FMOVE, etc.)
         001 = cpScc/cpDBcc/cpTRAPcc (FScc, FDBcc, FTRAPcc)
         010 = cpBcc.W (FBcc with 16-bit displacement)
         011 = cpBcc.L (FBcc with 32-bit displacement)
         100 = cpSAVE (FSAVE)
         101 = cpRESTORE (FRESTORE)
 5..0  = EA mode/register (varies by type)
```

---

## Phase 1: MOVES + cpGEN (DONE)

### Status: Implemented

Implements MOVES instruction (FC override with SFC/DFC) and cpGEN (general
coprocessor instructions like FADD, FMUL, FMOVE). This covers FPU detection
via `moves.w ($22000).l,D1` and all register-to-register and memory-source
FPU operations.

### Changes Made

#### TG68K_Pack.vhd
- Added micro_states: `cp_write_cmd`, `cp_read_resp`, `cp_idle_resp`, `cp_xfer_to`, `cp_xfer_from`
- Added exec flag: `opcCPcmd` (89), updated `lastOpcBit` to 89

#### TG68KdotC_Kernel.vhd
- New signals: `cp_fc_override`, `cp_cir_reg`, `cp_xfer_cnt`, `set_cpaddr`, `moves_fc_en`, `moves_fc_val`
- MOVES decode: replaced TODO with ea_build + SFC/DFC FC override
- FC override: cp_fc_override forces FC=7, moves_fc_en applies SFC/DFC
- 1111 handler: cpGEN enters cp_write_cmd micro_state
- data_write_tmp: opcCPcmd loads sndOPC as command word
- CIR address: set_cpaddr generates $0002_xxxx addresses
- Micro_state handlers: full CIR dialog loop (write cmd → read resp → decode → transfer)
- Registered process: cp_fc_override/cp_xfer_cnt/moves_fc_en management

### cpGEN Protocol Flow
```
1. Fetch opcode ($F2xx) → decode as cpGEN (type=000)
2. Fetch sndOPC (command word) → load into data_write_tmp
3. cp_write_cmd: Write command word to Command CIR ($0002_200A), FC=7
4. cp_read_resp: Read Response CIR ($0002_2000), FC=7
5. cp_idle_resp: Decode response[15:13]:
   - "000" Busy → re-read (goto cp_read_resp)
   - "001" Null → done
   - "011" Transfer to copro → cp_xfer_to loop
   - "100" Transfer from copro → cp_xfer_from loop
   - others → trap
6. Transfer loops: read/write Operand CIR ($0002_2010), count down cp_xfer_cnt
7. After transfer complete → read response again (goto cp_read_resp)
```

---

## Phase 2: cpSAVE / cpRESTORE [DONE]

### Goal
Implement FSAVE and FRESTORE for FPU context switching. Required by Mac II ROM
for multitasking and exception handling.

### Protocol: cpSAVE (FSAVE)

FSAVE saves the FPU's internal state to memory via the EA specified in the instruction.

```
1. Decode: opcode type[8:6]="100", validate EA (must be control alterable or -(An))
2. Write OpWord to OpWord CIR ($08) — tells FPU "save your state"
3. Read Save CIR ($04) — returns format word:
   - $0000 = Null frame (FPU uninitialized, no data follows)
   - $0018 = Idle frame (24 bytes = 6 longwords follow)
   - $00B4 = Busy frame (180 bytes = 45 longwords follow)
4. Write format word to EA
5. If not null: read N longwords from Operand CIR ($10), write each to EA
6. Done (no Response CIR read needed — SAVE uses Save CIR directly)
```

### Protocol: cpRESTORE (FRESTORE)

FRESTORE restores the FPU's internal state from memory.

```
1. Decode: opcode type[8:6]="101", validate EA (must be control or (An)+)
2. Write OpWord to OpWord CIR ($08) — tells FPU "prepare for restore"
3. Read format word from EA
4. Write format word to Restore CIR ($06)
   - FPU validates format:
     - $0000 = Null → reset FPU to power-on, no data follows
     - $0018 = Idle → expect 6 longwords
     - $00B4 = Busy → expect 45 longwords
     - Other = Pre-Instruction Exception (format error, vector 14)
5. If not null: read N longwords from EA, write each to Operand CIR ($10)
6. Read Response CIR ($00) for completion/error
7. Done
```

### New micro_states needed
```vhdl
cp_save_opw,        -- Write OpWord for cpSAVE
cp_save_read_fmt,   -- Read format word from Save CIR
cp_save_write_ea,   -- Write format word to EA
cp_save_read_data,  -- Read frame data from Operand CIR
cp_save_write_data, -- Write frame data to EA
cp_restore_opw,     -- Write OpWord for cpRESTORE
cp_restore_read_ea, -- Read format word from EA
cp_restore_write_fmt,-- Write format word to Restore CIR
cp_restore_read_data,-- Read frame data from EA
cp_restore_write_data,-- Write frame data to Operand CIR
cp_restore_resp     -- Read Response CIR after restore
```

### New signals
```vhdl
signal cp_frame_cnt   : std_logic_vector(5 downto 0); -- Up to 45 longwords
signal cp_save_fmt    : std_logic_vector(15 downto 0); -- Saved format word
signal cp_ea_addr     : std_logic_vector(31 downto 0); -- Current EA pointer
```

### 1111 handler changes

Replace cpSAVE trap block:
```vhdl
ELSIF opcode(8 downto 6)="100" THEN
    -- cpSAVE: validate EA modes
    IF SVmode='1' THEN
        IF opcode(5 downto 3)="100" THEN
            -- -(An) predecrement mode
            datatype <= "01"; -- word
            next_micro_state <= cp_save_opw;
        ELSIF opcode(5 downto 4)/="00" AND opcode(5 downto 3)/="011" AND
              (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00") THEN
            -- Control alterable modes
            ea_build_now <= '1';
            datatype <= "01";
            next_micro_state <= cp_save_opw;
        ELSE
            trap_illegal <= '1';
            trapmake <= '1';
        END IF;
    ELSE
        trap_priv <= '1';
        trapmake <= '1';
    END IF;
```

Replace cpRESTORE trap block:
```vhdl
ELSIF opcode(8 downto 6)="101" THEN
    -- cpRESTORE: validate EA modes
    IF SVmode='1' THEN
        IF opcode(5 downto 3)="011" THEN
            -- (An)+ postincrement mode
            datatype <= "01"; -- word
            next_micro_state <= cp_restore_opw;
        ELSIF opcode(5 downto 4)/="00" AND opcode(5 downto 3)/="100" AND
              (opcode(5 downto 3)/="111" OR opcode(2 downto 0)/="100") THEN
            -- Control modes
            ea_build_now <= '1';
            datatype <= "01";
            next_micro_state <= cp_restore_opw;
        ELSE
            trap_illegal <= '1';
            trapmake <= '1';
        END IF;
    ELSE
        trap_priv <= '1';
        trapmake <= '1';
    END IF;
```

### Micro_state handlers (cpSAVE)

```vhdl
WHEN cp_save_opw =>
    -- Write OpWord to OpWord CIR ($08)
    -- OpWord value: type="100" in bits [8:6]
    set_cpaddr <= '1';
    cp_cir_reg <= "00100"; -- OpWord CIR (register 4)
    setstate <= "11";      -- bus write
    datatype <= "01";      -- word
    next_micro_state <= cp_save_read_fmt;

WHEN cp_save_read_fmt =>
    -- Read format word from Save CIR ($04)
    set_cpaddr <= '1';
    cp_cir_reg <= "00010"; -- Save CIR (register 2)
    setstate <= "10";      -- bus read
    datatype <= "01";      -- word
    next_micro_state <= cp_save_write_ea;

WHEN cp_save_write_ea =>
    -- Write format word to EA (memory)
    -- cp_save_fmt was latched from last_data_read
    setstate <= "11";      -- bus write to EA
    datatype <= "01";      -- word
    -- Check format: if null ($0000), done
    IF cp_save_fmt = X"0000" THEN
        next_micro_state <= idle; -- Null frame, nothing more
    ELSE
        -- Determine frame size from format word
        -- $0018 → 6 longwords (12 words), $00B4 → 45 longwords (90 words)
        next_micro_state <= cp_save_read_data;
    END IF;

WHEN cp_save_read_data =>
    -- Read one word from Operand CIR ($10)
    set_cpaddr <= '1';
    cp_cir_reg <= "01000"; -- Operand CIR (register 8)
    setstate <= "10";      -- bus read
    datatype <= "01";      -- word
    next_micro_state <= cp_save_write_data;

WHEN cp_save_write_data =>
    -- Write data word to EA (memory), advance address
    setstate <= "11";      -- bus write
    datatype <= "01";      -- word
    IF cp_frame_cnt = "000000" THEN
        next_micro_state <= idle; -- All frame data written
    ELSE
        next_micro_state <= cp_save_read_data; -- More words
    END IF;
```

### Micro_state handlers (cpRESTORE)

```vhdl
WHEN cp_restore_opw =>
    -- Write OpWord to OpWord CIR ($08)
    set_cpaddr <= '1';
    cp_cir_reg <= "00100"; -- OpWord CIR (register 4)
    setstate <= "11";      -- bus write
    datatype <= "01";      -- word
    next_micro_state <= cp_restore_read_ea;

WHEN cp_restore_read_ea =>
    -- Read format word from EA (memory)
    setstate <= "10";      -- bus read from EA
    datatype <= "01";      -- word
    next_micro_state <= cp_restore_write_fmt;

WHEN cp_restore_write_fmt =>
    -- Write format word to Restore CIR ($06)
    set_cpaddr <= '1';
    cp_cir_reg <= "00011"; -- Restore CIR (register 3)
    setstate <= "11";      -- bus write
    datatype <= "01";      -- word
    -- Check format: if null, done; otherwise read frame data
    IF cp_save_fmt = X"0000" THEN
        next_micro_state <= cp_restore_resp;
    ELSE
        next_micro_state <= cp_restore_read_data;
    END IF;

WHEN cp_restore_read_data =>
    -- Read one word from EA (memory), advance address
    setstate <= "10";      -- bus read
    datatype <= "01";      -- word
    next_micro_state <= cp_restore_write_data;

WHEN cp_restore_write_data =>
    -- Write data word to Operand CIR ($10)
    set_cpaddr <= '1';
    cp_cir_reg <= "01000"; -- Operand CIR (register 8)
    setstate <= "11";      -- bus write
    datatype <= "01";      -- word
    IF cp_frame_cnt = "000000" THEN
        next_micro_state <= cp_restore_resp;
    ELSE
        next_micro_state <= cp_restore_read_data; -- More words
    END IF;

WHEN cp_restore_resp =>
    -- Read Response CIR for completion/error
    set_cpaddr <= '1';
    cp_cir_reg <= "00000"; -- Response CIR (register 0)
    setstate <= "10";      -- bus read
    datatype <= "01";      -- word
    next_micro_state <= cp_idle_resp; -- Reuse response decoder
```

### Registered process additions

```vhdl
-- In reset block:
cp_frame_cnt <= (others => '0');
cp_save_fmt <= (others => '0');

-- In clkena_lw block:
-- Latch format word when reading Save CIR
IF micro_state = cp_save_read_fmt THEN
    cp_save_fmt <= last_data_read(15 downto 0);
    -- Decode frame size
    CASE last_data_read(15 downto 0) IS
        WHEN X"0000" => cp_frame_cnt <= "000000"; -- Null
        WHEN X"0018" => cp_frame_cnt <= "001011"; -- 12 words (6 longs) - 1
        WHEN X"00B4" => cp_frame_cnt <= "101001"; -- 90 words (45 longs) - 1 (actually 89)
        WHEN OTHERS  => cp_frame_cnt <= "000000"; -- Unknown
    END CASE;
END IF;
-- Latch format word when reading EA for RESTORE
IF micro_state = cp_restore_read_ea THEN
    cp_save_fmt <= last_data_read(15 downto 0);
    CASE last_data_read(15 downto 0) IS
        WHEN X"0000" => cp_frame_cnt <= "000000";
        WHEN X"0018" => cp_frame_cnt <= "001011";
        WHEN X"00B4" => cp_frame_cnt <= "101001";
        WHEN OTHERS  => cp_frame_cnt <= "000000";
    END CASE;
END IF;
-- Decrement frame counter during data transfer
IF (micro_state = cp_save_write_data OR micro_state = cp_restore_write_data)
   AND cp_frame_cnt /= "000000" THEN
    cp_frame_cnt <= cp_frame_cnt - 1;
END IF;
```

### EA address management

cpSAVE/cpRESTORE need to alternate between CIR addresses (FC=7) and EA addresses
(FC=user/supervisor). The EA address comes from the normal ea_build path. Key issue:
the CIR address and EA address use different address generation paths.

Options:
1. Save/restore memaddr_reg around CIR accesses (complex)
2. Use cp_ea_addr register to track EA pointer separately
3. Use existing ea_data register + manual address management

Option 2 is cleanest: latch the EA from addr after ea_build, then use cp_ea_addr
for memory accesses and set_cpaddr for CIR accesses. Increment cp_ea_addr by 2
after each word transfer.

---

## Phase 3: FBcc / FScc / FDBcc / FTRAPcc

### Status: FBcc DONE, FScc (reg) DONE, FTRAPcc DONE, FDBcc/FScc (mem) TODO

### Goal
Implement conditional FPU instructions. The FPU evaluates the condition internally;
the CPU just needs to send the condition predicate and act on the response.

### Instruction Encoding

```
FBcc.W:    1111_001_010_xxxxxx  (type=010, 16-bit displacement follows)
FBcc.L:    1111_001_011_xxxxxx  (type=011, 32-bit displacement follows)
           Condition code in opcode[5:0]

FScc:      1111_001_001_MMMRRR  (type=001, EA in [5:0])
           sndOPC[5:0] = condition code

FDBcc:     1111_001_001_001RRR  (type=001, EA mode=001 = Dn)
           sndOPC[5:0] = condition code

FTRAPcc:   1111_001_001_111_1xx (type=001, EA=111_1xx)
           sndOPC[5:0] = condition code
           111_010 = .W operand, 111_011 = .L operand, 111_100 = no operand
```

### Protocol (all conditional instructions)

```
1. Write OpWord to OpWord CIR ($08) — type field distinguishes instruction
2. Write condition predicate to Condition CIR ($0E)
   - Bits [5:0] = condition code from opcode or sndOPC
3. Read Response CIR ($00)
4. Decode response:
   - Null with bit 0 = condition result (true/false)
   - Exception response → take FPU exception
5. CPU acts on result:
   - FBcc: if true, add displacement to PC (branch)
   - FScc: if true, set EA byte to $FF; else set to $00
   - FDBcc: if false, decrement Dn.W; if Dn.W != -1, branch
   - FTRAPcc: if true, take trap (vector 7)
```

### Response Word for Conditionals

```
Bit 0: cond_true (condition evaluated true)
Bit 4: bsun_event (Branch/Set on Unordered — signaling NaN)
Bits [15:13]: response primitive (001=Null for success, 111=Post-exception)
```

### New micro_states needed
```vhdl
cp_cond_opw,      -- Write OpWord for conditional
cp_cond_write,    -- Write condition code to Condition CIR
cp_cond_resp,     -- Read Response CIR
cp_cond_decode,   -- Decode response and act
cp_fbcc_branch,   -- FBcc: apply displacement to PC
cp_fscc_set,      -- FScc: write $FF/$00 to EA
cp_fdbcc_dec,     -- FDBcc: decrement Dn, check for branch
cp_ftrapcc_trap   -- FTRAPcc: take trap if condition true
```

### 1111 handler changes

Replace the Phase 3 trap block:
```vhdl
ELSE
    -- Conditional FPU instructions
    IF opcode(8 downto 6)="001" THEN
        -- FScc / FDBcc / FTRAPcc
        IF opcode(5 downto 3)="001" THEN
            -- FDBcc (EA mode = data register direct)
            datatype <= "01";
            next_micro_state <= cp_cond_opw;
        ELSIF opcode(5 downto 3)="111" AND opcode(2)='1' THEN
            -- FTRAPcc (EA = 111_1xx)
            datatype <= "01";
            next_micro_state <= cp_cond_opw;
        ELSE
            -- FScc (general EA)
            ea_build_now <= '1';
            datatype <= "00"; -- byte for FScc result
            next_micro_state <= cp_cond_opw;
        END IF;
    ELSIF opcode(8 downto 6)="010" THEN
        -- FBcc.W (16-bit displacement in extension word)
        datatype <= "01";
        next_micro_state <= cp_cond_opw;
    ELSIF opcode(8 downto 6)="011" THEN
        -- FBcc.L (32-bit displacement in extension words)
        datatype <= "01";
        next_micro_state <= cp_cond_opw;
    ELSE
        trap_1111 <= '1';
        trapmake <= '1';
    END IF;
END IF;
```

### Micro_state handlers

```vhdl
WHEN cp_cond_opw =>
    -- Write OpWord to OpWord CIR ($08)
    -- OpWord encodes the instruction type in [8:6]
    set_cpaddr <= '1';
    cp_cir_reg <= "00100"; -- OpWord CIR (register 4)
    setstate <= "11";      -- bus write
    datatype <= "01";      -- word
    next_micro_state <= cp_cond_write;

WHEN cp_cond_write =>
    -- Write condition code to Condition CIR ($0E)
    -- For FBcc: condition from opcode[5:0]
    -- For FScc/FDBcc/FTRAPcc: condition from sndOPC[5:0]
    set_cpaddr <= '1';
    cp_cir_reg <= "00111"; -- Condition CIR (register 7)
    setstate <= "11";      -- bus write
    datatype <= "01";      -- word
    next_micro_state <= cp_cond_resp;

WHEN cp_cond_resp =>
    -- Read Response CIR
    set_cpaddr <= '1';
    cp_cir_reg <= "00000"; -- Response CIR (register 0)
    setstate <= "10";      -- bus read
    datatype <= "01";      -- word
    next_micro_state <= cp_cond_decode;

WHEN cp_cond_decode =>
    -- Decode response
    setstate <= "01";      -- idle
    CASE last_data_read(15 downto 13) IS
        WHEN "000" =>      -- Busy
            next_micro_state <= cp_cond_resp;
        WHEN "001" =>      -- Null: condition result in bit 0
            -- Route to appropriate handler based on opcode type
            IF exe_opcode(8 downto 6)="010" OR exe_opcode(8 downto 6)="011" THEN
                -- FBcc: branch if condition true
                IF last_data_read(0)='1' THEN
                    next_micro_state <= cp_fbcc_branch;
                END IF;
                -- If false, fall through (next_micro_state defaults to idle)
            ELSIF exe_opcode(5 downto 3)="001" THEN
                -- FDBcc
                next_micro_state <= cp_fdbcc_dec;
            ELSIF exe_opcode(5 downto 3)="111" AND exe_opcode(2)='1' THEN
                -- FTRAPcc
                IF last_data_read(0)='1' THEN
                    next_micro_state <= cp_ftrapcc_trap;
                END IF;
            ELSE
                -- FScc
                next_micro_state <= cp_fscc_set;
            END IF;
        WHEN "111" =>      -- Post-instruction exception
            -- Extract vector, take exception
            trap_1111 <= '1';
            trapmake <= '1';
        WHEN OTHERS =>
            trap_1111 <= '1';
            trapmake <= '1';
    END CASE;

WHEN cp_fbcc_branch =>
    -- Add displacement to PC
    -- For .W: displacement is in sndOPC (sign-extended)
    -- For .L: displacement is in sndOPC:next_word (32-bit)
    -- Use TG68_PC_brw mechanism
    TG68_PC_brw <= '1';
    -- Implementation detail: need to compute PC + displacement
    -- Similar to existing bra1 micro_state

WHEN cp_fscc_set =>
    -- Write $FF (true) or $00 (false) to EA
    -- last_data_read(0) has condition result
    setstate <= "11";      -- bus write to EA
    datatype <= "00";      -- byte
    -- data_write_tmp should have $FF or $00

WHEN cp_fdbcc_dec =>
    -- If condition was true: done (no branch)
    -- If false: decrement Dn.W, branch if Dn.W != -1
    -- Similar to existing dbcc1 micro_state
    NULL; -- Details TBD based on dbcc1 implementation

WHEN cp_ftrapcc_trap =>
    -- Take trap (vector 7)
    trap_trap <= '1';
    trapmake <= '1';
```

### Key implementation notes for Phase 3

1. **FBcc displacement**: For FBcc.W, the 16-bit displacement is the extension word
   (already in sndOPC). For FBcc.L, a 32-bit displacement requires fetching two
   extension words. The branch target is PC + displacement (PC of the FBcc instruction).

2. **FScc result byte**: The condition result from the FPU (bit 0 of response) must
   be expanded to a full byte ($FF for true, $00 for false) and written to the EA.

3. **FDBcc counter**: Similar to the existing 68020 DBcc implementation. If the FPU
   condition is false, decrement Dn[15:0]. If the result is not -1 ($FFFF), branch
   to PC + displacement. Otherwise fall through.

4. **FTRAPcc**: If condition is true, take trap exception using vector 7. The optional
   operand word(s) (.W or .L) are on the stack but not used by the trap handler.

5. **Condition code source**:
   - FBcc: condition is in opcode[5:0]
   - FScc/FDBcc/FTRAPcc: condition is in sndOPC[5:0]

6. **OpWord construction**: The OpWord written to OpWord CIR must include the type
   field [8:6] so the FPU knows what kind of conditional instruction this is.

---

## Other Files Needing Changes (outside TG68K)

These are NOT part of the TG68K modification but are required for full FPU integration:

1. **tg68k.v** — Pass FC output to top-level (already exposed as output)
2. **addrDecoder.v** — Add selectFPU: decode FC=7 + addr $0002_xxxx
3. **LBMacTwo.sv** — Instantiate mc68881_top, connect bus, handle DSACK
4. **dataController_top.sv** — Add FPU to data mux (or handle in top-level)
5. **files.qip** — Add mc68881.qip reference

---

## FPU Frame Formats (for reference)

| Format Word | Frame Type | Size    | Words | Description              |
|-------------|-----------|---------|-------|--------------------------|
| $0000       | Null      | 0 bytes | 0     | FPU uninitialized        |
| $0018       | Idle      | 24 bytes| 12    | FPU idle, has state      |
| $00B4       | Busy      | 180 bytes| 90   | FPU mid-operation        |

---

### Changes Made (FBcc)

#### TG68K_Pack.vhd
- Added 3 new micro_states: `cp_cond_write`, `cp_cond_resp`, `cp_cond_eval`

#### TG68KdotC_Kernel.vhd
- New signals: `cp_branch_target` (32-bit pre-computed branch target), `cp_do_branch` (combinational branch trigger)
- 1111 handler: FBcc.W (type=010) and FBcc.L (type=011) decoded with `opcCPopw` flag, routed to `cp_write_opw`
  - FBcc.L uses `longaktion` for 32-bit displacement fetch
  - FScc/FDBcc/FTRAPcc (type=001) still trap to F-line exception (Phase 3b)
- cp_write_opw: Added routing for types 010/011 → `cp_cond_write`
- FC override: Added `cp_cond_write` and `cp_cond_resp` to FC=7 CIR access list
- data_write_tmp: Added `cp_cond_write` case to load condition code from `exe_opcode[5:0]`
- Branch target: Computed during `cp_write_opw` before CIR accesses corrupt `tmp_TG68_PC`:
  - FBcc.W: `tmp_TG68_PC + sign_extend(sndOPC)` (16-bit displacement)
  - FBcc.L: `tmp_TG68_PC + last_data_read` (32-bit displacement)
- TG68_PC update: Added `cp_do_branch` priority between `ea_to_pc` and normal PC increment
- Sensitivity list: Added `cp_do_branch`, `cp_branch_target` to PC calc process

### FBcc Protocol Flow
```
1. Fetch opcode ($F2xx/$F3xx) → decode as FBcc (type=010/011)
2. Fetch displacement word(s) → sndOPC (16-bit) or last_data_read (32-bit)
3. cp_write_opw: Write opcode to OpWord CIR ($0002_2008), FC=7
   - Also computes cp_branch_target = tmp_TG68_PC + displacement
4. cp_cond_write: Write condition code (opcode[5:0]) to Condition CIR ($0002_200E), FC=7
5. cp_cond_resp: Read Response CIR ($0002_2000), FC=7
6. cp_cond_eval: Decode response[15:13]:
   - "000" Busy → re-read (goto cp_cond_resp)
   - "001" Null → condition result in bit 0:
     - bit 0 = 1: branch taken → cp_do_branch loads TG68_PC from cp_branch_target
     - bit 0 = 0: fall through (done)
   - others → trap
```

---

### Changes Made (FScc / FTRAPcc)

#### TG68K_Pack.vhd
- Added 2 new micro_states: `cp_cond_skip`, `cp_fscc_wr`

#### TG68KdotC_Kernel.vhd
- New signals: `cp_cond_true` (registered condition result), `cp_fscc_writeback` (direct register write trigger)
- 1111 handler (type=001):
  - FScc data register (mode=000): routed to cp_write_opw → CIR dialog → cp_fscc_wr
  - FScc memory modes: trap (Phase 3c TODO)
  - FTRAPcc .W: cp_cond_skip (skip operand word) → cp_write_opw → CIR dialog → trap if true
  - FTRAPcc .L: cp_cond_skip + longaktion (skip 2 operand words) → CIR dialog → trap if true
  - FTRAPcc no-op: cp_write_opw → CIR dialog → trap if true
  - FDBcc: trap (Phase 3c TODO — needs 2 extension words + ALU decrement)
- data_write_tmp for cp_cond_write: FBcc uses exe_opcode[5:0], FScc/FTRAPcc use sndOPC[5:0]
- cp_cond_eval: routes FScc to cp_fscc_wr, FTRAPcc to trap_trapv if condition true
- cp_cond_skip: idle state (state="00") to skip operand words before CIR dialog
- cp_fscc_wr: triggers cp_fscc_writeback for direct register byte write
- Register file: new write port via cp_fscc_writeback — writes (others => cp_cond_true) to Dn byte
- Registered process: latches cp_cond_true from response bit 0 during cp_cond_eval

### FScc Protocol Flow (data register)
```
1. Fetch opcode ($F249) → decode as FScc (type=001, mode=000)
2. Fetch condition word (sndOPC) → condition in sndOPC[5:0]
3. cp_write_opw: Write opcode to OpWord CIR ($0002_2008), FC=7
4. cp_cond_write: Write condition (sndOPC[5:0]) to Condition CIR ($0002_200E), FC=7
5. cp_cond_resp: Read Response CIR ($0002_2000), FC=7
6. cp_cond_eval: Decode response, latch cp_cond_true
7. cp_fscc_wr: Write $FF (true) or $00 (false) to Dn via direct register port
```

### FTRAPcc Protocol Flow
```
1. Fetch opcode ($F27C etc) → decode as FTRAPcc (type=001, mode=111_1xx)
2. Fetch condition word (sndOPC) → condition in sndOPC[5:0]
3. cp_cond_skip: Skip .W/.L operand word(s) via PC fetch (state="00")
   (No-operand variant skips this step)
4. cp_write_opw: Write opcode to OpWord CIR
5. cp_cond_write: Write condition to Condition CIR
6. cp_cond_resp: Read Response CIR
7. cp_cond_eval: If condition true → trap_trapv (vector 7)
```

---

## Phase Summary
- **Phase 1** (DONE): MOVES + cpGEN → FPU detection + register ops + basic transfers
- **Phase 2** (DONE): cpSAVE/cpRESTORE → context switching support
- **Phase 3** (DONE): FBcc + FScc + FDBcc + FTRAPcc → all conditional FPU instructions

---

### Changes Made (FScc memory modes)

#### TG68K_Pack.vhd
- Added micro_state: `cp_fscc_wr_mem`

#### TG68KdotC_Kernel.vhd
- 1111 handler (type=001, FScc memory): Uses PEA-style `ea_only` + `ea_build_now` pattern
  to compute EA without bus read. On nextpass, starts CIR dialog via cp_write_opw.
  `IF set(get_ea_now)='1' THEN setstate<="01"` prevents unwanted PC advance.
- cp_ea_addr capture: `exec(get_ea_now)='1' AND ea_only='1'` captures `addr` into cp_ea_addr.
  cpSAVE/cpRESTORE capture now conditioned on type=100/101 to avoid overwriting FScc EA.
- data_write_tmp: Added `micro_state = cp_cond_eval` case to expand condition bit 0 to byte.
- cp_cond_eval: FScc memory (mode≠000, mode≠001, not FTRAPcc) routes to cp_fscc_wr_mem.
- cp_fscc_wr_mem: Writes result byte to `cp_ea_addr` via `set_cp_memaddr`.

### FScc Memory Protocol Flow
```
1. Decode: ea_only + ea_build_now compute EA address without bus access
2. nextpass: EA resolved in addr; captured to cp_ea_addr; opcCPopw set
3. cp_write_opw: Write opcode to OpWord CIR ($0002_2008), FC=7
4. cp_cond_write: Write condition (sndOPC[5:0]) to Condition CIR ($0002_200E), FC=7
5. cp_cond_resp: Read Response CIR ($0002_2000), FC=7
6. cp_cond_eval: Decode response, expand bit 0 to byte in data_write_tmp
7. cp_fscc_wr_mem: Write $FF/$00 to cp_ea_addr via set_cp_memaddr
```

---

### Changes Made (FDBcc)

#### TG68K_Pack.vhd
- Added 2 new micro_states: `cp_fdbcc_disp`, `cp_fdbcc_dec`

#### TG68KdotC_Kernel.vhd
- 1111 handler (type=001, mode=001): FDBcc routed to cp_fdbcc_disp for displacement fetch
- cp_fdbcc_disp: State "00" (PC fetch) reads displacement word, then cp_write_opw
- cp_branch_target: FDBcc case added — `(tmp_TG68_PC + 2) + sign_extend(last_data_read(15:0))`.
  The +2 accounts for displacement word being 2 bytes after the condition word.
- cp_cond_eval: FDBcc (mode=001) with condition FALSE sets `data_is_source` + `OP2out_one`,
  routes to cp_fdbcc_dec. Condition TRUE = instruction complete (no decrement).
- cp_fdbcc_dec: Uses ALU decrement pattern from DBcc — `Regwrena_now` writes Dn-1,
  `c_out(1)='1'` means not expired → cp_do_branch. c_out(1)='0' → fall through.

### FDBcc Protocol Flow
```
1. Fetch opcode ($F249) → decode as FDBcc (type=001, mode=001)
2. Fetch condition word (sndOPC) → sndOPC[5:0] = condition
3. cp_fdbcc_disp: PC fetch reads displacement word → last_data_read
4. cp_write_opw: Write opcode to OpWord CIR ($0002_2008), FC=7
   - Also computes cp_branch_target = (tmp_TG68_PC + 2) + sign_extend(displacement)
5. cp_cond_write: Write condition (sndOPC[5:0]) to Condition CIR ($0002_200E), FC=7
6. cp_cond_resp: Read Response CIR ($0002_2000), FC=7
7. cp_cond_eval: Decode response:
   - Condition TRUE → done (no decrement, no branch)
   - Condition FALSE → set up ALU decrement, goto cp_fdbcc_dec
8. cp_fdbcc_dec: Dn.W += $FFFF (= Dn.W - 1), write back via Regwrena_now
   - c_out(1)='1' (not expired): cp_do_branch loads PC from cp_branch_target
   - c_out(1)='0' (Dn was 0, now $FFFF = -1): fall through
```
