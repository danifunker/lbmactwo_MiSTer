-- MAME Lua script: capture CPU (M68020) instruction state from maciihmu.
--
-- Sibling of mame_fpu_capture.lua. Same frame-driven state machine, same
-- plant-program/run/dump approach. Differences:
--   * State dump records D0..D7, A0..A7, CCR, plus a 64-byte scratch RAM
--     window. (No FP regs, no FPCR/FPSR/FPIAR.)
--   * v1 scope: non-control-flow instructions only. Bcc/JMP/JSR/RTS/BSR
--     need dual-site dump dispatch and are deferred to a later phase.
--
-- Cross-platform invariant:
--   Test instruction bytes must be IDENTICAL between MAME and the Mac OS
--   bench, so any test that touches memory uses (A6) / d16(A6) addressing
--   with A6 pre-loaded by the harness to a *platform-specific* scratch base.
--   That way the same bytes run on both sides regardless of where scratch
--   RAM actually lives in each environment.
--
-- Outputs:
--   /tmp/cpu_corpus.json   -- JSON Lines, one test per line, init + final
--   /tmp/cpu_tests.h       -- C header with the same specs, for the Mac bench
--
-- USAGE
--   ../mame/maciihmu maciihmu -bios original -skip_gameinfo \
--       -debug -debugger none -window -nothrottle \
--       -autoboot_delay 1 \
--       -autoboot_script SingleStepTests/gen/mame_cpu_capture.lua

local CPU_OUT_PATH  = "/tmp/cpu_corpus.json"
local TESTS_H_PATH  = "/tmp/cpu_tests.h"

local PROG_BASE     = 0x00001000
local SCRATCH_BASE  = 0x00001800   -- A6 will be pre-loaded with this
local SCRATCH_LEN   = 64
local INIT_DUMP     = 0x00002000
local FINAL_DUMP    = 0x00002200
local VEC_BASE      = 0x00000000
local VEC_COUNT     = 256

