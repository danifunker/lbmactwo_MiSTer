-- Track key Verilator-vs-MAME indicators frame-by-frame:
--   * PC, A1, SP, RET
--   * MBState ($172), $0D10, $0D14, $08EE
--   * Take screenshots at requested frames
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "2000") or 2000
local snap_frames_env = os.getenv("MAME_SNAP_FRAMES") or "500,1000,1500,2000"
local snap_at = {}
for f in string.gmatch(snap_frames_env, "[^,]+") do
	snap_at[tonumber(f)] = true
end

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function u16(addr) return (mem:read_u8(addr) << 8) | mem:read_u8(addr + 1) end
local function u32(addr) return (u16(addr) << 16) | u16(addr + 2) end
local function u8(addr)  return mem:read_u8(addr) end

local function reg(n) return cpu.state[n] and cpu.state[n].value or 0 end

emu.register_frame_done(function()
	frames = frames + 1
	if frames % 100 == 0 or snap_at[frames] then
		print(string.format(
			"MAME_PROBE frame=%d pc=%s A1=%s SP=%s "
			.. "MBState($172)=%02X $173=%02X $0D10=%s $0D14=%s $08EE=%s",
			frames,
			hex(reg("CURPC")), hex(reg("A1")), hex(reg("SP")),
			u8(0x172), u8(0x173), hex(u32(0x0D10)), hex(u32(0x0D14)), hex(u32(0x08EE))))
	end
	if snap_at[frames] then
		manager.machine.video:snapshot()
		print(string.format("MAME_SNAP frame=%d taken", frames))
	end
	if frames >= stop_frame then
		print(string.format("MAME_DONE frames=%d", frames))
		manager.machine:exit()
	end
end, "progress")
