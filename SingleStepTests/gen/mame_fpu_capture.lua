-- MAME Lua script: capture FPU instruction state from maciihmu.
--
-- Strategy: rather than trying to single-step and snapshot via Lua
-- (which gets tangled because Lua can't reach into FP0..FP7 directly —
-- only D/A regs and SR/PC are exposed in cpu.state), we build a small
-- assembly program PER TEST that:
--   1. Initializes FPU state with known values (preamble FMOVEs).
--   2. Dumps initial FP0..FP7 + FPCR/FPSR + D/A regs to a known RAM
--      window via FMOVE.X / MOVE.L / etc.
--   3. Executes the target test instruction.
--   4. Dumps final FP0..FP7 + FPCR/FPSR + D/A regs to a second window.
--   5. Hits STOP #$2700 to halt deterministically.
--
-- Then we read the RAM windows back via Lua and emit JSON.
--
-- Why MAME (not Musashi standalone or some other oracle):
--   * Musashi's standalone build doesn't expose FP0..FP7 in its public
--     API; patching would diverge from upstream.
--   * MAME's m68k FPU is the same Musashi implementation but with full
--     state-export hooks AND a real bus model so we get exact
--     architectural behavior (FPSR side effects, exception flags,
--     etc.) matching what software will see on real hardware.
--   * maciihmu is the same target our FPGA core emulates, so any
--     model-specific quirks line up.
--
-- USAGE
-- -----
-- 1. cd ~/repos/mame
-- 2. ./mame64 maciihmu -window -debug \
--      -autoboot_script ~/repos/lbmactwo_MiSTer/SingleStepTests/gen/mame_fpu_capture.lua
-- 3. Let the boot ROM run for a few seconds so RAM at $0..$7FFFFF is
--    writeable (the MMU/HMMU has decoded RAM into the linear address
--    space). Then in the MAME debugger Lua prompt:
--      > capture_run()
-- 4. Output JSON written to FPU_OUT_PATH below.
--
-- The first cut handles cpGEN reg-reg ops. Memory-form ops, conditional
-- branches, cpSAVE/cpRESTORE need similar but distinct test templates;
-- adding them is a copy-paste of write_test_program for each family.

local FPU_OUT_PATH = "/tmp/fpu_corpus.json"

-- Memory layout per test:
--   $1000..$104F: instruction stream (preamble + dump + test + dump + STOP)
--   $1100..$11FF: initial-state dump (8 × 12-byte FPn + FPCR + FPSR + Dn + An)
--   $1200..$12FF: final-state dump
--   $1300..$13FF: scratch (operand source addresses for memory-form tests)
local PROG_BASE   = 0x00001000
local INIT_DUMP   = 0x00001100
local FINAL_DUMP  = 0x00001200
local SCRATCH     = 0x00001300