-- Snapshot layout (mirrored by Mac bench's Snapshot struct):
--   +0x00..0x1F : D0..D7  (4 bytes each, big-endian)
--   +0x20..0x3F : A0..A7
--   +0x40       : CCR
--   +0x41..0x43 : pad
--   +0x44..0x83 : 64-byte copy of scratch RAM
local SNAP_BYTES = 0x84

-- ----------------------------------------------------------------------
-- Handles + helpers
-- ----------------------------------------------------------------------
local cpu, prog
local function init_handles()
    cpu  = manager.machine.devices[":maincpu"]
    prog = cpu.spaces["program"]
end
local function rget(name) return cpu.state[name].value end
local function rset(name, v) cpu.state[name].value = v end
local function write_bytes(addr, bytes)
    for i, b in ipairs(bytes) do prog:write_u8(addr + i - 1, b) end
end
local function read_bytes(addr, n)
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = prog:read_u8(addr + i) end
    return out
end

-- ----------------------------------------------------------------------
-- Instruction emitters
-- ----------------------------------------------------------------------
local function bw(w) return { (w >> 8) & 0xFF, w & 0xFF } end
local function bl(l)
    return { (l >> 24) & 0xFF, (l >> 16) & 0xFF,
             (l >>  8) & 0xFF,  l        & 0xFF }
end
local function concat(...)
    local out = {}
    for _, t in ipairs({...}) do
        for _, b in ipairs(t) do out[#out + 1] = b end
    end
    return out
end

local function emit_move_l_dn_to_abs(dn, addr)
    return concat(bw(0x23C0 | (dn & 7)), bl(addr))
end
local function emit_move_l_an_to_abs(an, addr)
    return concat(bw(0x23C8 | (an & 7)), bl(addr))
end
local function emit_move_l_imm_to_dn(dn, imm)
    return concat(bw(0x203C | ((dn & 7) << 9)), bl(imm))
end
local function emit_movea_l_imm_to_an(an, imm)
    return concat(bw(0x207C | ((an & 7) << 9)), bl(imm))
end
-- LEA d16(A6),An = $41EE | (dst_an<<9), then 16-bit disp.
-- mode=5 (d16,An), reg=6 (A6) -> ea=0x2E. opword = 0x41C0 | (an<<9) | 0x2E
local function emit_lea_d16_a6_to_an(an, disp)
    return concat(bw(0x41EE | ((an & 7) << 9)), bw(disp & 0xFFFF))
end
local function emit_move_w_imm_to_ccr(imm)
    return concat(bw(0x44FC), bw(imm & 0xFF))
end
local function emit_move_ccr_to_dn(dn) return bw(0x42C0 | (dn & 7)) end

-- State dump epilogue. snap_base is platform-specific; `is_init` toggles
-- WHERE in the dump the CCR write lands.
--
-- TWO invariants this routine must preserve:
--   1. Must not clobber any general-purpose register (D0..D7, A0..A7).
--      The init dump runs BEFORE the test, so clobbered values would
--      propagate into the test instruction.
--   2. CCR is captured at the moment that matches its semantic role:
--        - INIT dump:  CCR last  -- captures the CCR the test will see,
--                                   i.e. after the dump's MOVE.L pollution.
--                                   Without this, the corpus is self-
--                                   inconsistent: init.ccr says "0" but
--                                   the test actually inherits CCR=0x04
--                                   from the dump's last MOVE.L 0,0.
--        - FINAL dump: CCR first -- captures the test's actual output CCR,
--                                   before the final dump's MOVE.L pollution.
--
-- All instructions use memory-to-memory or reg-to-memory forms with no
-- temp-register intermediates. `MOVE CCR,(abs.L)` writes a 16-bit word:
-- byte snap+0x40 = 0x00 (zero-extended high), byte snap+0x41 = CCR.
local function emit_state_dump(snap_base, is_init)
    local out = {}
    local function append(t)
        for _, b in ipairs(t) do out[#out + 1] = b end
    end
    local function emit_ccr()
        append(concat(bw(0x42F9), bl(snap_base + 0x40)))
    end
    if not is_init then emit_ccr() end
    -- A regs
    for an = 0, 7 do
        append(emit_move_l_an_to_abs(an, snap_base + 0x20 + an * 4))
    end
    -- D regs
    for dn = 0, 7 do
        append(emit_move_l_dn_to_abs(dn, snap_base + 0x00 + dn * 4))
    end
    -- Scratch RAM copy via MOVE.L (abs.L),(abs.L).
    for i = 0, (SCRATCH_LEN / 4) - 1 do
        append(concat(bw(0x23F9),
                      bl(SCRATCH_BASE + i * 4),
                      bl(snap_base + 0x44 + i * 4)))
    end
    if is_init then emit_ccr() end
    return out
end

local function read_snap(base)
    local snap = { d = {}, a = {}, ram = {} }
    for dn = 0, 7 do
        local b = read_bytes(base + 0x00 + dn * 4, 4)
        snap.d[dn] = (b[1] << 24) | (b[2] << 16) | (b[3] << 8) | b[4]
    end
    for an = 0, 7 do
        local b = read_bytes(base + 0x20 + an * 4, 4)
        snap.a[an] = (b[1] << 24) | (b[2] << 16) | (b[3] << 8) | b[4]
    end
    -- MOVE CCR,(abs.L) writes a 16-bit word; CCR byte is at offset 0x41.
    snap.ccr = read_bytes(base + 0x41, 1)[1]
    snap.ram = read_bytes(base + 0x44, SCRATCH_LEN)
    return snap
end

-- ======================================================================
-- TEST GENERATOR
--
-- Each entry: { name, preload, test, [ram_init], [privileged] }
--   preload     : bytes that set up D regs / CCR (and A regs via LEA from A6)
--                 BEFORE the init dump. A6 is reserved as scratch base; do
--                 not touch it.
--   test        : the bytes under test
--   ram_init    : optional 64-byte table preloaded into scratch RAM
--   privileged  : optional bool; if true the Mac bench should skip exec
--                 (MOVES, etc. trap in user mode).
-- ======================================================================

local tests = {}

-- Preload helpers ------------------------------------------------------

-- preload_dregs({[n]=val, ...}) emits MOVE.L #imm,Dn for each entry.
local function preload_dregs(d_vals)
    local out = {}
    if not d_vals then return out end
    for n = 0, 7 do
        local v = d_vals[n]
        if v then
            for _, b in ipairs(emit_move_l_imm_to_dn(n, v & 0xFFFFFFFF)) do
                out[#out + 1] = b
            end
        end
    end
    return out
end

-- preload_an_scratch({[n]=offset, ...}) emits LEA off(A6),An for each.
-- An will point into scratch RAM at offset (signed 16-bit).
local function preload_an_scratch(a_offsets)
    local out = {}
    if not a_offsets then return out end
    for n = 0, 7 do
        local off = a_offsets[n]
        if off ~= nil then
            if n == 6 then
                error("cannot preload A6 (reserved scratch base)")
            end
            if n == 7 then
                error("cannot preload A7 (Mac bench needs intact stack)")
            end
            for _, b in ipairs(emit_lea_d16_a6_to_an(n, off)) do
                out[#out + 1] = b
            end
        end
    end
    return out
end

local function preload_ccr(imm) return emit_move_w_imm_to_ccr(imm) end

-- ---------- MOVEQ ------------------------------------------------------
local function emit_moveq(dn, imm)
    return bw(0x7000 | ((dn & 7) << 9) | (imm & 0xFF))
end
for _, spec in ipairs({
    {0,  0,    "zero"}, {0, 1,    "one"}, {0, 0x7F, "max_pos"},
    {1, -1,    "neg_one"}, {2, -128, "min_neg"}, {3, 42, "answer"},
    {4, 0x5A,  "fives_alt"}, {7, -64, "neg_64_into_d7"},
}) do
    tests[#tests + 1] = {
        name    = string.format("MOVEQ #%d,D%d (%s)", spec[2], spec[1], spec[3]),
        preload = {},
        test    = emit_moveq(spec[1], spec[2]),
    }
end

-- ---------- MOVE.L Dm,Dn -----------------------------------------------
local function emit_move_l_dm_dn(dm, dn)
    return bw(0x2000 | ((dn & 7) << 9) | (dm & 7))
end
for _, spec in ipairs({
    {0,1, 0xDEADBEEF}, {1,2, 0},        {2,3, 0x80000000},
    {3,4, 0x7FFFFFFF}, {4,0, 0x12345678}, {7,5, 1},
}) do
    local dm, dn, v = spec[1], spec[2], spec[3]
    tests[#tests + 1] = {
        name    = string.format("MOVE.L D%d,D%d (0x%08X)", dm, dn, v & 0xFFFFFFFF),
        preload = preload_dregs({[dm] = v}),
        test    = emit_move_l_dm_dn(dm, dn),
    }
end

-- ---------- MOVE.W / MOVE.B Dm,Dn --------------------------------------
for _, spec in ipairs({
    {0,1, 0xDEADBEEF}, {1,2, 0xFFFF8000}, {3,4, 0x00007FFF},
    {5,7, 0x00000001}, {7,0, 0x12340000},
}) do
    local dm, dn, v = spec[1], spec[2], spec[3]
    tests[#tests + 1] = {
        name    = string.format("MOVE.W D%d,D%d (0x%08X)", dm, dn, v & 0xFFFFFFFF),
        preload = preload_dregs({[dm] = v, [dn] = 0xAAAAAAAA}),
        test    = bw(0x3000 | ((dn & 7) << 9) | (dm & 7)),
    }
end
for _, spec in ipairs({
    {0,1, 0x000000FF}, {2,3, 0x00000080}, {4,5, 0x0000007F},
    {7,0, 0x00000001},
}) do
    local dm, dn, v = spec[1], spec[2], spec[3]
    tests[#tests + 1] = {
        name    = string.format("MOVE.B D%d,D%d (0x%08X)", dm, dn, v & 0xFFFFFFFF),
        preload = preload_dregs({[dm] = v, [dn] = 0xBBBBBBBB}),
        test    = bw(0x1000 | ((dn & 7) << 9) | (dm & 7)),
    }
end

-- ---------- MOVE.L #imm,Dn (immediate load) ----------------------------
for _, spec in ipairs({
    {0, 0x12345678}, {1, 0x80000000}, {2, 0x7FFFFFFF},
    {3, 0xFFFFFFFF}, {7, 0x00000001},
}) do
    tests[#tests + 1] = {
        name    = string.format("MOVE.L #0x%08X,D%d", spec[2] & 0xFFFFFFFF, spec[1]),
        preload = {},
        test    = emit_move_l_imm_to_dn(spec[1], spec[2]),
    }
end

-- ---------- MOVE.L Dn,(A6) [write to scratch] --------------------------
-- MOVE.L Dn,(An) = $2080 | (an<<9) | <reg-direct>... wrong.
-- MOVE.L Dn,(An) = mode=2,reg=an for dst; src EA = mode=0,reg=dn.
-- opword = 0x2000 | (mode_dst<<6) | (reg_dst<<9) | <src_ea>
--        = 0x2000 | (2<<6) | (an<<9) | dn = 0x2080 | (an<<9) | dn
-- For An=A6: 0x2080 | (6<<9) | dn = 0x2080 | 0xC00 | dn = 0x2C80 | dn
-- We also want d16(A6) writes; mode=5,reg=6 for dst.
-- MOVE.L Dn,d16(A6) = 0x2D40 | dn  then 16-bit disp.
--   = 0x2000 | (5<<6) | (6<<9) | dn = 0x2000 | 0x140 | 0xC00 | dn = 0x2D40 | dn
for _, spec in ipairs({
    {0, 0xDEADBEEF, 0}, {1, 0x12345678, 4}, {7, 0xFFFFFFFF, 8},
}) do
    local dn, v, off = spec[1], spec[2], spec[3]
    tests[#tests + 1] = {
        name    = string.format("MOVE.L D%d,%d(A6) (val=0x%08X)",
                                dn, off, v & 0xFFFFFFFF),
        preload = preload_dregs({[dn] = v}),
        test    = concat(bw(0x2D40 | (dn & 7)), bw(off & 0xFFFF)),
    }
end

-- ---------- MOVE.L d16(A6),Dn ------------------------------------------
-- MOVE.L d16(A6),Dn: src mode=5,reg=6 -> ea=0x2E; dst mode=0,reg=dn.
-- opword = 0x2000 | (dn<<9) | 0x2E = 0x202E | (dn<<9)
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1] = 0xCA; ram[2] = 0xFE; ram[3] = 0xBA; ram[4] = 0xBE
    ram[5] = 0x12; ram[6] = 0x34; ram[7] = 0x56; ram[8] = 0x78
    for _, spec in ipairs({{0, 0}, {3, 4}, {7, 0}}) do
        local dn, off = spec[1], spec[2]
        tests[#tests + 1] = {
            name = string.format("MOVE.L %d(A6),D%d", off, dn),
            preload  = {},
            ram_init = ram,
            test = concat(bw(0x202E | ((dn & 7) << 9)), bw(off & 0xFFFF)),
        }
    end
end

-- ---------- MOVE.L (An),Dn (An preloaded from A6) ----------------------
-- MOVE.L (An),Dn = 0x2010 | (dn<<9) | an
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1] = 0xDE; ram[2] = 0xAD; ram[3] = 0xBE; ram[4] = 0xEF
    for _, spec in ipairs({{0, 1, 0}, {3, 2, 0}}) do
        local dn, an, off = spec[1], spec[2], spec[3]
        tests[#tests + 1] = {
            name = string.format("MOVE.L (A%d),D%d  A%d=scratch+%d", an, dn, an, off),
            preload  = preload_an_scratch({[an] = off}),
            ram_init = ram,
            test = bw(0x2010 | ((dn & 7) << 9) | (an & 7)),
        }
    end
end

-- ---------- MOVE.L (An)+,Dn / -(An),Dn ---------------------------------
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x11; ram[2]=0x22; ram[3]=0x33; ram[4]=0x44
    ram[5]=0x55; ram[6]=0x66; ram[7]=0x77; ram[8]=0x88
    tests[#tests + 1] = {
        name = "MOVE.L (A1)+,D0  A1=scratch+0",
        preload  = preload_an_scratch({[1] = 0}),
        ram_init = ram,
        test = bw(0x2019),                  -- MOVE.L (A1)+,D0
    }
    tests[#tests + 1] = {
        name = "MOVE.L -(A2),D3  A2=scratch+8",
        preload  = preload_an_scratch({[2] = 8}),
        ram_init = ram,
        test = bw(0x2622),                  -- MOVE.L -(A2),D3
    }
end

-- ---------- ADD/SUB/AND/OR/CMP register family -------------------------
-- ADD.L Dm,Dn = $D080 | (dn<<9) | dm (Dn += Dm)
local function emit_alu_reg(base, size_bits, dm, dn)
    return bw(base | size_bits | ((dn & 7) << 9) | (dm & 7))
end
local ALU_OPS = {
    {name="ADD", base=0xD000}, {name="SUB", base=0x9000},
    {name="AND", base=0xC000}, {name="OR",  base=0x8000},
    {name="CMP", base=0xB000},
}
local ALU_SAMPLES = {
    {0xDEADBEEF, 0x12345678},
    {0x80000000, 0x80000000},
    {0x7FFFFFFF, 0x00000001},
    {0x00000000, 0xFFFFFFFF},
    {0x00010000, 0x0000FFFF},
}
for _, op in ipairs(ALU_OPS) do
    for _, sz in ipairs({{name="L", bits=0x0080}, {name="W", bits=0x0040}, {name="B", bits=0x0000}}) do
        for i = 1, 3 do
            local vp = ALU_SAMPLES[i]
            tests[#tests + 1] = {
                name = string.format("%s.%s D1,D0 (#%d 0x%08X,0x%08X)",
                                     op.name, sz.name, i, vp[1] & 0xFFFFFFFF, vp[2] & 0xFFFFFFFF),
                preload = preload_dregs({[0] = vp[1], [1] = vp[2]}),
                test    = emit_alu_reg(op.base, sz.bits, 1, 0),
            }
        end
    end
end

-- EOR.L Dn_src,Dm_dst = $B180 | (dn_src<<9) | dm_dst
for i = 1, 3 do
    local vp = ALU_SAMPLES[i]
    tests[#tests + 1] = {
        name = string.format("EOR.L D1,D0 (#%d 0x%08X^0x%08X)", i,
                             vp[1] & 0xFFFFFFFF, vp[2] & 0xFFFFFFFF),
        preload = preload_dregs({[0] = vp[1], [1] = vp[2]}),
        test    = bw(0xB180 | (1 << 9) | 0),
    }
end

-- ---------- Immediate-form ADDI/SUBI/CMPI/ANDI/ORI/EORI ----------------
local IMM_OPS = {
    {name="ADDI", base=0x0600}, {name="SUBI", base=0x0400},
    {name="ANDI", base=0x0200}, {name="ORI",  base=0x0000},
    {name="EORI", base=0x0A00}, {name="CMPI", base=0x0C00},
}
local IMM_SAMPLES = {
    {dn=0, dv=0x12345678, imm=0x0000FFFF},
    {dn=1, dv=0x80000000, imm=0x80000000},
    {dn=2, dv=0xFFFFFFFF, imm=0x00000001},
}
for _, op in ipairs(IMM_OPS) do
    for _, s in ipairs(IMM_SAMPLES) do
        tests[#tests + 1] = {
            name = string.format("%s.L #0x%08X,D%d", op.name, s.imm & 0xFFFFFFFF, s.dn),
            preload = preload_dregs({[s.dn] = s.dv}),
            test    = concat(bw(op.base | 0x0080 | (s.dn & 7)), bl(s.imm)),
        }
    end
end

-- ---------- MULU/MULS/DIVU/DIVS (word forms) ---------------------------
local MULDIV_OPS = {
    {name="MULU", op=0xC0C0}, {name="MULS", op=0xC1C0},
    {name="DIVU", op=0x80C0}, {name="DIVS", op=0x81C0},
}
local MULDIV_SAMPLES = {
    {dn_v=0x00000010, dm_v=0x00000004},
    {dn_v=0x0000FFFF, dm_v=0x0000FFFF},
    {dn_v=0x00008000, dm_v=0x00000002},
}
for _, op in ipairs(MULDIV_OPS) do
    for i, s in ipairs(MULDIV_SAMPLES) do
        -- Sample #2 (0xFFFF / 0xFFFF) overflows for DIVS.W; PRM page 4-95
        -- says N and Z are undefined when DIVS/DIVU overflows or divides by
        -- zero. MAME and TG68K disagree on Z (and would disagree on N),
        -- so mask them out for the DIVS overflow case.
        local mask = nil
        if i == 2 and op.name == "DIVS" then mask = 0xF3 end  -- ignore N(0x08)+Z(0x04)
        tests[#tests + 1] = {
            name = string.format("%s.W D1,D0 (#%d Dn=0x%08X Dm=0x%08X)",
                                 op.name, i, s.dn_v, s.dm_v),
            preload = preload_dregs({[0] = s.dn_v, [1] = s.dm_v}),
            test    = bw(op.op | (0 << 9) | 1),
            ccr_mask = mask,
        }
    end
end

-- ---------- NEG/NOT/CLR ------------------------------------------------
local UN_OPS = {
    {name="NEG", base=0x4400}, {name="NOT", base=0x4600}, {name="CLR", base=0x4200},
}
for _, op in ipairs(UN_OPS) do
    for _, sz in ipairs({{name="L", bits=0x0080}, {name="W", bits=0x0040}, {name="B", bits=0x0000}}) do
        tests[#tests + 1] = {
            name = string.format("%s.%s D0 (0x12345678)", op.name, sz.name),
            preload = preload_dregs({[0] = 0x12345678}),
            test    = bw(op.base | sz.bits | 0),
        }
    end
end

-- ---------- SWAP / EXT -------------------------------------------------
tests[#tests + 1] = {
    name = "SWAP D0 (0x12345678)",
    preload = preload_dregs({[0] = 0x12345678}),
    test    = bw(0x4840),
}
tests[#tests + 1] = {
    name = "SWAP D3 (0xDEADBEEF)",
    preload = preload_dregs({[3] = 0xDEADBEEF}),
    test    = bw(0x4843),
}
tests[#tests + 1] = {
    name = "EXT.W D0 (0x000000FF)",
    preload = preload_dregs({[0] = 0x000000FF}),
    test    = bw(0x4880),
}
tests[#tests + 1] = {
    name = "EXT.L D0 (0x0000FFFF)",
    preload = preload_dregs({[0] = 0x0000FFFF}),
    test    = bw(0x48C0),
}
tests[#tests + 1] = {
    name = "EXTB.L D0 (0x00000080)",
    preload = preload_dregs({[0] = 0x00000080}),
    test    = bw(0x49C0),
}

-- ---------- LEA --------------------------------------------------------
-- LEA (A6),An = $41D6 | (an<<9)
-- A7 deliberately excluded: tests that write to A7 destroy the C stack
-- in the Mac OS bench (final RTS pops a garbage return address from
-- scratch RAM). MAME's harness uses a JMP-self loop and doesn't care.
for _, an in ipairs({0, 1, 5}) do
    tests[#tests + 1] = {
        name = string.format("LEA (A6),A%d", an),
        preload = {},
        test    = bw(0x41D6 | ((an & 7) << 9)),
    }
end
-- LEA 16(A6),A1
tests[#tests + 1] = {
    name = "LEA 16(A6),A1",
    preload = {},
    test    = concat(bw(0x43EE), bw(0x0010)),
}

-- ---------- BTST/BSET/BCLR/BCHG (dynamic + static) ---------------------
local BIT_OPS = {
    {name="BTST", base=0x0100}, {name="BCHG", base=0x0140},
    {name="BCLR", base=0x0180}, {name="BSET", base=0x01C0},
}
for _, op in ipairs(BIT_OPS) do
    tests[#tests + 1] = {
        name = string.format("%s.L D1,D0 (bit=3 set in 0x12345678)", op.name),
        preload = preload_dregs({[0] = 0x12345678, [1] = 3}),
        test    = bw(op.base | (1 << 9) | 0),
    }
    tests[#tests + 1] = {
        name = string.format("%s.L D1,D0 (bit=2 clr in 0x12345678)", op.name),
        preload = preload_dregs({[0] = 0x12345678, [1] = 2}),
        test    = bw(op.base | (1 << 9) | 0),
    }
end
tests[#tests + 1] = {
    name = "BTST #5,D0  (D0=0x20)",
    preload = preload_dregs({[0] = 0x00000020}),
    test    = concat(bw(0x0800), bw(0x0005)),
}
tests[#tests + 1] = {
    name = "BSET #31,D0  (D0=0)",
    preload = preload_dregs({[0] = 0x00000000}),
    test    = concat(bw(0x08C0), bw(0x001F)),
}

-- ---------- Shifts/Rotates (immediate count, .L) -----------------------
-- ASL/ASR/LSL/LSR/ROXL/ROXR/ROL/ROR
-- opword = $E000 | (cnt<<9) | (dr<<8) | (size<<6) | (ir<<5) | (typ<<3) | dn
-- dr=1 left/0 right, ir=0 (immediate), size: .B=00,.W=01,.L=10, typ as above.
local SHIFT_DEFS = {
    {"ASL", 1, 0}, {"ASR", 0, 0},
    {"LSL", 1, 1}, {"LSR", 0, 1},
    {"ROXL",1, 2}, {"ROXR",0, 2},
    {"ROL", 1, 3}, {"ROR", 0, 3},
}
for _, sd in ipairs(SHIFT_DEFS) do
    local name, dr, typ = sd[1], sd[2], sd[3]
    local base_l = 0xE000 | (dr << 8) | (0x2 << 6) | (typ << 3)  -- size=.L
    for _, cs in ipairs({{1, 0x80000001}, {4, 0x12345678}, {7, 0xDEADBEEF}}) do
        local cnt, v = cs[1], cs[2]
        local ic = cnt & 7        -- count 0 in field means 8
        tests[#tests + 1] = {
            name = string.format("%s.L #%d,D0 (0x%08X)", name, cnt, v & 0xFFFFFFFF),
            preload = preload_dregs({[0] = v}),
            test    = bw(base_l | (ic << 9) | 0),
        }
    end
end

-- ---------- MOVEM (using (A6) so A7 stays untouched) -------------------
-- MOVEM.L D0-D3,(A6) = $48D6, mask=0x000F  (postdec-mask not used for (An))
-- opword = $4880 | size<<6 | <ea>. size .L = 0x40. (An) ea = 0x16.
-- Actually MOVEM register-list, regs->mem: $4880 | size | <ea>, size .W=$0000, .L=$0040
-- For .L,(An): opword = $4880 | 0x40 | 0x10 | 6 = $48D6. mask = 0x000F (D0..D3)
tests[#tests + 1] = {
    name = "MOVEM.L D0-D3,(A6)",
    preload = preload_dregs({[0]=0x11111111,[1]=0x22222222,[2]=0x33333333,[3]=0x44444444}),
    test    = concat(bw(0x48D6), bw(0x000F)),
}
-- MOVEM.L (A6),D4-D7  -> reg list mask 0x00F0
-- mem->regs: $4C80 | size | <ea>; size .L=$0040.
-- opword = $4C80 | 0x40 | 0x10 | 6 = $4CD6.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0xAA; ram[2]=0xBB; ram[3]=0xCC; ram[4]=0xDD
    ram[5]=0x55; ram[6]=0x66; ram[7]=0x77; ram[8]=0x88
    ram[9]=0x11; ram[10]=0x22; ram[11]=0x33; ram[12]=0x44
    ram[13]=0x99; ram[14]=0x88; ram[15]=0x77; ram[16]=0x66
    tests[#tests + 1] = {
        name     = "MOVEM.L (A6),D4-D7",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0x4CD6), bw(0x00F0)),
    }
end

-- ---------- MOVES (privileged; supervisor only; Mac bench will skip) ---
-- MOVES.L D0,(A1)  A1=scratch
-- $0E80 | <ea>=0x11 (mode=2,reg=1) -> $0E91
-- ext: 15-12 = reg (D0=0), 11 = R=0 (Rg->Mem), 10..0 = 0 -> $0800
tests[#tests + 1] = {
    name = "MOVES.L D0,(A1) A1=scratch (privileged)",
    preload = concat(preload_dregs({[0] = 0xCAFEF00D}),
                     preload_an_scratch({[1] = 0})),
    test    = concat(bw(0x0E91), bw(0x0800)),
    privileged = true,
}

-- ---------- MOVE Dn,CCR / MOVE CCR,Dn ----------------------------------
tests[#tests + 1] = {
    name = "MOVE D0,CCR  (D0=0x1F)",
    preload = preload_dregs({[0] = 0x0000001F}),
    test    = bw(0x44C0),
}
tests[#tests + 1] = {
    name = "MOVE CCR,D1  (CCR=0x0F)",
    preload = concat(preload_dregs({[1] = 0xFFFFFF00}), preload_ccr(0x0F)),
    test    = bw(0x42C1),
}

-- ======================================================================
-- 68020-SPECIFIC INSTRUCTIONS
--
-- The base ISA above runs on every 680x0. This section exercises
-- 020-introduced features that a TG68K-derived implementation may not
-- have full coverage of:
--   - 32-bit MULU.L/MULS.L (both 32-bit-result and 64-bit-result forms)
--   - 32-bit DIVU.L/DIVS.L (both with and without separate remainder)
--   - Bitfield operations (BFTST/BFEXTU/BFEXTS/BFCHG/BFCLR/BFSET/BFFFO/BFINS)
--   - PACK / UNPK (BCD nibble pack/unpack, Dn,Dn form)
--   - Scaled-index addressing modes (d8,An,Xn.L*scale)
-- ======================================================================

-- ---------- 32-bit MULU.L / MULS.L -------------------------------------
-- 32-bit-result form: $4C00|<ea> | ext = Dq<<12 | (signed?0x800:0)
--   Dn destination = source value too; result is low 32 bits of Dq * <ea>.
-- 64-bit-result form: ext bit 10 set, Dh in low 3 bits; result = Dh:Dl.
local MUL32_SAMPLES = {
    {name="small",  a=0x00000010, b=0x00000004},   -- 0x40
    {name="midhi",  a=0x12345678, b=0x00010000},   -- low32 = 0x56780000
    {name="negneg", a=0xFFFFFFFE, b=0xFFFFFFFE},   -- signed: 4
}
for _, s in ipairs(MUL32_SAMPLES) do
    -- MULU.L D1,D0  -> D0 := (D0.L * D1.L) low 32 bits
    tests[#tests + 1] = {
        name    = string.format("MULU.L D1,D0 (%s 0x%08X*0x%08X)",
                                s.name, s.a & 0xFFFFFFFF, s.b & 0xFFFFFFFF),
        preload = preload_dregs({[0] = s.a, [1] = s.b}),
        test    = concat(bw(0x4C01), bw(0x0000)),    -- ext: Dq=0
    }
    tests[#tests + 1] = {
        name    = string.format("MULS.L D1,D0 (%s 0x%08X*0x%08X)",
                                s.name, s.a & 0xFFFFFFFF, s.b & 0xFFFFFFFF),
        preload = preload_dregs({[0] = s.a, [1] = s.b}),
        test    = concat(bw(0x4C01), bw(0x0800)),    -- signed
    }
end
-- 64-bit-result: D2:D0 := D0 * D1 (Dh=D2, Dl=D0)
for _, s in ipairs({
    {name="big",    a=0x12345678, b=0x10000000},
    {name="negneg", a=0xFFFFFFFF, b=0xFFFFFFFF},
}) do
    tests[#tests + 1] = {
        name    = string.format("MULU.L D1,D2:D0 (%s)", s.name),
        preload = preload_dregs({[0] = s.a, [1] = s.b}),
        test    = concat(bw(0x4C01), bw(0x0402)),    -- size=1, Dh=D2, Dl=D0
    }
    tests[#tests + 1] = {
        name    = string.format("MULS.L D1,D2:D0 (%s)", s.name),
        preload = preload_dregs({[0] = s.a, [1] = s.b}),
        test    = concat(bw(0x4C01), bw(0x0C02)),    -- signed + size=1
    }
end

-- ---------- 32-bit DIVU.L / DIVS.L -------------------------------------
-- opword: $4C40 | <ea>. ext: Dq<<12 | (signed?0x800:0) | (size?0x400:0) | Dr.
-- 32-bit form (size=0): Dq := Dq/<ea>, Dr := Dq%<ea>. If Dq==Dr only Dq used.
local DIV32_SAMPLES = {
    {name="exact",   dq=100,         d=7},
    {name="big",     dq=0x12345678,  d=0x100},
    {name="neg",     dq=0xFFFFFFF6,  d=0x4},    -- signed: -10 / 4 = -2
}
for _, s in ipairs(DIV32_SAMPLES) do
    -- DIVU.L D1,D0:D2  (Dq=D0 quotient, Dr=D2 remainder)
    tests[#tests + 1] = {
        name    = string.format("DIVU.L D1,D0:D2 (%s D0=0x%08X/D1=0x%08X)",
                                s.name, s.dq & 0xFFFFFFFF, s.d & 0xFFFFFFFF),
        preload = preload_dregs({[0] = s.dq, [1] = s.d}),
        test    = concat(bw(0x4C41), bw(0x0002)),  -- Dq=D0(0), Dr=D2(2)
    }
    tests[#tests + 1] = {
        name    = string.format("DIVS.L D1,D0:D2 (%s D0=0x%08X/D1=0x%08X)",
                                s.name, s.dq & 0xFFFFFFFF, s.d & 0xFFFFFFFF),
        preload = preload_dregs({[0] = s.dq, [1] = s.d}),
        test    = concat(bw(0x4C41), bw(0x0802)),  -- signed
    }
end
-- Quotient-only form (Dq==Dr=D0)
tests[#tests + 1] = {
    name    = "DIVU.L D1,D0 (quot-only D0=100/D1=7)",
    preload = preload_dregs({[0] = 100, [1] = 7}),
    test    = concat(bw(0x4C41), bw(0x0000)),     -- Dq=Dr=D0
}
tests[#tests + 1] = {
    name    = "DIVS.L D1,D0 (quot-only D0=-100/D1=7)",
    preload = preload_dregs({[0] = (-100) & 0xFFFFFFFF, [1] = 7}),
    test    = concat(bw(0x4C41), bw(0x0800)),
}

-- ---------- EXTB.L extra samples ---------------------------------------
-- (One already exists above for 0x80 -> 0xFFFFFF80; add positive/negative.)
tests[#tests + 1] = {
    name    = "EXTB.L D0 (0x000000FF -> 0xFFFFFFFF)",
    preload = preload_dregs({[0] = 0xAABBCCFF}),
    test    = bw(0x49C0),
}
tests[#tests + 1] = {
    name    = "EXTB.L D0 (0x0000007F -> 0x0000007F)",
    preload = preload_dregs({[0] = 0xAABBCC7F}),
    test    = bw(0x49C0),
}

-- ---------- Bitfield operations ----------------------------------------
-- All use Dn-direct EA (mode=0,reg=dn) to keep the encoding simple.
-- opword: $E8C0..$EFC0 | dn  (8 ops sharing the 1110 1xxx 11... prefix).
-- ext bits: dst_dn<<12 | Do<<11 | offset<<6 | Dw<<5 | width
--   For static offset/width: Do=Dw=0, offset in bits 10-6, width in bits 4-0.
--   width field: 0 means 32; 1..31 means 1..31.
-- All examples below use D0 as the bitfield source/dest, D1 as auxiliary
-- (dst for read ops, src for BFINS).
-- BFTST D0{16:8}: tests bits 16..23 of D0, sets CCR (N,Z); D0 unchanged.
tests[#tests + 1] = {
    name    = "BFTST D0{16:8} (D0=0x12FF5678 -> Z=0,N=1)",
    preload = preload_dregs({[0] = 0x12FF5678}),
    test    = concat(bw(0xE8C0), bw(0x0408)),    -- off=16,width=8
}
tests[#tests + 1] = {
    name    = "BFTST D0{0:16} (D0=0)",
    preload = preload_dregs({[0] = 0x00000000}),
    test    = concat(bw(0xE8C0), bw(0x0010)),    -- off=0,width=16
}
-- BFEXTU D0{16:8},D1 = unsigned extract
tests[#tests + 1] = {
    name    = "BFEXTU D0{16:8},D1 (D0=0x12FF5678 -> D1=0xFF)",
    preload = preload_dregs({[0] = 0x12FF5678}),
    test    = concat(bw(0xE9C0), bw(0x1408)),    -- dst=D1, off=16, w=8
}
tests[#tests + 1] = {
    name    = "BFEXTU D0{4:12},D2",
    preload = preload_dregs({[0] = 0xABCDEF12}),
    test    = concat(bw(0xE9C0), bw(0x210C)),    -- dst=D2, off=4, w=12
}
-- BFEXTS D0{16:8},D1 = signed extract (sign-extends top bit)
tests[#tests + 1] = {
    name    = "BFEXTS D0{16:8},D1 (D0=0x12FF5678 -> D1=0xFFFFFFFF)",
    preload = preload_dregs({[0] = 0x12FF5678}),
    test    = concat(bw(0xEBC0), bw(0x1408)),
}
tests[#tests + 1] = {
    name    = "BFEXTS D0{16:8},D1 (D0=0x12345678 -> D1=0x00000034)",
    preload = preload_dregs({[0] = 0x12345678}),
    test    = concat(bw(0xEBC0), bw(0x1408)),
}
-- BFCHG D0{16:8} = invert bitfield in place
tests[#tests + 1] = {
    name    = "BFCHG D0{16:8} (D0=0x12FF5678)",
    preload = preload_dregs({[0] = 0x12FF5678}),
    test    = concat(bw(0xEAC0), bw(0x0408)),
}
-- BFCLR D0{16:8} = zero bitfield
tests[#tests + 1] = {
    name    = "BFCLR D0{16:8} (D0=0xFFFFFFFF)",
    preload = preload_dregs({[0] = 0xFFFFFFFF}),
    test    = concat(bw(0xECC0), bw(0x0408)),
}
-- BFSET D0{16:8} = set bitfield to all-ones
tests[#tests + 1] = {
    name    = "BFSET D0{16:8} (D0=0)",
    preload = preload_dregs({[0] = 0x00000000}),
    test    = concat(bw(0xEEC0), bw(0x0408)),
}
-- BFFFO D0{16:8},D1 = find first one (bit number of highest set bit)
tests[#tests + 1] = {
    name    = "BFFFO D0{0:32},D1 (D0=0x00100000 -> D1=11)",
    preload = preload_dregs({[0] = 0x00100000}),
    test    = concat(bw(0xEDC0), bw(0x1000)),    -- off=0, w=32(encoded 0)
}
tests[#tests + 1] = {
    name    = "BFFFO D0{0:32},D1 (D0=0 -> D1=32)",
    preload = preload_dregs({[0] = 0x00000000}),
    test    = concat(bw(0xEDC0), bw(0x1000)),
}
-- BFINS D1,D0{16:8} = insert low N bits of D1 into D0's bitfield
tests[#tests + 1] = {
    name    = "BFINS D1,D0{16:8} (D0=0xFFFFFFFF, D1=0xAA)",
    preload = preload_dregs({[0] = 0xFFFFFFFF, [1] = 0x000000AA}),
    test    = concat(bw(0xEFC0), bw(0x1408)),
}

-- ---------- PACK / UNPK ------------------------------------------------
-- Dy,Dx,#adj form. Takes two BCD nibbles from low byte of Dy plus #adj16,
-- packs to one BCD byte in low byte of Dx (PACK), or expands one byte
-- to two-nibble-per-byte word (UNPK).
-- PACK D1,D0,#0: $8141 ext=$0000 (Dx=D0, Dy=D1)
tests[#tests + 1] = {
    name    = "PACK D1,D0,#0 (D1=0x00003132 -> D0 low byte=0x12)",
    preload = preload_dregs({[0] = 0xAABBCCDD, [1] = 0x00003132}),
    test    = concat(bw(0x8141), bw(0x0000)),
}
tests[#tests + 1] = {
    name    = "PACK D1,D0,#0x0100 (D1=0x00003132 -> D0 low byte=0x13)",
    preload = preload_dregs({[0] = 0xAABBCCDD, [1] = 0x00003132}),
    test    = concat(bw(0x8141), bw(0x0100)),
}
-- UNPK D1,D0,#0: $8181  (Dx=D0, Dy=D1)
tests[#tests + 1] = {
    name    = "UNPK D1,D0,#0 (D1 low byte=0x12 -> D0 low word=0x0102)",
    preload = preload_dregs({[0] = 0xAABBCCDD, [1] = 0x00000012}),
    test    = concat(bw(0x8181), bw(0x0000)),
}
tests[#tests + 1] = {
    name    = "UNPK D1,D0,#0x3030 (D1 low=0x12 -> D0='12' = 0x3132)",
    preload = preload_dregs({[0] = 0xAABBCCDD, [1] = 0x00000012}),
    test    = concat(bw(0x8181), bw(0x3030)),
}

-- ---------- Scaled-index addressing (d8,An,Xn.L*scale) -----------------
-- MOVE.L (d8,A6,Dn.L*scale),Dy
-- opword: $2000 | (dst_dn<<9) | (dst_mode<<6) | (src_mode<<3) | src_reg
--   src mode=6,reg=6 -> $36; dst Dn -> opword = $2236 (Dy=D1, dst_mode=0)
-- brief ext: D/A(1) | reg(3) | WL(1) | scale(2) | full(1) | disp(8)
--   D/A=0 (Dn index), WL=1 (long), scale=0..3 for 1/2/4/8, full=0
-- Preload scratch with a recognizable pattern so the read picks up
-- something meaningful per index.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = i end   -- 1,2,3,...64
    for _, sc in ipairs({
        {bits=0x00, mul=1, name="*1"},   -- scale=0
        {bits=0x02, mul=2, name="*2"},
        {bits=0x04, mul=4, name="*4"},
        {bits=0x06, mul=8, name="*8"},
    }) do
        local ext = 0x0800 | (sc.bits << 8)    -- D/A=0,reg=0(D0),WL=1,scale,full=0,disp=0
        tests[#tests + 1] = {
            name = string.format("MOVE.L (0,A6,D0.L%s),D1 (D0=2)", sc.name),
            preload  = preload_dregs({[0] = 2}),
            ram_init = ram,
            test     = concat(bw(0x2236), bw(ext)),
        }
    end
    -- Non-zero d8 to verify displacement add path.
    tests[#tests + 1] = {
        name = "MOVE.L (8,A6,D0.L*4),D1 (D0=1)",
        preload  = preload_dregs({[0] = 1}),
        ram_init = ram,
        test     = concat(bw(0x2236), bw(0x0C08)),   -- scale=4, disp=8
    }
end

-- ======================================================================
-- EXPANSION v3 -- catalog-driven (see SingleStepTests/cpu_isa_catalog.md):
--   * Quick wins: TST, ADDQ/SUBQ, ADDX/SUBX predec-mem form, NEGX
--   * CCR-immediate ops: ANDI/ORI/EORI to CCR
--   * Broader shift/rotate: Dm,Dn register-count form + mem single-bit form
--   * Bit-manipulation memory form: BTST/BCHG/BCLR/BSET Dn,(A6) + #imm,(A6)
--   * BCD predec memory form: ABCD/SBCD/PACK/UNPK -(An),-(An)
--   * Explicit MOVEA.L / MOVEA.W
--   * One 020-only full-extension addressing test
--   * Control flow with marker bytes: Bcc.B/W taken+not-taken (multiple
--     conditions), BRA.B/W, BSR.W/RTS, JSR/RTS, JMP (d16,PC), DBF,
--     Scc (all 16 conditions), LINK/UNLK
--
-- Marker convention for control-flow tests: paths converge to the end of
-- the test bytes; visited path is recorded by MOVE.B #imm,(A6) writes
-- visible in scratch[0]. (1 = not-taken, 2 = taken; 3 = both, 0 = neither.)
-- ======================================================================

-- ---------- TST.L/W/B Dn (gap from catalog) ---------------------------
for _, sz in ipairs({{name="L", bits=0x0080}, {name="W", bits=0x0040}, {name="B", bits=0x0000}}) do
    for _, s in ipairs({
        {v=0x12345678, lbl="pos"},
        {v=0x80000000, lbl="neg"},
        {v=0x00000000, lbl="zero"},
    }) do
        tests[#tests + 1] = {
            name = string.format("TST.%s D0 (0x%08X / %s)", sz.name, s.v, s.lbl),
            preload = preload_dregs({[0] = s.v}),
            test    = bw(0x4A00 | sz.bits | 0),
        }
    end
end

-- ---------- ADDQ / SUBQ #imm,Dn ---------------------------------------
-- ADDQ.L #imm,Dn = $5080 | (data<<9) | dn  (data 1-7, 0 means 8)
-- SUBQ.L         = $5180 | (data<<9) | dn
for _, op in ipairs({{name="ADDQ", base=0x5000}, {name="SUBQ", base=0x5100}}) do
    for _, sz in ipairs({{name="L", bits=0x0080}, {name="W", bits=0x0040}, {name="B", bits=0x0000}}) do
        tests[#tests + 1] = {
            name = string.format("%s.%s #3,D0 (D0=0x12345678)", op.name, sz.name),
            preload = preload_dregs({[0] = 0x12345678}),
            test    = bw(op.base | sz.bits | (3 << 9) | 0),
        }
    end
end
-- ADDQ.L #8,Dn (encoded as data=0)
tests[#tests + 1] = {
    name = "ADDQ.L #8,D0 (data field = 0 means 8)",
    preload = preload_dregs({[0] = 0x12345678}),
    test    = bw(0x5080 | (0 << 9) | 0),
}

-- ---------- ADDX/SUBX -(Ay),-(Ax) predec-memory form ------------------
-- ADDX.L -(A1),-(A0) = $D188 | (Ax=A0<<9) | Ay=A1 = $D189
-- Set A0 and A1 to scratch+8 and scratch+0x10 respectively so they predec
-- to scratch+4 and scratch+0xC (still in range).
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    -- Plant a longword at scratch[4..7] = 0x00000005 and scratch[12..15] = 0x00000003
    ram[5]=0x00; ram[6]=0x00; ram[7]=0x00; ram[8]=0x05
    ram[13]=0x00; ram[14]=0x00; ram[15]=0x00; ram[16]=0x03
    tests[#tests + 1] = {
        name     = "ADDX.L -(A1),-(A0)  mem+mem with X=1",
        preload  = concat(preload_an_scratch({[0] = 8, [1] = 0x10}),
                          preload_ccr(0x10)),    -- X=1
        ram_init = ram,
        test     = bw(0xD189),
    }
    tests[#tests + 1] = {
        name     = "SUBX.L -(A1),-(A0)  mem+mem with X=0",
        preload  = preload_an_scratch({[0] = 8, [1] = 0x10}),
        ram_init = ram,
        test     = bw(0x9189),
    }
end

-- ---------- NEGX.L/W/B Dn ---------------------------------------------
-- NEGX.B = $4000|dn, .W = $4040|dn, .L = $4080|dn
for _, sz in ipairs({{name="L", bits=0x0080}, {name="W", bits=0x0040}, {name="B", bits=0x0000}}) do
    tests[#tests + 1] = {
        name = string.format("NEGX.%s D0  (D0=0x12345678, X=1)", sz.name),
        preload = concat(preload_dregs({[0] = 0x12345678}), preload_ccr(0x10)),
        test    = bw(0x4000 | sz.bits | 0),
    }
end

-- ---------- ANDI/ORI/EORI to CCR --------------------------------------
-- ANDI #imm,CCR = $023C + immediate word (only low 8 bits used)
-- ORI  #imm,CCR = $003C
-- EORI #imm,CCR = $0A3C
tests[#tests + 1] = {
    name = "ANDI #0x10,CCR  (CCR=0x1F & 0x10 = 0x10)",
    preload = preload_ccr(0x1F),
    test    = concat(bw(0x023C), bw(0x0010)),
}
tests[#tests + 1] = {
    name = "ORI #0x08,CCR  (CCR=0x04 | 0x08 = 0x0C)",
    preload = preload_ccr(0x04),
    test    = concat(bw(0x003C), bw(0x0008)),
}
tests[#tests + 1] = {
    name = "EORI #0x0F,CCR  (CCR=0x05 ^ 0x0F = 0x0A)",
    preload = preload_ccr(0x05),
    test    = concat(bw(0x0A3C), bw(0x000F)),
}

-- ---------- Shifts: Dm,Dn register-count form (remaining ops) ---------
-- We previously tested only a subset in Dm,Dn form. Cover the rest:
-- Encoding: $E000 | (cnt_reg<<9) | (dr<<8) | (size<<6) | (ir=1<<5) | (typ<<3) | dn
-- For .L, size=2, ir=1 → 0xA0 base.
for _, sd in ipairs({
    -- name, dr, typ, opword for ".L D1,D0"
    {name="ASR", dr=0, typ=0, op = 0xE000 | (1<<9) | (0<<8) | (2<<6) | (1<<5) | (0<<3) | 0},  -- 0xE2A0
    {name="LSL", dr=1, typ=1, op = 0xE000 | (1<<9) | (1<<8) | (2<<6) | (1<<5) | (1<<3) | 0},  -- 0xE3A8
    {name="ROR", dr=0, typ=3, op = 0xE000 | (1<<9) | (0<<8) | (2<<6) | (1<<5) | (3<<3) | 0},  -- 0xE2B8
    {name="ROXL",dr=1, typ=2, op = 0xE000 | (1<<9) | (1<<8) | (2<<6) | (1<<5) | (2<<3) | 0},  -- 0xE3B0
    {name="ROXR",dr=0, typ=2, op = 0xE000 | (1<<9) | (0<<8) | (2<<6) | (1<<5) | (2<<3) | 0},  -- 0xE2B0
}) do
    tests[#tests + 1] = {
        name = string.format("%s.L D1,D0  reg-count (D0=0x80000001, D1=3, X=1)", sd.name),
        preload = concat(preload_dregs({[0] = 0x80000001, [1] = 3}), preload_ccr(0x10)),
        test    = bw(sd.op),
    }
end

-- ---------- Memory shifts: single-bit on word at (A6) ------------------
-- Encoding: $E0C0 | (dr<<8) | (typ<<9) | <ea>. For (A6) ea=0x16.
-- ASL: typ=0, dr=1 → 0xE1D6
-- ASR: typ=0, dr=0 → 0xE0D6
-- LSL: typ=1, dr=1 → 0xE3D6
-- LSR: typ=1, dr=0 → 0xE2D6
-- ROXL: typ=2, dr=1 → 0xE5D6
-- ROXR: typ=2, dr=0 → 0xE4D6
-- ROL:  typ=3, dr=1 → 0xE7D6
-- ROR:  typ=3, dr=0 → 0xE6D6
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x40; ram[2]=0x01                -- word 0x4001 at scratch[0..1]
    for _, sd in ipairs({
        {name="ASL",  op=0xE1D6}, {name="ASR",  op=0xE0D6},
        {name="LSL",  op=0xE3D6}, {name="LSR",  op=0xE2D6},
        {name="ROXL", op=0xE5D6}, {name="ROXR", op=0xE4D6},
        {name="ROL",  op=0xE7D6}, {name="ROR",  op=0xE6D6},
    }) do
        tests[#tests + 1] = {
            name = string.format("%s.W (A6)  mem-shift, single bit", sd.name),
            preload  = preload_ccr(0x10),       -- X=1 for ROX*
            ram_init = ram,
            test     = bw(sd.op),
        }
    end
end

-- ---------- Bit-manipulation memory form (B-size on (A6)) -------------
-- Dynamic (Dn-driven): opword = $0100 | (typ<<6) | (dn<<9) | <ea>
-- For BTST Dn,(A6): typ=00, ea=0x16 → $0116 | (dn<<9). For dn=1: $0316
-- BCHG: typ=01 → $0156 | (dn<<9)
-- BCLR: typ=10 → $0196 | (dn<<9)
-- BSET: typ=11 → $01D6 | (dn<<9)
-- Static: opword = $0800 | (typ<<6) | <ea>, then 16-bit imm word.
-- For BTST #imm,(A6): $0816 + imm word.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1] = 0x80                            -- bit 7 set at scratch[0]
    for _, b in ipairs({
        {name="BTST",  op=0x0316, suffix="D1=7 -> bit 7"},
        {name="BCHG",  op=0x0356, suffix="D1=7 -> invert bit 7"},
        {name="BCLR",  op=0x0396, suffix="D1=7 -> clear bit 7"},
        {name="BSET",  op=0x03D6, suffix="D1=0 -> set bit 0"},
    }) do
        local d1 = b.name == "BSET" and 0 or 7
        tests[#tests + 1] = {
            name = string.format("%s D1,(A6)  (%s)", b.name, b.suffix),
            preload  = preload_dregs({[1] = d1}),
            ram_init = ram,
            test     = bw(b.op),
        }
    end
    -- Static forms with #imm.
    tests[#tests + 1] = {
        name = "BTST #7,(A6)  static, byte ram=0x80",
        preload = {}, ram_init = ram,
        test    = concat(bw(0x0816), bw(0x0007)),
    }
    tests[#tests + 1] = {
        name = "BSET #0,(A6)  static, byte ram=0x80 -> 0x81",
        preload = {}, ram_init = ram,
        test    = concat(bw(0x08D6), bw(0x0000)),
    }
    tests[#tests + 1] = {
        name = "BCLR #7,(A6)  static, byte ram=0x80 -> 0x00",
        preload = {}, ram_init = ram,
        test    = concat(bw(0x0896), bw(0x0007)),
    }
    tests[#tests + 1] = {
        name = "BCHG #6,(A6)  static, byte ram=0x80 -> 0xC0",
        preload = {}, ram_init = ram,
        test    = concat(bw(0x0856), bw(0x0006)),
    }
end

-- ---------- BCD predec-memory form ------------------------------------
-- ABCD -(Ay),-(Ax) = $C108 | (Ax<<9) | Ay
-- We use A0=dst, A1=src. A0 pre-loaded to scratch+4 (predecrements to +3).
-- A1 pre-loaded to scratch+8 (predecrements to +7). Bytes there hold the BCD operands.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[4]  = 0x25   -- scratch[3] = $25 (BCD operand 1, A0 dst predec target)
    ram[8]  = 0x37   -- scratch[7] = $37 (BCD operand 2, A1 src predec target)
    tests[#tests + 1] = {
        name     = "ABCD -(A1),-(A0)  mem-mem (0x25 + 0x37, X=0)",
        preload  = preload_an_scratch({[0] = 4, [1] = 8}),
        ram_init = ram,
        test     = bw(0xC109),
    }
    tests[#tests + 1] = {
        name     = "SBCD -(A1),-(A0)  mem-mem (0x42 - 0x18, X=0)",
        preload  = preload_an_scratch({[0] = 4, [1] = 8}),
        ram_init = (function()
            local r = {}
            for i = 1, SCRATCH_LEN do r[i] = 0 end
            r[4] = 0x42; r[8] = 0x18
            return r
        end)(),
        test     = bw(0x8109),
    }
    -- PACK predec form: $8108 | (Ax<<9) | Ay + 16-bit adjust
    -- Wait, PACK -(Ay),-(Ax),#adj encoding:
    --   $8100 | (Ax<<9) | (101<<3) | Ay  for predec mem form
    --   = $8108 | (Ax<<9) | Ay -- but bits 5-3 = 101 (mode=5) -> 0x28
    -- Actually PACK is: $8140 | (Ax<<9) | Ay + adj for predec.
    -- Per PRM: PACK -(An),-(An),#data: $8108|(Ax<<9)|(1<<6)|Ay.
    -- For Ax=0, Ay=1: $814A? Hmm.
    -- Looking at the actual encoding:
    --   PACK Dy,Dx,#adjustment:     $8140 | (Dx<<9) | Dy
    --   PACK -(Ay),-(Ax),#adjustment: $8148 | (Ax<<9) | Ay
    -- The bit 3 distinguishes Dn vs -(An) form.
    -- For Ax=0, Ay=1: $8149. Then 2-byte adjustment.
    tests[#tests + 1] = {
        name     = "PACK -(A1),-(A0),#0  mem-mem",
        preload  = preload_an_scratch({[0] = 4, [1] = 8}),
        ram_init = (function()
            local r = {}; for i = 1, SCRATCH_LEN do r[i] = 0 end
            -- Source: 2 bytes, packed-decimal source. Predec twice from A1=8: A1=6 then A1=7, reading bytes 6 and 7.
            r[7] = 0x31; r[8] = 0x32   -- "12" in ASCII-ish
            return r
        end)(),
        test     = concat(bw(0x8149), bw(0x0000)),
    }
    -- UNPK -(Ay),-(Ax),#adjustment: $8188 | (Ax<<9) | Ay
    -- For Ax=0, Ay=1: $8189. Then 2-byte adjustment.
    tests[#tests + 1] = {
        name     = "UNPK -(A1),-(A0),#0x3030  mem-mem",
        preload  = preload_an_scratch({[0] = 6, [1] = 8}),  -- A0 -> 5,4; A1 -> 7
        ram_init = (function()
            local r = {}; for i = 1, SCRATCH_LEN do r[i] = 0 end
            r[8] = 0x12   -- packed BCD byte 0x12
            return r
        end)(),
        test     = concat(bw(0x8189), bw(0x3030)),
    }
end

-- ---------- MOVEA explicit (cover .W and .L) --------------------------
-- MOVEA.L #imm,An = $207C | (an<<9) + 4-byte imm
-- MOVEA.W #imm,An = $307C | (an<<9) + 2-byte imm  (sign-extended to .L)
tests[#tests + 1] = {
    name = "MOVEA.L #0x12345678,A0",
    preload = {},
    test    = concat(bw(0x207C), bl(0x12345678)),
}
tests[#tests + 1] = {
    name = "MOVEA.W #0xFFFE,A1  (sign-extended to 0xFFFFFFFE)",
    preload = {},
    test    = concat(bw(0x327C), bw(0xFFFE)),
}

-- ---------- 020 full-extension addressing  ----------------------------
-- MOVE.L (bd,A6,D0.W),D1 with word base displacement = 0
-- Full ext word: full=1(bit8), D/A=0(Dn), reg=000(D0), W/L=0(W), scale=00,
--   BS=0, IS=0, BDSIZE=10(word), IIS=000(no mem-indirect)
-- = 0_000_0_00_1_0_0_10_0_000 = 0x0120
-- bd word follows: 0x0000
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = i end   -- 1..64 at scratch[0..63]
    tests[#tests + 1] = {
        name     = "MOVE.L (bd.W,A6,D0.W),D1  full-ext, bd=0, D0=8",
        preload  = preload_dregs({[0] = 8}),
        ram_init = ram,
        test     = concat(bw(0x2236), bw(0x0120), bw(0x0000)),
    }
end
-- MOVE.L (bd.L,A6,D0.L*4),D1 with long base displacement = 0
-- = full=1, D/A=0, reg=0, W/L=1(L), scale=10(*4), BS=0, IS=0, BDSIZE=11(L), IIS=0
-- = 0_000_1_10_1_0_0_11_0_000 = 0x0D30
-- bd long follows: 0x00000000
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = i end
    tests[#tests + 1] = {
        name     = "MOVE.L (bd.L,A6,D0.L*4),D1  full-ext scaled, bd=0, D0=2",
        preload  = preload_dregs({[0] = 2}),
        ram_init = ram,
        test     = concat(bw(0x2236), bw(0x0D30), bl(0x00000000)),
    }
end

-- ======================================================================
-- CONTROL FLOW (marker-byte convention: scratch[0] holds the visited path)
-- ======================================================================

-- Helper: emit MOVE.B #imm,(A6)  (4 bytes, writes one byte to scratch[0])
local function emit_mb_to_a6(imm)
    return concat(bw(0x1CBC), bw(imm & 0xFF))
end

-- Helper: emit BRA.B disp  (2 bytes; disp signed byte, nonzero)
local function emit_bra_b(disp)
    return bw(0x6000 | (disp & 0xFF))
end

-- ---------- Bcc.B taken / not-taken ----------------------------------
-- Layout for Bcc.B (12 bytes):
--   $00: Bcc.B disp=$06           ; if taken, target = $02+$06 = $08
--   $02: MOVE.B #1,(A6)           ; not-taken marker (4 bytes)
--   $06: BRA.B disp=$04           ; PC+2=$08, +$04 = $0C = end
--   $08: MOVE.B #2,(A6)           ; taken marker (4 bytes)
--   $0C: end
local function bcc_b_test(name, cc, ccr_in)
    return {
        name    = name,
        preload = preload_ccr(ccr_in),
        test    = concat(
            bw(0x6006 | (cc << 8)),       -- Bcc.B disp=$06
            emit_mb_to_a6(1),             -- not-taken: scratch[0]=1
            emit_bra_b(0x04),             -- jump to end
            emit_mb_to_a6(2)              -- taken: scratch[0]=2
        ),
    }
end
-- Bcc.W (14 bytes):
--   $00: Bcc.W disp=$0008         ; target = $02+$08 = $0A
--   $04: MOVE.B #1,(A6)           ; not-taken (4 bytes)
--   $08: BRA.B disp=$04           ; PC+2=$0A, +$04 = $0E = end
--   $0A: MOVE.B #2,(A6)           ; taken (4 bytes)
--   $0E: end
local function bcc_w_test(name, cc, ccr_in)
    return {
        name    = name,
        preload = preload_ccr(ccr_in),
        test    = concat(
            bw(0x6000 | (cc << 8)), bw(0x0008),  -- Bcc.W disp=$0008
            emit_mb_to_a6(1),
            emit_bra_b(0x04),
            emit_mb_to_a6(2)
        ),
    }
end
-- Pick conditions that resolve both ways with CCR=0x04 (Z=1) and CCR=0x09 (N=1,C=1):
--   With Z=1: BEQ taken, BNE not-taken; BHI not-taken (C∨Z = Z), BLS taken
--   With N=1,C=1: BMI taken, BPL not-taken, BCS taken, BCC not-taken
for _, cs in ipairs({
    {n="BEQ",  cc=0x7, ccr=0x04, suffix="taken (Z=1)"},
    {n="BNE",  cc=0x6, ccr=0x04, suffix="not-taken (Z=1)"},
    {n="BMI",  cc=0xB, ccr=0x09, suffix="taken (N=1)"},
    {n="BPL",  cc=0xA, ccr=0x09, suffix="not-taken (N=1)"},
    {n="BCS",  cc=0x5, ccr=0x09, suffix="taken (C=1)"},
    {n="BCC",  cc=0x4, ccr=0x09, suffix="not-taken (C=1)"},
    {n="BHI",  cc=0x2, ccr=0x04, suffix="not-taken (Z=1)"},
    {n="BLS",  cc=0x3, ccr=0x04, suffix="taken (Z=1)"},
}) do
    tests[#tests + 1] = bcc_b_test(string.format("%s.B  %s", cs.n, cs.suffix), cs.cc, cs.ccr)
    tests[#tests + 1] = bcc_w_test(string.format("%s.W  %s", cs.n, cs.suffix), cs.cc, cs.ccr)
end

-- ---------- BRA.B / BRA.W ---------------------------------------------
-- BRA.B disp=$04 (10 bytes):
--   $00: BRA.B disp=$04           ; target = $02+$04 = $06
--   $02: MOVE.B #1,(A6)           ; (skipped)
--   $06: MOVE.B #2,(A6)           ; (reached)
--   $0A: end
tests[#tests + 1] = {
    name    = "BRA.B  always-skip",
    preload = {},
    test    = concat(
        emit_bra_b(0x04),
        emit_mb_to_a6(1),
        emit_mb_to_a6(2)
    ),
}
-- BRA.W disp=$0006 (10 bytes):
--   $00: BRA.W disp=$0006         ; target = $02+$06 = $08
--   $04: MOVE.B #1,(A6)           ; (skipped)
--   $08: MOVE.B #2,(A6)           ; (reached)
--   $0C: end
tests[#tests + 1] = {
    name    = "BRA.W  always-skip",
    preload = {},
    test    = concat(
        bw(0x6000), bw(0x0006),
        emit_mb_to_a6(1),
        emit_mb_to_a6(2)
    ),
}

-- ---------- BSR/RTS round-trip ----------------------------------------
-- Layout (16 bytes):
--   $00: BRA.B disp=$06           ; skip subroutine
--   $02: MOVE.B #2,(A6)           ; subroutine body
--   $06: RTS                      ; (2 bytes)
--   $08: BSR.W disp=$FFF8         ; target = $0A + (-$08) = $02
--   $0C: MOVE.B #1,(A6)           ; runs AFTER RTS returns (overwrites)
--   $10: end
-- After test: scratch[0] = 1 (caller's write happened last)
-- A7 unchanged (BSR pushed 4, RTS popped 4)
tests[#tests + 1] = {
    name    = "BSR.W / RTS  round-trip",
    preload = {},
    test    = concat(
        emit_bra_b(0x06),
        emit_mb_to_a6(2),
        bw(0x4E75),                 -- RTS
        bw(0x6100), bw(0xFFF8),     -- BSR.W disp=-8
        emit_mb_to_a6(1)
    ),
}

-- ---------- JSR (d16,PC) / RTS round-trip -----------------------------
-- Same shape; JSR (d16,PC) = $4EBA + word disp.
-- disp from JSR PC+2. From $08, PC+2=$0A. Target $02 → disp = -8 = 0xFFF8.
tests[#tests + 1] = {
    name    = "JSR (d16,PC) / RTS  round-trip",
    preload = {},
    test    = concat(
        emit_bra_b(0x06),
        emit_mb_to_a6(2),
        bw(0x4E75),
        bw(0x4EBA), bw(0xFFF8),     -- JSR (d16,PC) disp=-8
        emit_mb_to_a6(1)
    ),
}

-- ---------- JMP (d16,PC)  (jumps to next instruction = no-op) ---------
-- JMP (d16,PC): target = (address of displacement word) + disp.
-- The disp word lives at test_pc+2 = $1006. To jump to the byte right
-- AFTER the JMP (= $1008, where the bench's MOVE CCR begins), use disp=2.
-- Using disp=0 would land back inside the JMP's own extension word and
-- execute garbage; explicitly verified misbehaves in both MAME and TG68K.
tests[#tests + 1] = {
    name    = "JMP (d16,PC) disp=2  no-op (target = next instruction)",
    preload = {},
    test    = concat(bw(0x4EFA), bw(0x0002)),
}

-- ---------- DBF (DBRA) loop counter -----------------------------------
-- Layout (6 bytes):
--   $00: ADDQ.B #1,(A6)           ; ADDQ.B #1,(A6) = $5216 (2 bytes)
--   $02: DBF D1,disp=$FFFC         ; branch back to $00 if D1.W≠-1 (4 bytes)
--   $06: end
-- D1 init = 2 → loop runs 3x → scratch[0]=3, D1.L = 0x0000FFFF
tests[#tests + 1] = {
    name    = "DBF D1,loop  (D1=2 -> counts to -1, scratch[0]=3)",
    preload = preload_dregs({[1] = 2}),
    test    = concat(
        bw(0x5216),                 -- ADDQ.B #1,(A6)
        bw(0x51C9), bw(0xFFFC)      -- DBF D1, disp=-4
    ),
}
-- DBNE D1,loop with NE condition that becomes false during loop:
-- Setup: CCR=0x04 (Z=1) so DBNE condition NE is FALSE → DB falls into decrement.
-- D1 = 3 → DBNE decrements: 2 (branch), 1 (branch), 0 (branch), -1 (exit).
tests[#tests + 1] = {
    name    = "DBNE D1,loop  (Z=1 so NE always false; counts to -1)",
    preload = concat(preload_dregs({[1] = 3}), preload_ccr(0x04)),
    test    = concat(
        bw(0x5216),                 -- ADDQ.B #1,(A6)
        bw(0x56C9), bw(0xFFFC)      -- DBNE D1, disp=-4
    ),
}
-- DBEQ where condition (EQ=Z=1) is TRUE: DBcc never decrements when cc true.
-- So D1 unchanged, loop exits immediately. scratch[0] = 1 (body runs once before DBEQ).
tests[#tests + 1] = {
    name    = "DBEQ D1,loop  (Z=1 so EQ true; loop exits immediately)",
    preload = concat(preload_dregs({[1] = 3}), preload_ccr(0x04)),
    test    = concat(
        bw(0x5216),
        bw(0x57C9), bw(0xFFFC)      -- DBEQ D1
    ),
}

-- ---------- Scc Dn for all 16 conditions ------------------------------
-- Scc Dn = $50C0 | (cc<<8) | dn
-- Use CCR=0x04 (Z=1): each condition produces $FF or $00 in Dn.B per the
-- truth table. This exercises every condition encoding the chip implements.
local CC_LIST = {
    {n="ST",  cc=0x0}, {n="SF",  cc=0x1},
    {n="SHI", cc=0x2}, {n="SLS", cc=0x3},
    {n="SCC", cc=0x4}, {n="SCS", cc=0x5},
    {n="SNE", cc=0x6}, {n="SEQ", cc=0x7},
    {n="SVC", cc=0x8}, {n="SVS", cc=0x9},
    {n="SPL", cc=0xA}, {n="SMI", cc=0xB},
    {n="SGE", cc=0xC}, {n="SLT", cc=0xD},
    {n="SGT", cc=0xE}, {n="SLE", cc=0xF},
}
for _, c in ipairs(CC_LIST) do
    tests[#tests + 1] = {
        name    = string.format("%s D0  (CCR=0x04, Z=1)", c.n),
        preload = concat(preload_dregs({[0] = 0xAABBCC00}), preload_ccr(0x04)),
        test    = bw(0x50C0 | (c.cc << 8) | 0),
    }
end

-- ---------- LINK / UNLK net-no-op -------------------------------------
-- LINK A0,#-16 ; UNLK A0. A0 and A7 should be unchanged from start.
-- LINK A0,#imm = $4E50 | an + signed 16-bit imm.
-- UNLK A0 = $4E58 | an.
tests[#tests + 1] = {
    name    = "LINK A0,#-16 / UNLK A0  (net no-op)",
    preload = preload_an_scratch({[0] = 0x20}),
    test    = concat(
        bw(0x4E50), bw(0xFFF0),     -- LINK A0,#-16
        bw(0x4E58)                  -- UNLK A0
    ),
}

-- ======================================================================
-- EXPANSION v5 -- TG68K bug-hunting batch
--
-- Targets the highest-bug-surface gaps from cpu_isa_catalog.md:
--   * 020 full-extension addressing in memory-indirect forms
--     ([bd,An]+od) and ([bd,An,Xn]+od) -- never tested before
--   * PC-relative source EAs: (d16,PC), (d8,PC,Xn), (bd,PC,Xn)
--   * Absolute-short (xxx).W with sign-extension
--   * EXG (Dn,Dn / An,An / Dn,An)
--   * MOVE byte/word memory variants (previously only .L tested)
--   * MOVEM with -(An) / (An)+ (only (A6) tested before)
--   * ADDA / SUBA / CMPA mem,An and Dn,An (only #imm,An tested)
--   * Shift sizes .B and .W for all 8 ops (only .L tested broadly)
--   * TAS Dn and TAS (A6) -- atomic test-and-set
--   * CHK2.W / CMP2.W with in-bounds & on-boundary cases
--   * TRAPV with V=0 (falls through, not an exception)
-- ======================================================================

-- ---------- 020 memory-indirect addressing (preindexed / postindexed) -
-- Pointer placed at scratch[0..3] = $00001808 (scratch+8).
-- Target longword placed at scratch[8..11] = $DEADCAFE.
do
    local function ram_with_ptr_and_value(ptr_off, val_off, value)
        local r = {}
        for i = 1, SCRATCH_LEN do r[i] = 0 end
        local ptr_abs = SCRATCH_BASE + val_off
        r[ptr_off + 1] = (ptr_abs >> 24) & 0xFF
        r[ptr_off + 2] = (ptr_abs >> 16) & 0xFF
        r[ptr_off + 3] = (ptr_abs >>  8) & 0xFF
        r[ptr_off + 4] =  ptr_abs        & 0xFF
        r[val_off + 1] = (value >> 24) & 0xFF
        r[val_off + 2] = (value >> 16) & 0xFF
        r[val_off + 3] = (value >>  8) & 0xFF
        r[val_off + 4] =  value        & 0xFF
        return r
    end

    -- MOVE.L ([bd.W,A6]),D1  -- memory indirect, no index (IS=1), no od.
    -- Full ext: D/A=0 reg=000 W/L=0 scale=00 full=1 BS=0 IS=1 BDSIZE=10 IIS=101
    -- = 0_000_0_00_1_0_1_10_0_101 = 0x0165
    -- bd word = 0; pointer at A6+0 -> reads value pointer points to.
    tests[#tests + 1] = {
        name     = "MOVE.L ([bd.W,A6]),D1  memind no-idx no-od (->DEADCAFE)",
        preload  = {},
        ram_init = ram_with_ptr_and_value(0, 8, 0xDEADCAFE),
        test     = concat(bw(0x2236), bw(0x0165), bw(0x0000)),
    }

    -- MOVE.L ([bd.W,A6],D0.L*2,od.W),D1 -- postindexed with scaled index + word od.
    -- IIS=110 (postindexed, word od); W/L=1; scale=01.
    -- = 0_000_1_01_1_0_0_10_0_110 = 0x0B26
    -- bd=0, od=0. EA = MEM[A6] + D0*2.
    --   Pointer at A6+0 = $1800 itself -> read =>$1800; +D0(=4)*2=8 -> $1808 -> read 0xDEADCAFE.
    do
        local r = ram_with_ptr_and_value(0, 8, 0xDEADCAFE)
        -- Override pointer to $1800 so post-index lands at $1808.
        r[1] = 0x00; r[2] = 0x00; r[3] = 0x18; r[4] = 0x00
        tests[#tests + 1] = {
            name     = "MOVE.L ([bd.W,A6],D0.L*2,od.W),D1  postindexed scaled+od (D0=4)",
            preload  = preload_dregs({[0] = 4}),
            ram_init = r,
            test     = concat(bw(0x2236), bw(0x0B26), bw(0x0000), bw(0x0000)),
        }
    end

    -- MOVE.L ([bd.W,A6,D0.L*2],od.W),D1 -- preindexed (index THEN indirect)
    -- IIS=010 (preindexed word od); W/L=1; scale=01.
    -- = 0_000_1_01_1_0_0_10_0_010 = 0x0B22
    -- bd=0, od=0. EA = MEM[A6 + D0*2].
    --   D0=2 -> MEM[$1804] = pointer at scratch[4..7]; we place $00001808 there
    --   -> read longword at $1808 = $0BADC0DE.
    do
        local r = ram_with_ptr_and_value(4, 8, 0x0BADC0DE)
        tests[#tests + 1] = {
            name     = "MOVE.L ([bd.W,A6,D0.L*2],od.W),D1  preindexed scaled+od (D0=2)",
            preload  = preload_dregs({[0] = 2}),
            ram_init = r,
            test     = concat(bw(0x2236), bw(0x0B22), bw(0x0000), bw(0x0000)),
        }
    end

    -- MOVE.L ([bd.L,A6],D0.L*4,od.L),D1 -- postindexed, LONG bd and LONG od (all zero).
    -- IIS=111 (postindexed long od); W/L=1; scale=10(*4).
    -- = 0_000_1_10_1_0_0_11_0_111 = 0x0D37
    -- bd.L = 0; od.L = 0. EA = MEM[A6+0] + D0*4 = $1800 + D0*4.
    --   D0=2, pointer at A6+0 -> $1800; +D0*4(8) = $1808 -> 0xCAFEF00D.
    do
        local r = ram_with_ptr_and_value(0, 8, 0xCAFEF00D)
        r[1] = 0x00; r[2] = 0x00; r[3] = 0x18; r[4] = 0x00
        tests[#tests + 1] = {
            name     = "MOVE.L ([bd.L,A6],D0.L*4,od.L),D1  postindexed long+long (D0=2)",
            preload  = preload_dregs({[0] = 2}),
            ram_init = r,
            test     = concat(bw(0x2236), bw(0x0D37),
                              bl(0x00000000), bl(0x00000000)),
        }
    end
end

-- ---------- PC-relative addressing source EAs --------------------------
-- We embed the data inside the test bytes and use a BRA.B to jump past
-- it so the CPU never executes the data. All PC-rel modes use opword
-- mode=7 (reg=2 for d16,PC; reg=3 for d8/bd-indexed PC).
--
-- Test layout (sized so the BRA.B lands exactly at the dump epilogue):
--   $00..: MOVE.L (...),D1            -- opword + ext (+ maybe bd word)
--   $XX..: BRA.B disp                 -- skip over the data words
--   $YY..: 4 bytes of data (0x11223344)

-- (d16,PC) -- opword=$223A; ext=disp16. PC at ext word = test_pc+2.
-- Layout (10 bytes):
--   off 0..1: $22 $3A          opword
--   off 2..3: $00 $04          ext = +4 -> EA = test_pc+2+4 = test_pc+6
--   off 4..5: $60 $04          BRA.B disp=+4 -> after-branch PC = test_pc+10
--   off 6..9: $11 $22 $33 $44  data read by MOVE.L
-- dump_pc = test_pc+10 (after the 10-byte test).
tests[#tests + 1] = {
    name    = "MOVE.L (d16,PC),D1  disp=4 -> reads 0x11223344",
    preload = {},
    test    = concat(bw(0x223A), bw(0x0004),
                     bw(0x6004),
                     bw(0x1122), bw(0x3344)),
}

-- (d8,PC,Dn.W) -- brief PC-indexed. opword=$223B; brief ext word.
-- Brief ext: D/A=0, reg=0(D0), W/L=0(W), scale=0, full=0, disp=byte.
-- D0=0, disp=4 -> target = test_pc+2 + 4 = test_pc+6 (data).
tests[#tests + 1] = {
    name    = "MOVE.L (d8,PC,D0.W),D1  brief PC-idx (D0=0, disp=4)",
    preload = preload_dregs({[0] = 0}),
    test    = concat(bw(0x223B), bw(0x0004),
                     bw(0x6004),
                     bw(0x1122), bw(0x3344)),
}

-- (bd.W,PC,Dn.W) -- full PC-indexed. opword=$223B; full ext.
-- Full ext: D/A=0 reg=0 W/L=0 scale=00 full=1 BS=0 IS=0 BDSIZE=10 IIS=000
-- = 0_000_0_00_1_0_0_10_0_000 = 0x0120
-- bd=word. PC at full-ext word = test_pc+2. Layout grows by 2 bytes vs brief.
--   off 0: $22 $3B
--   off 2: $01 $20            full ext
--   off 4: $00 $06            bd = 6 (target = (test_pc+2)+6 = test_pc+8)
--   off 6: $60 $04            BRA.B (PC_after=test_pc+8; +4 -> test_pc+12=dump)
--   off 8: data
tests[#tests + 1] = {
    name    = "MOVE.L (bd.W,PC,D0.W),D1  full PC-idx (D0=0, bd=6)",
    preload = preload_dregs({[0] = 0}),
    test    = concat(bw(0x223B), bw(0x0120), bw(0x0006),
                     bw(0x6004),
                     bw(0x1122), bw(0x3344)),
}

-- ---------- Absolute-short addressing source (xxx).W -----------------
-- MOVE.L (xxx).W,D1 = opword $2238 + word abs addr (sign-extended to 32-bit).
-- Use $1820 = scratch+0x20 (positive 16-bit so no sign-ext surprise).
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[0x21] = 0x12; ram[0x22] = 0x34; ram[0x23] = 0x56; ram[0x24] = 0x78
    tests[#tests + 1] = {
        name     = "MOVE.L (xxx).W=$1820,D1  abs-short read",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0x2238), bw(0x1820)),
    }
end

-- ---------- EXG (Dn,Dn / An,An / Dn,An) ------------------------------
-- EXG Dx,Dy: $C140 | (Rx<<9) | Ry  (opmode=01000)
-- EXG Ax,Ay: $C148 | (Rx<<9) | Ry  (opmode=01001)
-- EXG Dx,Ay: $C188 | (Rx<<9) | Ry  (opmode=10001)
tests[#tests + 1] = {
    name    = "EXG D1,D0  (D1=0xCAFE D0=0xBABE)",
    preload = preload_dregs({[0] = 0x0000BABE, [1] = 0x0000CAFE}),
    test    = bw(0xC340),   -- Rx=D1<<9 -> $C100|$200|$40|0 = $C340
}
tests[#tests + 1] = {
    -- EXG Ax,Ay: $C100 | (Rx<<9) | (9<<3) | Ry.  For A2,A3: $C54B.
    name    = "EXG A2,A3  (A2=scratch+4 A3=scratch+8)",
    preload = preload_an_scratch({[2] = 4, [3] = 8}),
    test    = bw(0xC54B),
}
tests[#tests + 1] = {
    name    = "EXG D1,A0  (D1=0xDEADBEEF A0=scratch)",
    preload = concat(preload_dregs({[1] = 0xDEADBEEF}),
                     preload_an_scratch({[0] = 0})),
    test    = bw(0xC388),   -- Rx=D1<<9=$200, opmode<<3=$88, Ry=A0=0 -> $C388
}

-- ---------- MOVE byte/word memory variants ----------------------------
-- MOVE.W Dm,(A6): mode_dst=2,reg_dst=6 -> $3080 | (6<<9) | dm = $3C80|dm
-- For D0 src: $3C80.
-- MOVE.B Dm,(A6): $1080 | (6<<9) | dm = $1C80|dm. For D0: $1C80.
-- MOVE.W d16(A6),Dn: src mode=5,reg=6 -> ea=$2E. opword = $3000|(dn<<9)|$2E
--   = $302E for D0.
-- MOVE.B (A6)+,Dn: src mode=3,reg=6 -> ea=$1E. opword = $1000|(dn<<9)|$1E = $101E for D0.
tests[#tests + 1] = {
    name    = "MOVE.W D0,(A6)  (D0=0xAABB1234 -> [A6]=0x1234)",
    preload = preload_dregs({[0] = 0xAABB1234}),
    test    = bw(0x3C80),
}
tests[#tests + 1] = {
    name    = "MOVE.B D0,(A6)  (D0=0xAABBCCDD -> [A6]=0xDD)",
    preload = preload_dregs({[0] = 0xAABBCCDD}),
    test    = bw(0x1C80),
}
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0xAA; ram[2]=0xBB; ram[3]=0xCC; ram[4]=0xDD
    tests[#tests + 1] = {
        name     = "MOVE.W 0(A6),D0  (reads word 0xAABB)",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0x302E), bw(0x0000)),
    }
    tests[#tests + 1] = {
        name     = "MOVE.B (A1)+,D0  A1=scratch (reads byte 0xAA, A1+=1)",
        preload  = preload_an_scratch({[1] = 0}),
        ram_init = ram,
        test     = bw(0x1019),    -- MOVE.B (A1)+,D0
    }
    tests[#tests + 1] = {
        name     = "MOVE.W -(A1),D0  A1=scratch+4 (reads word 0xCCDD, A1-=2)",
        preload  = preload_an_scratch({[1] = 4}),
        ram_init = ram,
        test     = bw(0x3021),    -- MOVE.W -(A1),D0
    }
end

-- ---------- MOVEM with -(An) and (An)+ --------------------------------
-- MOVEM.L D0-D3,-(A1): regs->predec mem. opword = $48A0 | reg.
-- Mask order for predec is REVERSED: bit 0 = A7, bit 15 = D0. For D0-D3
-- (the low 4 D regs) -> mask bits 12..15 set -> mask = $F000.
-- A1 must be high enough that 4 predecs (4*4=16 bytes) stay in scratch.
-- A1 = scratch+0x20 -> writes scratch[$1C..$1F],[$18..$1B],[$14..$17],[$10..$13].
tests[#tests + 1] = {
    name    = "MOVEM.L D0-D3,-(A1)  predec  A1=scratch+0x20",
    preload = concat(
        preload_dregs({[0]=0xAAAAAAAA,[1]=0xBBBBBBBB,[2]=0xCCCCCCCC,[3]=0xDDDDDDDD}),
        preload_an_scratch({[1] = 0x20})),
    test    = concat(bw(0x48E1), bw(0xF000)),
    -- opword = $4880 | size=$40 | <ea>=0x21 (mode=4,reg=1) = $48E1.
}
-- MOVEM.L (A1)+,D4-D7: mem->postinc regs. opword = $4CD9 (size=L, ea=mode=3,reg=1=0x19).
-- mask for postinc: bit 0=D0,bit 15=A7. D4-D7 -> bits 4..7 = $00F0.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    -- 16 bytes of pattern at scratch[0..15].
    ram[1]=0xAA;ram[2]=0xAA;ram[3]=0xAA;ram[4]=0xAA
    ram[5]=0xBB;ram[6]=0xBB;ram[7]=0xBB;ram[8]=0xBB
    ram[9]=0xCC;ram[10]=0xCC;ram[11]=0xCC;ram[12]=0xCC
    ram[13]=0xDD;ram[14]=0xDD;ram[15]=0xDD;ram[16]=0xDD
    tests[#tests + 1] = {
        name     = "MOVEM.L (A1)+,D4-D7  postinc  A1=scratch",
        preload  = preload_an_scratch({[1] = 0}),
        ram_init = ram,
        test     = concat(bw(0x4CD9), bw(0x00F0)),
    }
end

-- ---------- ADDA/SUBA/CMPA Dn,An and mem,An --------------------------
-- ADDA.L Dn,An = $D1C0 | (an<<9) | dn (size=L). For D0,A0: $D1C0.
-- SUBA.L Dn,An = $91C0 | ...
-- CMPA.L Dn,An = $B1C0 | ...
-- ADDA.L (A1),A0 = $D1D1 (ea=$11)
tests[#tests + 1] = {
    name    = "ADDA.L D0,A0  (D0=0x100, A0=scratch -> A0+=0x100)",
    preload = concat(preload_dregs({[0] = 0x00000100}),
                     preload_an_scratch({[0] = 0})),
    test    = bw(0xD1C0),
}
tests[#tests + 1] = {
    name    = "SUBA.L D0,A0  (D0=0x10, A0=scratch+0x20 -> A0-=0x10)",
    preload = concat(preload_dregs({[0] = 0x00000010}),
                     preload_an_scratch({[0] = 0x20})),
    test    = bw(0x91C0),
}
tests[#tests + 1] = {
    name    = "ADDA.W D0,A0  (D0=0xFFFFFFFE sign-ext to .L; A0=scratch+0x20)",
    preload = concat(preload_dregs({[0] = 0xFFFFFFFE}),
                     preload_an_scratch({[0] = 0x20})),
    test    = bw(0xD0C0),    -- ADDA.W = $D0C0 | (an<<9) | <ea>
}
tests[#tests + 1] = {
    name    = "CMPA.L D0,A0  (D0=scratch+8, A0=scratch+8 -> Z=1)",
    preload = concat(preload_dregs({[0] = SCRATCH_BASE + 8}),
                     preload_an_scratch({[0] = 8})),
    test    = bw(0xB1C0),
}
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x00;ram[2]=0x00;ram[3]=0x00;ram[4]=0x10
    tests[#tests + 1] = {
        name     = "ADDA.L (A1),A0  A0=scratch+0x20, A1=scratch (reads $10)",
        preload  = preload_an_scratch({[0] = 0x20, [1] = 0}),
        ram_init = ram,
        test     = bw(0xD1D1),
    }
end

-- ---------- Shift sizes .B and .W (immediate count and Dm,Dn) ---------
-- We only had .L coverage broadly. Add .W and .B for a representative
-- subset: ASL/ASR/LSR/ROL.
-- Encoding: $E000 | (cnt<<9) | (dr<<8) | (size<<6) | (ir<<5) | (typ<<3) | dn
-- size: .B=00, .W=01. ir=0 (imm), ir=1 (reg).
for _, sd in ipairs({
    {name="ASL", dr=1, typ=0},
    {name="ASR", dr=0, typ=0},
    {name="LSR", dr=0, typ=1},
    {name="ROL", dr=1, typ=3},
}) do
    -- .W #4,Dn imm form
    local op_w_imm = 0xE000 | (4<<9) | (sd.dr<<8) | (1<<6) | (0<<5) | (sd.typ<<3) | 0
    tests[#tests + 1] = {
        name    = string.format("%s.W #4,D0  (D0=0x12345678)", sd.name),
        preload = preload_dregs({[0] = 0x12345678}),
        test    = bw(op_w_imm),
    }
    -- .B Dm,Dn reg form
    local op_b_reg = 0xE000 | (1<<9) | (sd.dr<<8) | (0<<6) | (1<<5) | (sd.typ<<3) | 0
    tests[#tests + 1] = {
        name    = string.format("%s.B D1,D0  reg-count (D0=0x000000F0, D1=2)", sd.name),
        preload = preload_dregs({[0] = 0x000000F0, [1] = 2}),
        test    = bw(op_b_reg),
    }
end

-- ---------- TAS (atomic test-and-set) --------------------------------
-- TAS <ea>: $4AC0 | <ea>. Sets N from MSB and Z from value==0 of source,
-- then sets bit 7 of source. Byte-size only.
tests[#tests + 1] = {
    name    = "TAS D0  (D0=0x00 -> Z=1, D0.B=0x80)",
    preload = preload_dregs({[0] = 0x00000000}),
    test    = bw(0x4AC0),
}
tests[#tests + 1] = {
    name    = "TAS D0  (D0=0x7F -> N=0,Z=0; D0.B=0xFF)",
    preload = preload_dregs({[0] = 0x0000007F}),
    test    = bw(0x4AC0),
}
tests[#tests + 1] = {
    name    = "TAS D0  (D0=0x80 -> N=1,Z=0; D0.B=0x80)",
    preload = preload_dregs({[0] = 0x00000080}),
    test    = bw(0x4AC0),
}
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1] = 0x40   -- byte at scratch[0] = 0x40 -> after TAS = 0xC0
    tests[#tests + 1] = {
        name     = "TAS (A6)  (ram[0]=0x40 -> N=0,Z=0; ram[0]=0xC0)",
        preload  = {},
        ram_init = ram,
        test     = bw(0x4AD6),  -- $4AC0|0x16
    }
end

-- ---------- CHK2 / CMP2 (bounds in memory) ---------------------------
-- opword: $00C0 | (size<<9) | <ea>; size: B=00,W=01,L=10.
-- ext: D/A(1) reg(3) opmode(1) 0... -> CHK2 opmode=1, CMP2 opmode=0.
-- CHK2/CMP2 read the two bounds from <ea> as adjacent operand-size values
-- (low first, then high).
-- For .W (size=$2): opword $02C0 | <ea>. (A6) ea=$16 -> opword=$02D6.
-- Bounds at scratch: low=$0010 (word at 0..1), high=$0030 (word at 2..3).
-- ext for D0,CMP2.W: D/A=0,reg=0,opmode=0 -> ext=$0000.
-- ext for D0,CHK2.W: opmode=1 -> ext=$0800.
do
    local r = {}
    for i = 1, SCRATCH_LEN do r[i] = 0 end
    r[1]=0x00; r[2]=0x10; r[3]=0x00; r[4]=0x30   -- low=$10, high=$30
    -- PRM page 4-58 (CMP2/CHK2): N is undefined; only Z and C are spec'd.
    -- TG68K leaves N from internal subtract result; MAME clears it.
    local MASK_NO_N = 0xF7
    tests[#tests + 1] = {
        name     = "CMP2.W (A6),D0  in-range  (D0=0x20, bounds[$10,$30])",
        preload  = preload_dregs({[0] = 0x00000020}),
        ram_init = r,
        test     = concat(bw(0x02D6), bw(0x0000)),
        ccr_mask = MASK_NO_N,
    }
    tests[#tests + 1] = {
        name     = "CMP2.W (A6),D0  on-boundary  (D0=0x10 -> Z=1)",
        preload  = preload_dregs({[0] = 0x00000010}),
        ram_init = r,
        test     = concat(bw(0x02D6), bw(0x0000)),
        ccr_mask = MASK_NO_N,
    }
    tests[#tests + 1] = {
        name     = "CMP2.W (A6),D0  out-of-range  (D0=0x100 -> C=1)",
        preload  = preload_dregs({[0] = 0x00000100}),
        ram_init = r,
        test     = concat(bw(0x02D6), bw(0x0000)),
        ccr_mask = MASK_NO_N,
    }
    tests[#tests + 1] = {
        name     = "CHK2.W (A6),D0  in-range  (D0=0x20, no trap)",
        preload  = preload_dregs({[0] = 0x00000020}),
        ram_init = r,
        test     = concat(bw(0x02D6), bw(0x0800)),
        ccr_mask = MASK_NO_N,
    }
end

-- ---------- TRAPV with V=0 (does NOT trap) ---------------------------
-- TRAPV traps only when V=1. With V=0 it's a no-op (modulo cycles).
tests[#tests + 1] = {
    name    = "TRAPV  V=0 (no trap, falls through)",
    preload = preload_ccr(0x00),   -- V=0
    test    = bw(0x4E76),
}

-- ---------- More CMP forms (mem source) ------------------------------
-- CMP.L (A6),D0: src mode=2,reg=6 ea=$16 -> $B080|<dn-9>|$16 -> for D0: $B096
-- CMP.W (A6)+,D0: ea=$1E -> $B05E
do
    local r = {}
    for i = 1, SCRATCH_LEN do r[i] = 0 end
    r[1]=0x12;r[2]=0x34;r[3]=0x56;r[4]=0x78
    tests[#tests + 1] = {
        name     = "CMP.L (A6),D0  (D0=0x12345678 vs ram=0x12345678 -> Z=1)",
        preload  = preload_dregs({[0] = 0x12345678}),
        ram_init = r,
        test     = bw(0xB096),
    }
end

-- ---------- ADDQ/SUBQ on An (no flags affected) ----------------------
-- ADDQ.L #1,A0 = $5088 | An. Per PRM, when dst is An, the operation is
-- always .L (regardless of size field) and flags are NOT affected.
tests[#tests + 1] = {
    name    = "ADDQ.L #5,A0  (A0=scratch+0x10 -> +5; CCR unaffected)",
    preload = concat(preload_an_scratch({[0] = 0x10}), preload_ccr(0x1F)),
    test    = bw(0x5A88),    -- ADDQ.L #5,A0 = $5088|(5<<9)|0 = $5A88
}
tests[#tests + 1] = {
    name    = "SUBQ.L #3,A1  (A1=scratch+0x10 -> -3; CCR unaffected)",
    preload = concat(preload_an_scratch({[1] = 0x10}), preload_ccr(0x1F)),
    test    = bw(0x5789),    -- SUBQ.L #3,A1 = $5180|(3<<9)|1 = $5789
}

-- ======================================================================
-- EXPANSION v6 -- broader EA coverage
--
-- Goal: exercise every operand-EA-mode decode path in TG68K. v5 hit the
-- highest bug-surface gaps (memory-indirect, PC-rel). v6 fills in the
-- long tail: ALU/IMM with memory destinations and memory sources;
-- control-flow long-displacement forms; remaining DBcc conditions; more
-- JMP/JSR EAs; RTR/RTD/PEA/LINK.L; bit-field on memory; mem-shift ROL/ROR.
-- ======================================================================

-- ---------- ALU mem-source: <op>.{B,W,L} (A6),D0 ---------------------
-- Opmode bits 8..6 for ea->Dn: B=000, W=001, L=010 -> $0/$40/$80.
-- ea (A6) = $16.
local ALU_BASE = {
    {name="ADD", base=0xD000}, {name="SUB", base=0x9000},
    {name="AND", base=0xC000}, {name="OR",  base=0x8000},
}
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    -- scratch[0..3] holds the longword $00010002 (so byte=$00, word=$0001, long=$00010002)
    ram[1]=0x00; ram[2]=0x01; ram[3]=0x00; ram[4]=0x02
    for _, op in ipairs(ALU_BASE) do
        for _, sz in ipairs({{n="L",bits=0x0080},{n="W",bits=0x0040},{n="B",bits=0x0000}}) do
            tests[#tests + 1] = {
                name = string.format("%s.%s (A6),D0  mem-src (D0=0x12345678)", op.name, sz.n),
                preload  = preload_dregs({[0] = 0x12345678}),
                ram_init = ram,
                test     = bw(op.base | sz.bits | (0<<9) | 0x16),
            }
        end
    end
end

-- ---------- ALU mem-dest: <op>.{B,W,L} D0,(A6) ----------------------
-- Opmode bits 8..6 for Dn->ea: B=100, W=101, L=110 -> $100/$140/$180.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    -- scratch[0..3] = $0A0B0C0D, so byte=$0A, word=$0A0B, long=$0A0B0C0D
    ram[1]=0x0A; ram[2]=0x0B; ram[3]=0x0C; ram[4]=0x0D
    for _, op in ipairs(ALU_BASE) do
        for _, sz in ipairs({{n="L",bits=0x0180},{n="W",bits=0x0140},{n="B",bits=0x0100}}) do
            tests[#tests + 1] = {
                name = string.format("%s.%s D0,(A6)  mem-dst (D0=0xCAFEBABE)", op.name, sz.n),
                preload  = preload_dregs({[0] = 0xCAFEBABE}),
                ram_init = ram,
                test     = bw(op.base | sz.bits | (0<<9) | 0x16),
            }
        end
    end
end

-- EOR is Dn->ea only. opmode bits 8..6: B=100, W=101, L=110.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x0F; ram[2]=0xF0; ram[3]=0x55; ram[4]=0xAA
    for _, sz in ipairs({{n="L",bits=0x0180},{n="W",bits=0x0140},{n="B",bits=0x0100}}) do
        tests[#tests + 1] = {
            name = string.format("EOR.%s D0,(A6)  mem-dst (D0=0xCAFEBABE)", sz.n),
            preload  = preload_dregs({[0] = 0xCAFEBABE}),
            ram_init = ram,
            test     = bw(0xB000 | sz.bits | (0<<9) | 0x16),
        }
    end
end

-- ---------- Immediate-to-memory: <IMMOP>.{B,W,L} #imm,(A6) ----------
-- Opcode: <base> | <size> | <ea>. size bits 7..6: B=00, W=$40, L=$80.
-- Immediate follows: word (B/W; B uses low byte) or longword (L).
local IMM_OPS_MEM = {
    {name="ADDI", base=0x0600},
    {name="SUBI", base=0x0400},
    {name="ANDI", base=0x0200},
    {name="ORI",  base=0x0000},
    {name="EORI", base=0x0A00},
}
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x00; ram[2]=0x00; ram[3]=0x00; ram[4]=0x10   -- long = $00000010
    for _, op in ipairs(IMM_OPS_MEM) do
        -- .L form
        tests[#tests + 1] = {
            name     = string.format("%s.L #0x12345678,(A6)", op.name),
            preload  = {},
            ram_init = ram,
            test     = concat(bw(op.base | 0x0080 | 0x16), bl(0x12345678)),
        }
        -- .W form
        tests[#tests + 1] = {
            name     = string.format("%s.W #0x1234,(A6)", op.name),
            preload  = {},
            ram_init = ram,
            test     = concat(bw(op.base | 0x0040 | 0x16), bw(0x1234)),
        }
        -- .B form (immediate is a word, low byte used)
        tests[#tests + 1] = {
            name     = string.format("%s.B #0x55,(A6)", op.name),
            preload  = {},
            ram_init = ram,
            test     = concat(bw(op.base | 0x0000 | 0x16), bw(0x0055)),
        }
    end
end

-- CMPI to memory: $0C<sz><ea> + imm.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x00; ram[2]=0x00; ram[3]=0x12; ram[4]=0x34
    tests[#tests + 1] = {
        name     = "CMPI.L #0x00001234,(A6)  (Z=1)",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0x0C00 | 0x0080 | 0x16), bl(0x00001234)),
    }
    tests[#tests + 1] = {
        name     = "CMPI.W #0x1234,(A6)  (cmp word at A6 = 0x0000)",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0x0C00 | 0x0040 | 0x16), bw(0x1234)),
    }
    tests[#tests + 1] = {
        name     = "CMPI.B #0x00,(A6)  (Z=1)",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0x0C00 | 0x0000 | 0x16), bw(0x0000)),
    }
