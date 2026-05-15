-- MAME Lua script: capture FPU instruction state from maciihmu.
--
-- Drives MAME as an FPU oracle to produce JSON test corpora that the
-- SingleStepTests/fpu bench can consume.
--
-- Strategy: per test we plant a small instruction stream at $1000:
--   preload  → init-state dump → test instruction → final-state dump → STOP
-- Then we hijack PC, resume the CPU, wait for PC to reach the STOP, pause
-- again, read both dump windows back from RAM, advance to the next test.
--
-- Implementation is a frame-driven state machine. The Lua engine only
-- gets control between MAME frames (via the periodic/frame_done hooks),
-- so we cannot block waiting for the CPU to run — we let it run for a
-- frame, then come back and check progress.
--
-- USAGE
-- -----
--   ../mame/maciihmu maciihmu -bios original -skip_gameinfo \
--     -debug -debugger none -window -nothrottle \
--     -autoboot_delay 1 \
--     -autoboot_script SingleStepTests/gen/mame_fpu_capture.lua
--
-- Why these flags:
--   maciihmu maciihmu : binary name + system arg (yes, twice)
--   -bios original    : rev. A ROM
--   -skip_gameinfo    : skip system info screen
--   -debug            : skips the disclaimer/warnings screens
--                       (UI's display_startup_screens uses
--                        DEBUG_FLAG_ENABLED to disable both)
--   -debugger none    : but DON'T open the debugger UI window
--   -nothrottle       : run as fast as host can (we want to exit ASAP)
--   -autoboot_delay 1 : let one second pass before our Lua hook fires
--                       so the boot ROM has time to flip the overlay
--                       bit and map RAM at $0..
--
-- MAME exits automatically once the corpus is written.

local FPU_OUT_PATH = "/tmp/fpu_corpus.json"

local PROG_BASE   = 0x00001000
local INIT_DUMP   = 0x00001100
local FINAL_DUMP  = 0x00001200

-- Each entry produces ONE corpus entry. Bytes are concatenated and
-- planted at PROG_BASE between init/final dump blocks.
local tests = {
    -- Sanity test 1: no FPU at all. If this works, FPU exception is the
    -- problem. If even this hangs, our stop-detection is wrong.
    { name = "DBG: MOVEQ #5,D0 (no FPU)",
      preload = {},
      test    = { 0x70, 0x05 } }, -- MOVEQ #5,D0
    -- Sanity test 2: F-line but skip the dump prologue/epilogue.
    { name = "FMOVE.L #1,FP0",
      preload = {},
      test    = { 0x70, 0x01,            -- MOVEQ #1,D0
                  0xF2, 0x00, 0x80, 0x00 } }, -- FMOVE.L D0,FP0
    { name = "FADD.X FP0,FP0 (1+1=2)",
      preload = { 0x70, 0x01, 0xF2, 0x00, 0x80, 0x00 },
      test    = { 0xF2, 0x00, 0x00, 0x22 } },
    { name = "FMUL.X FP0,FP0 (2*2=4)",
      preload = { 0x70, 0x02, 0xF2, 0x00, 0x80, 0x00 },
      test    = { 0xF2, 0x00, 0x00, 0x23 } },
    { name = "FSQRT.X FP0,FP0 (sqrt(4)=2)",
      preload = { 0x70, 0x04, 0xF2, 0x00, 0x80, 0x00 },
      test    = { 0xF2, 0x00, 0x00, 0x04 } },
    { name = "FNEG.X FP0,FP0 (1 -> -1)",
      preload = { 0x70, 0x01, 0xF2, 0x00, 0x80, 0x00 },
      test    = { 0xF2, 0x00, 0x00, 0x1A } },
    { name = "FABS.X FP0,FP0 (-1 -> 1)",
      preload = { 0x70, 0xFF, 0xF2, 0x00, 0x80, 0x00 },
      test    = { 0xF2, 0x00, 0x00, 0x18 } },
    { name = "FTST.X FP0",
      preload = { 0x70, 0x00, 0xF2, 0x00, 0x80, 0x00 },
      test    = { 0xF2, 0x00, 0x00, 0x3A } },
    { name = "FMOVE.X FP0,FP1",
      preload = { 0x70, 0x05, 0xF2, 0x00, 0x80, 0x00 },
      test    = { 0xF2, 0x00, 0x00, 0x80 } },
}

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

-- Instruction emitters --------------------------------------------------

-- FMOVE.X FPn,(abs.L)  --  8 bytes
local function emit_fmove_x_to_abs(fpn, abs_addr)
    local opword = 0xF239
    local ext    = 0x7400 | (fpn * 128)
    return {
        (opword >> 8) & 0xFF, opword & 0xFF,
        (ext    >> 8) & 0xFF, ext    & 0xFF,
        (abs_addr >> 24) & 0xFF, (abs_addr >> 16) & 0xFF,
        (abs_addr >>  8) & 0xFF,  abs_addr        & 0xFF,
    }
