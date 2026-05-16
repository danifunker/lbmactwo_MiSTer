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

-- State dump epilogue. snap_base is platform-specific.
--
-- TWO invariants this routine must preserve:
--   1. Must not clobber any general-purpose register (D0..D7, A0..A7).
--      The init dump runs BEFORE the test, so clobbered values would
--      propagate into the test instruction.
--   2. Must capture CCR BEFORE issuing any flag-setting instruction.
--      `MOVE.L Dn,abs.L` sets N/Z based on the source -- by the time
--      MOVE CCR,(abs.L) runs at the end of the dump, CCR has been
--      overwritten by the last register dumped (D7=0 -> Z=1 -> 0x04).
--
-- Order:
--   1. MOVE CCR,(abs.L) -- first, while CCR still reflects the test
--   2. MOVE.L An,abs.L x 8
--   3. MOVE.L Dn,abs.L x 8
--   4. MOVE.L (abs.L),(abs.L) x 16 -- scratch RAM copy
--
-- All instructions use memory-to-memory or reg-to-memory forms with no
-- temp-register intermediates. `MOVE CCR,(abs.L)` writes a 16-bit word:
-- byte snap+0x40 = 0x00 (zero-extended high), byte snap+0x41 = CCR.
local function emit_state_dump(snap_base)
    local out = {}
    local function append(t)
        for _, b in ipairs(t) do out[#out + 1] = b end
    end
    -- CCR first (before subsequent MOVEs corrupt it).
    append(concat(bw(0x42F9), bl(snap_base + 0x40)))
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
        tests[#tests + 1] = {
            name = string.format("%s.W D1,D0 (#%d Dn=0x%08X Dm=0x%08X)",
                                 op.name, i, s.dn_v, s.dm_v),
            preload = preload_dregs({[0] = s.dn_v, [1] = s.dm_v}),
            test    = bw(op.op | (0 << 9) | 1),
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
for _, an in ipairs({0, 1, 5, 7}) do
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
    f:write("    unsigned char privileged;        /* 0 or 1 -- bench skips if 1 */\n")
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
        f:write(string.format("    {%q,\n", t.name))
        f:write(string.format("      %s, %d,\n", pre_str, #t.preload))
        f:write(string.format("      %s, %d,\n", tst_str, #t.test))
        f:write(string.format("      %s, %d, %d},\n", ram_str, ram_n, priv))
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
    append(emit_state_dump(INIT_DUMP))
    local final_dump_off = #out + #t.test
    append(t.test)
    append(emit_state_dump(FINAL_DUMP))
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