end

-- ---------- CMP broader sources -------------------------------------
-- CMP.L (A6),D0 already in v5. Add (An)+/-(An)/d16(An)/PC-rel.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x12;ram[2]=0x34;ram[3]=0x56;ram[4]=0x78
    -- CMP.L (A1)+,D0  ea=$19. opmode L,ea->Dn = $80. $B000|(0<<9)|$80|$19=$B099
    tests[#tests + 1] = {
        name     = "CMP.L (A1)+,D0  A1=scratch (D0=0x12345678 vs ram -> Z=1)",
        preload  = concat(preload_dregs({[0]=0x12345678}),
                          preload_an_scratch({[1]=0})),
        ram_init = ram,
        test     = bw(0xB099),
    }
    -- CMP.W -(A1),D0  ea=$21. opmode .W=$40. $B000|0|$40|$21=$B061
    tests[#tests + 1] = {
        name     = "CMP.W -(A1),D0  A1=scratch+2 (D0=0x12345678 vs ram[0..1]=0x1234 -> Z=1)",
        preload  = concat(preload_dregs({[0]=0x12345678}),
                          preload_an_scratch({[1]=2})),
        ram_init = ram,
        test     = bw(0xB061),
    }
    -- CMP.B d16(A6),D0  ea=$2E + word disp. .B opmode=0. $B000|0|0|$2E=$B02E
    tests[#tests + 1] = {
        name     = "CMP.B 3(A6),D0  (D0=0x78 vs ram[3]=0x78 -> Z=1)",
        preload  = preload_dregs({[0]=0x00000078}),
        ram_init = ram,
        test     = concat(bw(0xB02E), bw(0x0003)),
    }