-- ----------------------------------------------------------------------
-- Tests. Each entry produces ONE corpus entry.
--
-- preload : list of instructions (raw bytes) that set up FP register
--           values before the test. Example: FMOVE.L #1,FP0 then
--           FMOVE.L #2,FP1.
-- test    : the single F-line instruction whose effect we want to
--           capture.
-- ----------------------------------------------------------------------
local tests = {
    {
        name    = "FMOVE.L #1,FP0",
        preload = {},
        -- F200 8000 + 70 01 (MOVEQ #1,D0 first) — actually since we don't
        -- have a clean way to provide an immediate, encode as a sequence:
        -- MOVEQ #1,D0 ; FMOVE.L D0,FP0
        test    = { 0x70, 0x01,            -- MOVEQ #1,D0
                    0xF2, 0x00, 0x80, 0x00 }, -- FMOVE.L D0,FP0
    },
    {
        name    = "FADD.X FP0,FP0 (1+1=2)",
        preload = { 0x70, 0x01, 0xF2, 0x00, 0x80, 0x00 }, -- FP0=1
        test    = { 0xF2, 0x00, 0x00, 0x22 },              -- FADD.X FP0,FP0
    },
    {
        name    = "FMUL.X FP0,FP0 (2*2=4)",
        preload = { 0x70, 0x02, 0xF2, 0x00, 0x80, 0x00 }, -- FP0=2
        test    = { 0xF2, 0x00, 0x00, 0x23 },              -- FMUL.X FP0,FP0
    },
    {
        name    = "FSQRT.X FP0,FP0 (sqrt(4)=2)",
        preload = { 0x70, 0x04, 0xF2, 0x00, 0x80, 0x00 }, -- FP0=4
        test    = { 0xF2, 0x00, 0x00, 0x04 },
    },
    {
        name    = "FNEG.X FP0,FP0 (1 -> -1)",
        preload = { 0x70, 0x01, 0xF2, 0x00, 0x80, 0x00 },
        test    = { 0xF2, 0x00, 0x00, 0x1A },
    },
    {
        name    = "FABS.X FP0,FP0 (-1 -> 1)",
        preload = { 0x70, 0xFF, 0xF2, 0x00, 0x80, 0x00 }, -- D0=-1, FP0=-1
        test    = { 0xF2, 0x00, 0x00, 0x18 },
    },
    {
        name    = "FTST.X FP0 (sets FPSR for 0)",
        preload = { 0x70, 0x00, 0xF2, 0x00, 0x80, 0x00 }, -- FP0=0
        test    = { 0xF2, 0x00, 0x00, 0x3A },
    },
    {
        name    = "FMOVE.X FP0,FP1",
        preload = { 0x70, 0x05, 0xF2, 0x00, 0x80, 0x00 }, -- FP0=5
        test    = { 0xF2, 0x00, 0x00, 0x80 },              -- FMOVE.X FP0,FP1
    },
}

-- ----------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------
local cpu, prog
local function init_handles()
    cpu  = manager.machine.devices[":maincpu"]
    prog = cpu.spaces["program"]
end

local function rget(name) return cpu.state[name].value end
local function rset(name, v) cpu.state[name].value = v end

local function write_bytes(addr, bytes)
    for i, b in ipairs(bytes) do
        prog:write_u8(addr + i - 1, b)
    end
end

local function read_bytes(addr, n)
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = prog:read_u8(addr + i) end
    return out
end

local function hexstr(bytes)
    local out = {}
    for i = 1, #bytes do out[i] = string.format("%02x", bytes[i]) end
    return table.concat(out)
end

-- Build instructions ----------------------------------------------------

-- FMOVE.X FPn,(abs.L)  --  8 bytes
local function emit_fmove_x_to_abs(fpn, abs_addr)
    local opword = 0xF239
    local ext    = 0x7400 | (fpn * 128) -- family=011 fmt=100(X) src=FPn dst=mode111reg001
    return {
        (opword >> 8) & 0xFF, opword & 0xFF,
        (ext    >> 8) & 0xFF, ext    & 0xFF,
        (abs_addr >> 24) & 0xFF, (abs_addr >> 16) & 0xFF,
        (abs_addr >>  8) & 0xFF,  abs_addr        & 0xFF,
    }
end

-- FMOVE FPSR/FPCR/FPIAR,(abs.L)  --  6 bytes (FMOVE.L with ctrl-reg variant)
-- Opword: F239 / ext: 1010_000_FPCR_FPSR_FPIAR_xxxxxxx
-- Simpler: skip FPCR/FPSR dumps for now, only emit FP regs. We can add
-- ctrl-reg dumping once the basic flow is proven.

-- MOVE.L Dn,(abs.L)  --  6 bytes (opcode 23C0 | (n<<0))
local function emit_move_l_dn_to_abs(dn, abs_addr)
    local opword = 0x23C0 | (dn & 7)
    return {
        (opword >> 8) & 0xFF, opword & 0xFF,
        (abs_addr >> 24) & 0xFF, (abs_addr >> 16) & 0xFF,
        (abs_addr >>  8) & 0xFF,  abs_addr        & 0xFF,
    }
end
-- MOVE.L An,(abs.L)  --  6 bytes
local function emit_move_l_an_to_abs(an, abs_addr)
    local opword = 0x23C8 | (an & 7)
    return {
        (opword >> 8) & 0xFF, opword & 0xFF,
        (abs_addr >> 24) & 0xFF, (abs_addr >> 16) & 0xFF,
        (abs_addr >>  8) & 0xFF,  abs_addr        & 0xFF,
    }
end

-- Build a full state-dump block at `addr`. Returns the byte-list.
-- Layout written to RAM[dump_base..dump_base+0xC0]:
--   +0x00..0x5F :  FP0..FP7 (96 bits each = 12 bytes), packed
--   +0x60..0x7F :  D0..D7 (32 bits each)
--   +0x80..0x9F :  A0..A7
-- (FPCR/FPSR omitted; add once flow works.)
local function emit_state_dump(dump_base)
    local out = {}
    local function append(t)
        for _, b in ipairs(t) do out[#out + 1] = b end
    end
    for fpn = 0, 7 do
        append(emit_fmove_x_to_abs(fpn, dump_base + fpn * 12))
    end
    for dn = 0, 7 do
        append(emit_move_l_dn_to_abs(dn, dump_base + 0x60 + dn * 4))
    end
    -- A7 is the stack pointer; reading it is fine but writing it via
    -- MOVE.L An is OK since we're just snapshotting.
    for an = 0, 7 do
        append(emit_move_l_an_to_abs(an, dump_base + 0x80 + an * 4))
    end
    return out
end

-- ----------------------------------------------------------------------
-- Run one test
-- ----------------------------------------------------------------------
local function run_one(t)
    local out = {}
    local function append(bs)
        for _, b in ipairs(bs) do out[#out + 1] = b end
    end

    append(t.preload)
    append(emit_state_dump(INIT_DUMP))
    append(t.test)
    append(emit_state_dump(FINAL_DUMP))
    -- STOP #$2700
    append({ 0x4E, 0x72, 0x27, 0x00 })

    write_bytes(PROG_BASE, out)

    -- Reset register state so we get reproducible "initial" snapshots
    -- (well, after preload runs, but preload is deterministic).
    for r = 0, 7 do rset("D" .. r, 0); rset("A" .. r, 0) end
    rset("SR", 0x2000)
    rset("A7", 0x00200000)  -- some valid stack
    rset("PC", PROG_BASE)

    -- Step until STOP fires (the FPU dumps + test all settle).
    -- Count instructions roughly: preload/2 + 24 (init dump) + 1 + 24 + 1.
    -- Use go-to-PC=PROG_BASE+#out-4 (STOP location):
    local stop_pc = PROG_BASE + #out - 4
    cpu.debug:bpset(stop_pc)
    cpu.debug:go()
    -- After go(), execution is paused at the breakpoint. Clear it.
    cpu.debug:bpclear()

    -- Read state dumps back from RAM.
    local function read_snap(base)
        local snap = { fp = {}, d = {}, a = {} }
        for fpn = 0, 7 do
            snap.fp[fpn] = hexstr(read_bytes(base + fpn * 12, 12))
        end
        for dn = 0, 7 do
            local b = read_bytes(base + 0x60 + dn * 4, 4)
            snap.d[dn] = (b[1] << 24) | (b[2] << 16) | (b[3] << 8) | b[4]
        end
        for an = 0, 7 do
            local b = read_bytes(base + 0x80 + an * 4, 4)
            snap.a[an] = (b[1] << 24) | (b[2] << 16) | (b[3] << 8) | b[4]
        end
        return snap
    end

    return { name = t.name,
             initial = read_snap(INIT_DUMP),
             final   = read_snap(FINAL_DUMP) }
end

-- ----------------------------------------------------------------------
-- JSON emission
-- ----------------------------------------------------------------------
local function emit_snap(file, label, s, trailing_comma)
    file:write(string.format("    \"%s\": {\n", label))
    file:write("      \"d\":[")
    for i = 0, 7 do
        file:write(string.format("%s%d", i == 0 and "" or ",", s.d[i]))
    end
    file:write("],\n      \"a\":[")
    for i = 0, 7 do
        file:write(string.format("%s%d", i == 0 and "" or ",", s.a[i]))
    end
    file:write("],\n      \"fp\":[")
    for i = 0, 7 do
        file:write(string.format("%s\"%s\"", i == 0 and "" or ",", s.fp[i]))
    end
    file:write("]\n    }" .. (trailing_comma and "," or "") .. "\n")
end

local function emit_json(file, results)
    file:write("[\n")
    for i, e in ipairs(results) do
        file:write(string.format("  {\n    \"name\": %q,\n", e.name))
        emit_snap(file, "initial", e.initial, true)
        emit_snap(file, "final",   e.final,   false)
        file:write(string.format("  }%s\n", i < #results and "," or ""))
    end
    file:write("]\n")
end

-- ----------------------------------------------------------------------
-- Driver
-- ----------------------------------------------------------------------
function capture_run()
    init_handles()
    print("FPU capture starting (output: " .. FPU_OUT_PATH .. ")")
    manager.machine.debugger.execution_state = "stop"

    local results = {}
    for _, t in ipairs(tests) do
        print(string.format("  running: %s", t.name))
        results[#results + 1] = run_one(t)
    end

    local f = io.open(FPU_OUT_PATH, "w")
    if f == nil then
        print("ERROR: cannot open " .. FPU_OUT_PATH)
        return
    end
    emit_json(f, results)
    f:close()
    print(string.format("Wrote %d tests to %s", #results, FPU_OUT_PATH))
end

print("mame_fpu_capture.lua loaded. After boot has progressed, run:")
print("  > capture_run()")