end

-- MOVE.L Dn,(abs.L)  --  6 bytes
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

-- State dump block: FP0..FP7 then D0..D7 then A0..A7.
-- Layout in RAM[dump_base..]:
--   +0x00..0x5F : FP0..FP7 (12 bytes each)
--   +0x60..0x7F : D0..D7 (4 bytes each)
--   +0x80..0x9F : A0..A7 (4 bytes each)
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
    for an = 0, 7 do
        append(emit_move_l_an_to_abs(an, dump_base + 0x80 + an * 4))
    end
    return out
end

-- Read the dump block back from RAM into a snapshot table.
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
-- Frame-driven state machine
--
-- Phases:
--   WAIT_RAM    : poll RAM at $1000 each frame until writable.
--   SETUP_NEXT  : pause CPU, plant next test program, set PC, resume.
--                 Goes directly to RUN.
--   RUN         : every frame, check if PC is at our stop address; if so,
--                 pause, capture, advance.
--   DONE        : write JSON, exit MAME.
-- ----------------------------------------------------------------------
local RAM_PROBE_VALUE = 0xDEADBEEF
local MAX_WAIT_FRAMES = 1800
local MAX_RUN_FRAMES  = 120     -- per test; ~2 sec headroom

local phase   = "WAIT_RAM"
local frames  = 0
local test_i  = 1
local stop_pc = 0
local results = {}

local function start_test(t)
    -- Build the instruction stream.
    local out = {}
    local function append(bs)
        for _, b in ipairs(bs) do out[#out + 1] = b end
    end
    append(t.preload)
    append(emit_state_dump(INIT_DUMP))
    append(t.test)
    append(emit_state_dump(FINAL_DUMP))
    -- Landing pad: JMP-to-self. PC sticking at this address means the
    -- test is complete. Easier to detect than STOP, and survives the
    -- absence of any vector table / stack setup.
    local jmp_pc = PROG_BASE + #out
    append({
        0x4E, 0xF9,
        (jmp_pc >> 24) & 0xFF, (jmp_pc >> 16) & 0xFF,
        (jmp_pc >>  8) & 0xFF,  jmp_pc        & 0xFF,
    })
    stop_pc = jmp_pc

    write_bytes(PROG_BASE, out)

    -- Reset core registers. SR = $2700 (supervisor, interrupts masked
    -- level 7) — critical because the running maciihmu machine keeps
    -- firing VBL/timer interrupts; without masking, PC bounces back to
    -- the ROM interrupt handler every frame.
    for r = 0, 7 do rset("D" .. r, 0); rset("A" .. r, 0) end
    rset("SR", 0x2700)
    rset("A7", 0x00200000)
    rset("PC", PROG_BASE)
    -- stop_pc was set inside the append() block above.
    frames  = 0
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
            phase  = "SETUP_NEXT"
            frames = 0
        elseif frames >= MAX_WAIT_FRAMES then
            print(string.format("ERROR: RAM never mapped at $%08X.", PROG_BASE))
            phase = "ABORT"
        end

    elseif phase == "SETUP_NEXT" then
        if test_i > #tests then
            phase = "DONE"
            return
        end
        local t = tests[test_i]
        print(string.format("[%d/%d] %s", test_i, #tests, t.name))
        emu.pause()
        start_test(t)
        emu.unpause()
        phase = "RUN"

    elseif phase == "RUN" then
        frames = frames + 1
        local pc = rget("PC")
        -- The test ends with a JMP-to-self at stop_pc; PC sticking
        -- there means the test instruction stream has completed.
        if pc == stop_pc then
            emu.pause()
            local t = tests[test_i]
            results[#results + 1] = {
                name    = t.name,
                initial = read_snap(INIT_DUMP),
                final   = read_snap(FINAL_DUMP),
            }
            test_i = test_i + 1
            phase  = "SETUP_NEXT"
        elseif frames >= MAX_RUN_FRAMES then
            print(string.format("  timeout: PC=$%08X, expected $%08X",
                pc, stop_pc))
            emu.pause()
            test_i = test_i + 1
            phase  = "SETUP_NEXT"
        end

    elseif phase == "DONE" then
        local f = io.open(FPU_OUT_PATH, "w")
        if f == nil then
            print("ERROR: cannot open " .. FPU_OUT_PATH)
        else
            emit_json(f, results)
            f:close()
            print(string.format("Wrote %d tests to %s", #results, FPU_OUT_PATH))
        end
        phase = "EXITED"
        manager.machine:exit()

    elseif phase == "ABORT" then
        manager.machine:exit()
    end
end

emu.register_frame_done(tick, "fpu_capture")
print("mame_fpu_capture.lua loaded — waiting for RAM, will run "
      .. #tests .. " tests then exit.")