end

-- ---------- BTST/BCHG/BCLR/BSET on (A6)+ and d16(A6) ----------------
-- Dynamic mode (Dn,ea): opword = $0100 | (typ<<6) | (Dn<<9) | <ea>.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1] = 0x80
    -- BTST D1,(A1)+  Dn=D1, typ=00, ea (A1)+ = $19. $0100|0|(1<<9)|$19 = $0319
    tests[#tests + 1] = {
        name     = "BTST D1,(A1)+  A1=scratch, D1=7 -> tests bit 7 of 0x80",
        preload  = concat(preload_dregs({[1]=7}),
                          preload_an_scratch({[1]=0})),
        ram_init = ram,
        test     = bw(0x0319),
    }
    -- BSET D1,d16(A6)  ea = $2E. $0100|(3<<6)|(1<<9)|$2E = $0100|$C0|$200|$2E = $03EE.
    tests[#tests + 1] = {
        name     = "BSET D1,2(A6)  D1=0 -> set bit 0 of ram[2]=0x00",
        preload  = preload_dregs({[1]=0}),
        ram_init = ram,
        test     = concat(bw(0x03EE), bw(0x0002)),
    }
end

-- ---------- Mem-shift ROL/ROR (A6)  (typ=11) ------------------------
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x80; ram[2]=0x01
    -- ROL.W (A6) = $E700|<ea>. (A6) ea=$16 -> opword = $E7D6.
    -- Actually mem-shift opword: $E0C0 | (typ<<9) | (dr<<8) | <ea>
    -- ROL typ=3 dr=1: $E0C0 | $600 | $100 | $16 = $E7D6
    -- ROR typ=3 dr=0: $E0C0 | $600 | 0    | $16 = $E6D6
    tests[#tests + 1] = {
        name     = "ROL.W (A6)  mem-shift single bit (ram=0x8001 -> 0x0003)",
        preload  = {},
        ram_init = ram,
        test     = bw(0xE7D6),
    }
    tests[#tests + 1] = {
        name     = "ROR.W (A6)  mem-shift single bit (ram=0x8001 -> 0xC000)",
        preload  = {},
        ram_init = ram,
        test     = bw(0xE6D6),
    }
end

-- ---------- Bit-field on memory: BFTST/BFEXTU/BFCHG/BFCLR/BFSET (A6) -
-- All bit-field opwords for (A6) are $XXD6 (ea=$16):
--   BFTST $E8D6, BFEXTU $E9D6, BFCHG $EAD6, BFCLR $ECD6, BFSET $EED6
-- ext: dst_dn<<12 | offset_dyn<<11 | offset<<6 | width_dyn<<5 | width
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x12;ram[2]=0xFF;ram[3]=0x56;ram[4]=0x78
    tests[#tests + 1] = {
        name     = "BFTST (A6){8:8}  byte ram[1]=0xFF -> N=1,Z=0",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0xE8D6), bw(0x0208)),  -- off=8,w=8
    }
    tests[#tests + 1] = {
        name     = "BFEXTU (A6){8:8},D1  -> D1=0xFF",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0xE9D6), bw(0x1208)),  -- dst=D1, off=8, w=8
    }
    tests[#tests + 1] = {
        name     = "BFCHG (A6){8:8}  ram[1]=0xFF -> 0x00",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0xEAD6), bw(0x0208)),
    }
    tests[#tests + 1] = {
        name     = "BFCLR (A6){8:8}  ram[1]=0xFF -> 0x00",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0xECD6), bw(0x0208)),
    }
    tests[#tests + 1] = {
        name     = "BFSET (A6){0:8}  ram[0]=0x12 -> 0xFF",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0xEED6), bw(0x0008)),
    }
end

-- ---------- 020 PC memory-indirect addressing -----------------------
-- mode=7,reg=3 with full ext PC-rel + memory-indirect.
-- Layout: opword + full-ext + bd word + BRA.B + pointer-bytes + data-bytes.
-- We place a pointer in the test bytes (PC-rel reachable) that points
-- into scratch RAM, then have memory-indirect read 4 bytes from there.

-- ([bd.W,PC],od.W)  IIS=110 with IS=1 (no index), W od
-- Full ext: D/A=0,reg=0,W/L=0,scale=0,full=1,BS=0,IS=1,BDSIZE=10,IIS=110
-- = 0_000_0_00_1_0_1_10_0_110 = 0x0166
-- bd points to the longword in test bytes; longword in test bytes is the
-- pointer; od=0 means EA = MEM[(PC of ext)+bd].
-- Layout:
--   $00..1: $22 $3B  opword
--   $02..3: $01 $66  full ext (PC base, no idx, word od, postindexed)
--   $04..5: bd.W = +6                (target = ($1006)+6 = $100C)
--   $06..7: od.W = 0
--   $08..9: BRA.B disp=$06           (PC after = test_pc+$0A; +6 -> test_pc+$10)
--   $0A..D: pointer.L = $00001810    (read at $100C..$100F)
--   $0E..F: padding (must be NOPed or unreachable; BRA jumps past)
-- Actually we need exactly 16 bytes to hit dump at test_pc+$10. Layout:
--   $00..7: opword + full-ext + bd + od  (8 bytes)
--   $08..9: BRA.B (2 bytes)
--   $0A..D: pointer (4 bytes)
-- = 14 bytes -> dump at $1004+$0E = $1012. BRA from $0A: PC_after=test_pc+$0C; +6 -> test_pc+$12.
-- Want target $100C to hold pointer. So pointer must be at offset $0C.
-- Layout (revised, 16 bytes):
--   $00..1: $22 $3B
--   $02..3: $01 $66
--   $04..5: bd.W = $08  -> target = ($1006)+$08 = $100E
--   $06..7: od.W = 0
--   $08..9: BRA.B disp=$06  -> after-branch $100C; +6 -> $1012 = dump
--   $0A..D: 4 bytes padding (unreached due to BRA)
--   $0E..11: pointer $00001810 (read at $100E)
-- = 18 bytes
-- Hmm getting complex; skip PC memory-indirect for now -- not high-yield.

-- ---------- Bcc.L (32-bit displacement, 020+) -----------------------
-- Encoding: $6Xff + disp32. The 8-bit displacement field = $FF signals
-- a 32-bit longword displacement follows. PC at the disp word = test_pc+2.
-- Layout (16 bytes, dump at test_pc+$10):
--   $00..1: $6XFF (Bcc.L opword)
--   $02..5: disp32 (target = test_pc + $0C for taken)
--   $06..9: MOVE.B #1,(A6)  (4 bytes; not-taken path)
--   $0A..B: BRA.B disp=$04   (PC after = test_pc+$0C; +4 -> test_pc+$10 = dump)
--   $0C..F: MOVE.B #2,(A6)   (4 bytes; taken path)
local function bcc_l_test(name, cc, ccr_in)
    return {
        name    = name,
        preload = preload_ccr(ccr_in),
        test    = concat(
            bw(0x60FF | (cc << 8)), bl(0x0000000A),
            emit_mb_to_a6(1),
            emit_bra_b(0x04),
            emit_mb_to_a6(2)
        ),
    }
end
for _, cs in ipairs({
    {n="BEQ", cc=0x7, ccr=0x04, suffix="taken (Z=1)"},
    {n="BNE", cc=0x6, ccr=0x04, suffix="not-taken (Z=1)"},
    {n="BCS", cc=0x5, ccr=0x01, suffix="taken (C=1)"},
    {n="BVS", cc=0x9, ccr=0x02, suffix="taken (V=1)"},
}) do
    tests[#tests + 1] = bcc_l_test(string.format("%s.L  %s", cs.n, cs.suffix),
                                    cs.cc, cs.ccr)
end

-- ---------- BRA.L (always-branch long) ------------------------------
-- $60FF + disp32. Same layout, no condition.
tests[#tests + 1] = {
    name    = "BRA.L  always-skip",
    preload = {},
    test    = concat(
        bw(0x60FF), bl(0x0000000A),
        emit_mb_to_a6(1),
        emit_bra_b(0x04),
        emit_mb_to_a6(2)
    ),
}

-- ---------- BSR.L / RTS round-trip ----------------------------------
-- Layout (18 bytes, dump at test_pc+$12):
--   $00..1: BRA.B disp=$06          (skip subroutine; PC_after=$1006,+6=$100C)
--   $02..5: MOVE.B #2,(A6)           (subroutine body)
--   $06..7: RTS = $4E75
--   $08..9: $61FF (BSR.L opword)
--   $0A..D: disp32 = $FFFFFFF4 (back to $02; PC_at_disp=$100A,+disp=$1002)
--                   disp = $1002 - $100A = -8 = $FFFFFFF8.
--   $0E..11: MOVE.B #1,(A6)
-- Total = 18 bytes -> dump = test_pc+$12 = $1016.
-- Hmm earlier counted wrong. Let me re-check:
--   $00..1 BRA.B (2) -> 2
--   $02..5 MOVE.B #2 (4) -> 6
--   $06..7 RTS (2) -> 8
--   $08..9 BSR.L op (2) -> 10
--   $0A..D disp32 (4) -> 14
--   $0E..11 MOVE.B #1 (4) -> 18. dump = test_pc+$12.
-- BRA.B at $00: PC_after = $1006. disp = +6 -> $100C... but $100C lands at MOVE.B #1 not RTS.
-- Hmm. Subroutine body needs to be reachable from the BSR.L but not in the BRA.B fall-through path.
-- Easier: skip past subroutine to BSR site.
-- Restructure:
--   $00..1: BRA.B disp=$06  skip subroutine, target=$00+2+6=$08
--   $02..5: MOVE.B #2,(A6)  sub body
--   $06..7: RTS
--   $08..9: $61FF  BSR.L
--   $0A..D: disp32 = -8 (PC_at_disp=$0A, +(-8)=$02)
--   $0E..11: MOVE.B #1,(A6)
-- Test PC is relative; harness adds $1004. Disp is to be added to PC.
-- All offsets above are offsets from test start (= test_pc=$1004).
-- For BRA.B disp=+6 at offset $00: PC_after_fetch=test_pc+2; +6 = test_pc+8. ✓ (BSR.L)
-- For BSR.L: pushes return = test_pc+$0E (next instr after BSR.L+disp32).
--   Disp32 added to PC_at_disp = test_pc+$0A. Target = test_pc+$0A + disp32.
--   We want target = test_pc+$02 (sub body). disp32 = -8 = $FFFFFFF8.
-- RTS returns to test_pc+$0E. Then MOVE.B #1 runs.
-- Total test_len = 18. dump = test_pc+$12. After MOVE.B #1 at test_pc+$0E..$11, PC = test_pc+$12 = dump. ✓
tests[#tests + 1] = {
    name    = "BSR.L / RTS  round-trip",
    preload = {},
    test    = concat(
        emit_bra_b(0x06),              -- $00..1  BRA.B disp=+6
        emit_mb_to_a6(2),              -- $02..5  sub body
        bw(0x4E75),                    -- $06..7  RTS
        bw(0x61FF), bl(0xFFFFFFF8),    -- $08..D  BSR.L disp=-8
        emit_mb_to_a6(1)               -- $0E..11 after-return
    ),
}

-- ---------- DBcc remaining conditions (immediate-exit case) ---------
-- All 13 untested DBcc conditions tested with CCR set such that cc=True
-- so DBcc never decrements D1, exits immediately. Body is ADDQ.B #1,(A6),
-- so it runs once before DBcc; scratch[0]=1, D1 unchanged (=3).
-- Encoding: $50C9 | (cc<<8). D1 is the counter reg.
for _, c in ipairs({
    {n="DBT",  cc=0x0, ccr=0x00},
    {n="DBHI", cc=0x2, ccr=0x00},
    {n="DBLS", cc=0x3, ccr=0x04},
    {n="DBCC", cc=0x4, ccr=0x00},
    {n="DBCS", cc=0x5, ccr=0x01},
    {n="DBVC", cc=0x8, ccr=0x00},
    {n="DBVS", cc=0x9, ccr=0x02},
    {n="DBPL", cc=0xA, ccr=0x00},
    {n="DBMI", cc=0xB, ccr=0x08},
    {n="DBGE", cc=0xC, ccr=0x00},
    {n="DBLT", cc=0xD, ccr=0x08},
    {n="DBGT", cc=0xE, ccr=0x00},
    {n="DBLE", cc=0xF, ccr=0x04},
}) do
    tests[#tests + 1] = {
        name = string.format("%s D1,loop  cc=True (immediate exit, D1=3)", c.n),
        preload = concat(preload_dregs({[1]=3}), preload_ccr(c.ccr)),
        test    = concat(bw(0x5216),
                         bw(0x50C9 | (c.cc << 8)), bw(0xFFFC)),
    }
end

-- ---------- JMP/JSR additional EAs ----------------------------------
-- Note: JMP (An) and JSR (An) can't be tested portably here -- they need
-- A0 preloaded with a runtime PC, and that PC differs between MAME and
-- TG68K (MAME harness prepends preload + init-dump, shifting test bytes).
-- After the JMP/JSR, A0 still holds the platform-specific PC, which the
-- bench compares and flags as a diff. JMP/JSR via (d16,PC) is already
-- covered in v3 -- skipping (An) and (xxx).{W,L} JMP/JSR forms.

-- ---------- RTR (Return-and-Restore CCR) ----------------------------
-- $4E77. Pops CCR word THEN PC long from stack (per PRM 4-160).
-- So push PC long FIRST (lower on stack), then CCR word on top.
-- PEA (d16,PC) pushes address_of_disp_word + disp.
-- Layout (10 bytes):
--   $00..1: PEA opword            $487A
--   $02..3: disp word             $0008  (address_of_disp=test+$02; +8 = test+$0A)
--   $04..7: MOVE.W #$0007,-(A7)   $3F3C $0007   CCR word on top
--   $08..9: RTR                    $4E77
-- dump = test_pc+$0A. After RTR: CCR=$07, PC=test+$0A = dump. ✓
tests[#tests + 1] = {
    name    = "RTR  pop CCR=$07 + PC=(d16,PC) from stack",
    preload = {},
    test    = concat(
        bw(0x487A), bw(0x0008),
        bw(0x3F3C), bw(0x0007),
        bw(0x4E77)
    ),
}

-- ---------- RTD #disp (010+) ----------------------------------------
-- $4E74 + word disp. After RTS-like pop, adds disp to SP.
-- Layout: BSR.W to sub, sub does RTD #0 (net same as RTS).
--   $00..1: BRA.B disp=$06  -> target $08 (after RTD)
--   $02..5: MOVE.B #2,(A6)  sub body
--   $06..7: RTS  -- wait we use RTD
--   $06..9: RTD #0          ($4E74 $0000)
--   $0A..B: BSR.W disp=$FFF8 (target = test_pc+$06? Actually $0C+disp; we want $02)
-- Hmm structure messed up; reconstruct.
-- Layout (16 bytes):
--   $00..1: BRA.B disp=$08  skip sub, target=$0A (BSR)
--   $02..5: MOVE.B #2,(A6)  sub body
--   $06..9: RTD #0          (4 bytes)
--   $0A..D: BSR.W disp=$FFF6 (target=test_pc+$02, sub body)
--          PC_at_disp = test_pc+$0C; +(-$0A)=test_pc+$02. disp=$FFF6.
--   $0E..F: pad/end
-- Total = 14 -> dump = test_pc+$0E = $1012.
-- BSR.W disp from PC_at_disp = test_pc+$0C. Target $02 -> disp = $02-$0C = -$0A = $FFF6.
tests[#tests + 1] = {
    name    = "BSR.W / RTD #0  round-trip",
    preload = {},
    test    = concat(
        emit_bra_b(0x08),            -- $00..1
        emit_mb_to_a6(2),            -- $02..5
        bw(0x4E74), bw(0x0000),      -- $06..9  RTD #0
        bw(0x6100), bw(0xFFF6)       -- $0A..D  BSR.W disp=-10
    ),
}
-- RTD #4: net SP rises by 4 vs RTS. A7 excluded from diff so visible
-- only via SP relative effects. Same shape.
tests[#tests + 1] = {
    name    = "BSR.W / RTD #4  (A7 net +4 vs RTS; A7 excluded from diff)",
    preload = {},
    test    = concat(
        emit_bra_b(0x08),
        emit_mb_to_a6(2),
        bw(0x4E74), bw(0x0004),
        bw(0x6100), bw(0xFFF6)
    ),
}

-- ---------- PEA <ea> ------------------------------------------------
-- $4840 | <ea>. Pushes effective address as long onto stack.
-- Plant PEA then pop via MOVE.L (A7)+,D0 to verify.
-- PEA (A6): $4856. Pushes $1800 (= SCRATCH_BASE).
-- Then MOVE.L (A7)+,D0 = $201F. D0 should become $00001800.
tests[#tests + 1] = {
    name    = "PEA (A6) ; MOVE.L (A7)+,D0  (D0 should = $00001800)",
    preload = preload_dregs({[0] = 0xDEADBEEF}),
    test    = concat(bw(0x4856), bw(0x201F)),
}
-- PEA d16(A6): $486E + disp16.
tests[#tests + 1] = {
    name    = "PEA 16(A6) ; MOVE.L (A7)+,D0  (D0 should = $00001810)",
    preload = preload_dregs({[0] = 0xDEADBEEF}),
    test    = concat(bw(0x486E), bw(0x0010), bw(0x201F)),
}

-- ---------- LINK.L An,#disp32 (020+) --------------------------------
-- $4808 | An. Same semantics as LINK.W but with 32-bit displacement.
-- Test as net no-op with UNLK.
tests[#tests + 1] = {
    name    = "LINK.L A0,#-32 / UNLK A0  (net no-op, 020+)",
    preload = preload_an_scratch({[0] = 0x20}),
    test    = concat(
        bw(0x4808), bl(0xFFFFFFE0),     -- LINK.L A0,#-32
        bw(0x4E58)                       -- UNLK A0
    ),
}

-- ---------- CHK2 out-of-bounds (traps to vec 6 / $18) ---------------
-- Same encoding as CHK2 in-range but with D0 outside [low,high].
do
    local r = {}
    for i = 1, SCRATCH_LEN do r[i] = 0 end
    r[1]=0x00; r[2]=0x10; r[3]=0x00; r[4]=0x30
    tests[#tests + 1] = {
        name     = "EXC: CHK2.W (A6),D0  out-of-range (D0=0x100, vec 6 / $18)",
        preload  = preload_dregs({[0] = 0x00000100}),
        ram_init = r,
        test     = concat(bw(0x02D6), bw(0x0800)),
        raises_exception = true,
        ccr_mask = 0xF7,    -- PRM 4-58: CHK2/CMP2 N undefined
    }
end

-- ---------- MOVEM with (A0)+ writing to memory ----------------------
-- MOVEM.L D0-D3,(A1)+  -- wait, postinc isn't valid for MOVEM regs->mem
-- (only predec is). MOVEM mem->regs uses postinc (already tested in v5).
-- Skip: 68k doesn't allow this combo.

-- ---------- ABCD/SBCD register form recap (Dn,Dn already done) ------
-- Add more samples to exercise carry / X-flag chains.
tests[#tests + 1] = {
    name    = "ABCD D1,D0  D1=$99 D0=$01 -> $00 with C=1",
    preload = preload_dregs({[0]=0x00000001, [1]=0x00000099}),
    test    = bw(0xC101),    -- ABCD D1,D0 = $C100|(0<<9)|1
}
tests[#tests + 1] = {
    name    = "SBCD D1,D0  D1=$05 D0=$10 -> $05",
    preload = preload_dregs({[0]=0x00000010, [1]=0x00000005}),
    test    = bw(0x8101),
}
-- NBCD on memory
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1] = 0x42
    tests[#tests + 1] = {
        name     = "NBCD (A6)  ram[0]=$42 -> $58 (10-complement BCD)",
        preload  = {},
        ram_init = ram,
        test     = bw(0x4816),    -- NBCD <ea> = $4800|<ea>; (A6) ea=$16
        ccr_mask = 0xF5,           -- PRM 4-122: NBCD N+V undefined
    }
end

-- ---------- More MOVE coverage --------------------------------------
-- MOVE.L (xxx).L,Dn -- absolute long source.
-- $2039 + 4-byte addr. Place data at scratch+0x20 = $1820 and read it.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[0x21]=0xCA; ram[0x22]=0xFE; ram[0x23]=0xF0; ram[0x24]=0x0D
    tests[#tests + 1] = {
        name     = "MOVE.L (xxx).L=$1820,D1  abs-long read",
        preload  = {},
        ram_init = ram,
        test     = concat(bw(0x2039), bl(0x00001820)),
    }
end
-- MOVE.L Dn,(xxx).L -- abs-long dest.
tests[#tests + 1] = {
    name    = "MOVE.L D0,(xxx).L=$1820  abs-long write (D0=0x12345678)",
    preload = preload_dregs({[0] = 0x12345678}),
    test    = concat(bw(0x23C0), bl(0x00001820)),
}
-- MOVE.W Dn,(xxx).W abs-short write.
tests[#tests + 1] = {
    name    = "MOVE.W D0,(xxx).W=$1820  abs-short write (D0=0x12345678 -> word $5678)",
    preload = preload_dregs({[0] = 0x12345678}),
    test    = concat(bw(0x31C0), bw(0x1820)),
}

-- ---------- MOVE from CCR / to CCR with memory ----------------------
-- MOVE from CCR <ea>: $42C0 | <ea>. (A6) = $42D6. Writes word (high byte 0, low byte CCR).
tests[#tests + 1] = {
    name    = "MOVE from CCR,(A6)  (CCR=0x0F -> ram[0..1] = 0x000F)",
    preload = preload_ccr(0x0F),
    test    = bw(0x42D6),
}
-- MOVE to CCR <ea>: $44C0 | <ea>. (A6) ea=$16 -> $44D6. Reads word; low byte to CCR.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x00; ram[2]=0x1F    -- word $001F -> CCR = $1F
    tests[#tests + 1] = {
        name     = "MOVE (A6),CCR  reads word 0x001F -> CCR=0x1F",
        preload  = {},
        ram_init = ram,
        test     = bw(0x44D6),
    }
end

-- ---------- TST with memory EA --------------------------------------
-- TST.B (A6) = $4A16.  TST.W (A6) = $4A56.  TST.L (A6) = $4A96.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x80;ram[2]=0x00;ram[3]=0x00;ram[4]=0x01
    tests[#tests + 1] = {
        name     = "TST.B (A6)  ram[0]=0x80 -> N=1,Z=0",
        preload  = {}, ram_init = ram,
        test     = bw(0x4A16),
    }
    tests[#tests + 1] = {
        name     = "TST.W (A6)  ram[0..1]=0x8000 -> N=1,Z=0",
        preload  = {}, ram_init = ram,
        test     = bw(0x4A56),
    }
    tests[#tests + 1] = {
        name     = "TST.L (A6)  ram[0..3]=0x80000001 -> N=1,Z=0",
        preload  = {}, ram_init = ram,
        test     = bw(0x4A96),
    }
end

-- ---------- CLR with memory EA --------------------------------------
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x11;ram[2]=0x22;ram[3]=0x33;ram[4]=0x44
    tests[#tests + 1] = {
        name     = "CLR.B (A6)  ram[0]=0x11 -> 0x00",
        preload  = {}, ram_init = ram,
        test     = bw(0x4216),
    }
    tests[#tests + 1] = {
        name     = "CLR.W (A6)  ram[0..1]=0x1122 -> 0x0000",
        preload  = {}, ram_init = ram,
        test     = bw(0x4256),
    }
    tests[#tests + 1] = {
        name     = "CLR.L (A6)  ram[0..3]=0x11223344 -> 0x00000000",
        preload  = {}, ram_init = ram,
        test     = bw(0x4296),
    }
end

-- ---------- NEG / NOT with memory EA --------------------------------
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x12;ram[2]=0x34;ram[3]=0x56;ram[4]=0x78
    tests[#tests + 1] = {
        name     = "NEG.L (A6)  ram[0..3]=0x12345678 -> 0xEDCBA988",
        preload  = {}, ram_init = ram,
        test     = bw(0x4496),    -- NEG.L <ea> = $4480|<ea>; (A6) -> $4496
    }
    tests[#tests + 1] = {
        name     = "NOT.W (A6)  ram[0..1]=0x1234 -> 0xEDCB",
        preload  = {}, ram_init = ram,
        test     = bw(0x4656),    -- NOT.W <ea> = $4640|<ea>; (A6) -> $4656
    }
end

-- ---------- NEGX with memory EA -------------------------------------
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x00;ram[2]=0x00;ram[3]=0x00;ram[4]=0x05
    tests[#tests + 1] = {
        name     = "NEGX.L (A6)  ram=5, X=1 -> 0xFFFFFFFA",
        preload  = preload_ccr(0x10),
        ram_init = ram,
        test     = bw(0x4096),    -- NEGX.L = $4080|<ea>
    }
end

-- ---------- TAS additional cases (memory predec/postinc) ------------
-- TAS doesn't support predec/postinc (byte-only, data-alterable -An/(An)+ OK)
-- Actually TAS supports any data-alterable EA. Add (A1)+.
do
    local ram = {}
    for i = 1, SCRATCH_LEN do ram[i] = 0 end
    ram[1]=0x00; ram[2]=0x40
    tests[#tests + 1] = {
        name     = "TAS (A1)+  A1=scratch+1 ram[1]=0x40 -> 0xC0, A1+=1",
        preload  = preload_an_scratch({[1] = 1}),
        ram_init = ram,
        test     = bw(0x4AD9),    -- TAS (A1)+ = $4AC0|0x19
    }
end

-- ======================================================================
-- EXCEPTION TESTS
--
-- These tests deliberately trigger exceptions. The MAME harness vector
-- table (VEC_BASE..VEC_BASE+VEC_COUNT*4) already points every vector at
-- the final-dump entry, so any exception lands in our state-capture
-- code. TG68K's bench replicates the same vector setup. Mac OS catches
-- exceptions and kills the app, so these are marked raises_exception=1
-- and the Mac bench skips them.
--
-- Per PRM Table B-1 (verified against the manual):
--   Vec 2 / $08  Access Fault (bus error)   -- needs /BERR; deferred
--   Vec 3 / $0C  Address Error              -- triggered by odd PC fetch
--   Vec 4 / $10  Illegal Instruction        -- $4AFC
--   Vec 5 / $14  Integer Divide by Zero
--   Vec 6 / $18  CHK / CHK2 (shared)
--   Vec 7 / $1C  TRAPcc / TRAPV / FTRAPcc (shared)
--   Vec 8 / $20  Privilege Violation        -- needs user-mode harness; deferred
--   Vec 9 / $24  Trace                      -- needs T-bit harness; deferred
--   Vec 10/ $28  Line A (1010 emulator)
--   Vec 11/ $2C  Line F (1111 emulator)     -- on MAME w/ FPU, dispatches to FPU
--   Vec 32-47   TRAP #0 .. TRAP #15
--
-- After the exception fires, A7 has been decremented by the stack-frame
-- size (4 or 6 words on 68020). The diff tool excludes A7 from
-- comparison so this is fine. SR's S bit is set; we capture only CCR
-- (low byte), so unaffected.
-- ======================================================================

-- ILLEGAL ($4AFC) -- vector 4 / $10
tests[#tests + 1] = {
    name    = "EXC: ILLEGAL  ($4AFC -> vec 4 / $10)",
    preload = {},
    test    = bw(0x4AFC),
    raises_exception = true,
}

-- Integer Divide by Zero -- vector 5 / $14
-- DIVU.W #0,D0 = $80FC + immediate word $0000
tests[#tests + 1] = {
    name    = "EXC: DIVU.W #0,D0  (vec 5 / $14)",
    preload = preload_dregs({[0] = 0x00000100}),
    test    = concat(bw(0x80FC), bw(0x0000)),
    raises_exception = true,
}
-- DIVS.W #0,D0 = $81FC + immediate word $0000
tests[#tests + 1] = {
    name    = "EXC: DIVS.W #0,D0  (vec 5 / $14)",
    preload = preload_dregs({[0] = 0x00000100}),
    test    = concat(bw(0x81FC), bw(0x0000)),
    raises_exception = true,
}

-- CHK.W Dn,Dm out-of-bounds -- vector 6 / $18
-- CHK.W Dy,Dx = $4180 | (Dx<<9) | Dy. For CHK D1,D0: $4180 | 1 = $4181.
-- D0 holds the value to check; D1 holds the upper bound (signed word).
-- Out-of-bound above:
tests[#tests + 1] = {
    name    = "EXC: CHK.W D1,D0  (D0=100 > D1=10, vec 6 / $18)",
    preload = preload_dregs({[0] = 100, [1] = 10}),
    test    = bw(0x4181),
    raises_exception = true,
}
-- Out-of-bound below (D0 negative):
tests[#tests + 1] = {
    name    = "EXC: CHK.W D1,D0  (D0=-1 < 0, vec 6 / $18)",
    preload = preload_dregs({[0] = 0xFFFFFFFF, [1] = 100}),
    test    = bw(0x4181),
    raises_exception = true,
}

-- TRAPV with V flag set -- vector 7 / $1C
-- TRAPV = $4E76. V=1 must be in CCR at TRAPV time; we can't use the
-- preload, because the init-dump epilogue runs *between* preload and
-- the test instruction and overwrites CCR (its last MOVE.L 0,0 sets
-- Z=1, wiping any V we put in the preload). Emit MOVE #2,CCR inside
-- the test bytes so V=1 is set immediately before TRAPV.
tests[#tests + 1] = {
    name    = "EXC: MOVE #2,CCR ; TRAPV  (V=1, vec 7 / $1C)",
    preload = {},
    test    = concat(bw(0x44FC), bw(0x0002), bw(0x4E76)),
    raises_exception = true,
}

-- TRAP #N -- vectors 32-47 / $80-$BC. TRAP #N = $4E40 | N.
for _, n in ipairs({0, 7, 15}) do
    tests[#tests + 1] = {
        name    = string.format("EXC: TRAP #%d  (vec %d / $%X)", n, 32 + n, 0x80 + n * 4),
        preload = {},
        test    = bw(0x4E40 | n),
        raises_exception = true,
    }
end

-- Address Error via odd PC fetch -- vector 3 / $0C
-- Preload A0 = scratch+1 (odd address), then JMP (A0). The JMP itself
-- executes fine; the *next* instruction prefetch from $1801 fails with
-- an address error (per UM §6.1.3).
tests[#tests + 1] = {
    name    = "EXC: JMP (A0) where A0=$1801 (odd, vec 3 / $0C)",
    preload = preload_an_scratch({[0] = 1}),     -- LEA $1(A6),A0 -> A0=scratch+1
    test    = bw(0x4ED0),                         -- JMP (A0)
    raises_exception = true,
}

-- Line A trap ($A000) -- vector 10 / $28
-- Any $AXXX opcode is unimplemented and traps to the Line A emulator
-- vector (per PRM Table B-1, vector 10). Mac OS uses $AXXX for toolbox
-- traps; this just exercises the dispatch path.
tests[#tests + 1] = {
    name    = "EXC: Line A trap ($A000, vec 10 / $28)",
    preload = {},
    test    = bw(0xA000),
    raises_exception = true,
}

-- Line F trap: deferred. On MAME's maciihmu, the FPU is present and
-- claims all F-line opcodes regardless of cpid. We verified $F800
-- (cpid=4) doesn't trap on MAME -- A7 unchanged after the test. On
-- TG68K (no FPU dispatch yet), all F-lines do trap. To exercise this
-- divergence cleanly we'd need a Line-F-only oracle separate from the
-- FPU-present MAME path; that's CPU+FPU integration scope (blocked on
-- the CIR Response read bug).

-- ---------- Smoke ------------------------------------------------------
tests[#tests + 1] = {
    name    = "DBG: NOP (baseline)",
    preload = {},
    test    = bw(0x4E71),
}

print(string.format("Corpus has %d tests.", #tests))

-- ----------------------------------------------------------------------
-- Emit C header
-- ----------------------------------------------------------------------
local function emit_tests_h(path)
    local f = io.open(path, "w")
    if f == nil then print("WARN: cannot write " .. path); return end
    f:write("/* Auto-generated by SingleStepTests/gen/mame_cpu_capture.lua.\n")
    f:write(" * Do not edit by hand -- regenerate by re-running the script. */\n")
    f:write("#ifndef CPU_TESTS_H\n#define CPU_TESTS_H\n\n")
    local max_pre, max_tst = 0, 0
    for _, t in ipairs(tests) do
        if #t.preload > max_pre then max_pre = #t.preload end
        if #t.test    > max_tst then max_tst = #t.test    end
    end
    -- No artificial floor: each per-entry byte wastes 216x on the Mac side.
    -- THINK C splits hairs over the 32KB-per-segment data limit, so we
    -- track the actual widest preload/test bytes observed.
    local pre_cap = max_pre
    local tst_cap = max_tst
    f:write(string.format("#define CPU_TEST_MAX_PRELOAD %d  /* widest: %d */\n",
        pre_cap, max_pre))
    f:write(string.format("#define CPU_TEST_MAX_TEST    %d  /* widest: %d */\n",
        tst_cap, max_tst))
    f:write(string.format("#define CPU_SCRATCH_LEN      %d\n", SCRATCH_LEN))
    f:write("\n")
    f:write("typedef struct {\n")
    f:write("    const char *name;\n")
    f:write("    unsigned char preload[CPU_TEST_MAX_PRELOAD];\n")
    f:write("    unsigned short preload_len;\n")
    f:write("    unsigned char test[CPU_TEST_MAX_TEST];\n")
    f:write("    unsigned short test_len;\n")
    f:write("    unsigned char ram_init[CPU_SCRATCH_LEN];\n")
    f:write("    unsigned char ram_init_present;  /* 0 or 1 */\n")
    f:write("    unsigned char privileged;        /* 0 or 1 -- Mac bench skips */\n")
    f:write("    unsigned char raises_exception;  /* 0 or 1 -- Mac bench skips; TG68K + MAME run\n")
    f:write("                                      * (vector table is set up to land at the dump). */\n")
    f:write("    unsigned char ccr_mask;          /* bits to compare in CCR; 0xFF = compare all.\n")
    f:write("                                      * Clear a bit (e.g. 0xF7 = ignore N) when the PRM\n")
    f:write("                                      * declares that flag undefined for this op. */\n")
    f:write("} CpuTestSpec;\n\n")
    -- Note: NOT `static const`. THINK C places const arrays in the CODE
    -- resource, which has a hard 32KB-per-segment ceiling. Plain `static`
    -- lives in the data segment, which can be extended to 32-bit via
    -- THINK C Project Type -> Memory -> 32-bit globals.
    f:write("static CpuTestSpec g_cpu_tests[] = {\n")
    local function bytes_str(t)
        if not t or #t == 0 then return "{0}" end
        local parts = {}
        for _, b in ipairs(t) do parts[#parts + 1] = string.format("0x%02X", b) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    for _, t in ipairs(tests) do
        local pre_str = bytes_str(t.preload)
        local tst_str = bytes_str(t.test)
        local ram_str, ram_n
        if t.ram_init then
            local parts = {}
            for _, b in ipairs(t.ram_init) do parts[#parts + 1] = string.format("0x%02X", b) end
            ram_str = "{" .. table.concat(parts, ",") .. "}"; ram_n = 1
        else
            ram_str = "{0}"; ram_n = 0
        end
        local priv = t.privileged and 1 or 0
        local exc  = t.raises_exception and 1 or 0
        local mask = t.ccr_mask or 0xFF
        f:write(string.format("    {%q,\n", t.name))
        f:write(string.format("      %s, %d,\n", pre_str, #t.preload))
        f:write(string.format("      %s, %d,\n", tst_str, #t.test))
        f:write(string.format("      %s, %d, %d, %d, 0x%02X},\n",
            ram_str, ram_n, priv, exc, mask))
    end
    f:write("};\n\n")
    f:write("#define CPU_N_TESTS "
        .. "((unsigned short)(sizeof(g_cpu_tests)/sizeof(g_cpu_tests[0])))\n\n")
    f:write("#endif /* CPU_TESTS_H */\n")
    f:close()
    print(string.format("Wrote C header (%d tests) to %s", #tests, path))
end

emit_tests_h(TESTS_H_PATH)

-- ----------------------------------------------------------------------
-- JSON Lines emission
-- ----------------------------------------------------------------------
local function snap_to_string(s)
    local buf = { "{\"d\":[" }
    for i = 0, 7 do
        buf[#buf + 1] = (i == 0 and "" or ",") .. tostring(s.d[i])
    end
    buf[#buf + 1] = "],\"a\":["
    for i = 0, 7 do
        buf[#buf + 1] = (i == 0 and "" or ",") .. tostring(s.a[i])
    end
    buf[#buf + 1] = "],\"ccr\":" .. tostring(s.ccr & 0xFF)
    buf[#buf + 1] = ",\"ram\":["
    for i = 1, #s.ram do
        buf[#buf + 1] = (i == 1 and "" or ",") .. tostring(s.ram[i])
    end
    buf[#buf + 1] = "]}"
    return table.concat(buf)
end

local function emit_entry(file, name, initial, final)
    file:write(string.format("{\"name\":%q,\"initial\":%s,\"final\":%s}\n",
        name, snap_to_string(initial), snap_to_string(final)))
    file:flush()
end

-- ----------------------------------------------------------------------
-- Frame-driven state machine
-- ----------------------------------------------------------------------
local RAM_PROBE_VALUE = 0xDEADBEEF
local MAX_WAIT_FRAMES = 1800
local MAX_RUN_FRAMES  = 120

local phase    = "WAIT_RAM"
local frames   = 0
local test_i   = 1
local stop_pc  = 0
local out_file = nil
local n_written = 0

local function start_test(t)
    for i = 0, SNAP_BYTES - 1 do
        prog:write_u8(INIT_DUMP  + i, 0xCD)
        prog:write_u8(FINAL_DUMP + i, 0xCD)
    end
    for i = 0, SCRATCH_LEN - 1 do
        local b = 0
        if t.ram_init then b = t.ram_init[i + 1] or 0 end
        prog:write_u8(SCRATCH_BASE + i, b)
    end

    local out = {}
    local function append(bs)
        for _, b in ipairs(bs) do out[#out + 1] = b end
    end
    -- 1) Load A6 = SCRATCH_BASE (harness, not per-test).
    append(emit_movea_l_imm_to_an(6, SCRATCH_BASE))
    -- 2) Zero CCR so each test starts clean.
    append(emit_move_w_imm_to_ccr(0))
    -- 3) Per-test preload (D regs, optional A regs via LEA-from-A6, CCR overrides).
    append(t.preload)
    append(emit_state_dump(INIT_DUMP, true))
    local final_dump_off = #out + #t.test
    append(t.test)
    append(emit_state_dump(FINAL_DUMP, false))
    local jmp_pc = PROG_BASE + #out
    append(concat(bw(0x4EF9), bl(jmp_pc)))   -- JMP self
    stop_pc = jmp_pc
    local final_dump_pc = PROG_BASE + final_dump_off

    write_bytes(PROG_BASE, out)

    for v = 0, VEC_COUNT - 1 do
        prog:write_u32(VEC_BASE + v * 4, final_dump_pc)
    end

    for r = 0, 7 do rset("D" .. r, 0); rset("A" .. r, 0) end
    rset("SR", 0x2700)
    rset("A7", 0x00200000)
    rset("PC", PROG_BASE)
    rset("VBR", VEC_BASE)
    if cpu.state["SFC"]  then rset("SFC", 0) end
    if cpu.state["DFC"]  then rset("DFC", 0) end
    if cpu.state["CACR"] then rset("CACR", 0) end
    frames = 0
end

local function tick()
    init_handles()
    if phase == "WAIT_RAM" then
        prog:write_u32(PROG_BASE, RAM_PROBE_VALUE)
        local rb = prog:read_u32(PROG_BASE)
        frames = frames + 1
        if rb == RAM_PROBE_VALUE then
            print(string.format("RAM mapped at $%08X after %d frames.",
                PROG_BASE, frames))
            out_file = io.open(CPU_OUT_PATH, "w")
            if out_file == nil then
                print("ERROR: cannot open " .. CPU_OUT_PATH)
                phase = "ABORT"; return
            end
            phase = "SETUP_NEXT"; frames = 0
        elseif frames >= MAX_WAIT_FRAMES then
            print(string.format("ERROR: RAM never mapped at $%08X.", PROG_BASE))
            phase = "ABORT"
        end
    elseif phase == "SETUP_NEXT" then
        if test_i > #tests then phase = "DONE"; return end
        local t = tests[test_i]
        print(string.format("[%d/%d] %s", test_i, #tests, t.name))
        emu.pause(); start_test(t); emu.unpause()
        phase = "RUN"
    elseif phase == "RUN" then
        frames = frames + 1
        local pc = rget("PC")
        if pc == stop_pc then
            emu.pause()
            local t = tests[test_i]
            emit_entry(out_file, t.name,
                read_snap(INIT_DUMP), read_snap(FINAL_DUMP))
            n_written = n_written + 1
            test_i = test_i + 1
            phase = "SETUP_NEXT"
        elseif frames >= MAX_RUN_FRAMES then
            print(string.format("  timeout: PC=$%08X expected $%08X SR=$%04X",
                pc, stop_pc, rget("SR")))
            emu.pause(); test_i = test_i + 1; phase = "SETUP_NEXT"
        end
    elseif phase == "DONE" then
        if out_file then out_file:close() end
        print(string.format("Wrote %d tests to %s", n_written, CPU_OUT_PATH))
        phase = "EXITED"; manager.machine:exit()
    elseif phase == "ABORT" then
        if out_file then out_file:close() end
        manager.machine:exit()
    end
end

emu.register_frame_done(tick, "cpu_capture")
print("mame_cpu_capture.lua loaded -- waiting for RAM, will run "
      .. #tests .. " tests then exit.")
