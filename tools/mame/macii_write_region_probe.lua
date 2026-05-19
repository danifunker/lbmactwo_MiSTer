local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "900") or 900
local stop_tick = tonumber(os.getenv("MAME_STOP_TICK") or "")
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "120") or 120
local start_addr = tonumber(os.getenv("MAME_WRITE_START") or "12000", 16) or 0x12000
local end_addr = tonumber(os.getenv("MAME_WRITE_END") or "125ff", 16) or 0x125ff
local printed = 0

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function reg(name)
	local entry = cpu.state[name]
	if entry == nil then
		return 0
	end
	return entry.value or 0
end

local function u8(addr)
	return mem:read_u8(addr) or 0
end

local function u16(addr)
	return (((u8(addr) << 8) | u8(addr + 1)) & 0xffff)
end

local function u32(addr)
	return ((u16(addr) << 16) | u16(addr + 2)) & 0xffffffff
end

local function log_write(offset, data, mask)
	if frames < min_frame or printed >= max_print then
		return
	end
	printed = printed + 1
	print(string.format(
		"MAME_WRITE_REGION hit=%03d frame=%d pc=%s tick016A=%s addr=%s data=%s mask=%s D0=%s D1=%s D2=%s A0=%s A1=%s A2=%s A4=%s A5=%s L12000=%s L124D0=%s",
		printed, frames, hex(reg("CURPC")), hex(u32(0x016a)), hex(offset),
		hex(data), hex(mask), hex(reg("D0")), hex(reg("D1")), hex(reg("D2")),
		hex(reg("A0")), hex(reg("A1")), hex(reg("A2")), hex(reg("A4")),
		hex(reg("A5")), hex(u32(0x12000)), hex(u32(0x124d0))))
end

mem:install_write_tap(start_addr, end_addr, "write_region_probe", log_write)

emu.register_frame_done(function()
	frames = frames + 1
	local tick = u32(0x016a)
	local tick_ready = tick < 0x01000000
	if (stop_tick ~= nil and tick_ready and tick >= stop_tick) or frames >= stop_frame then
		print(string.format(
			"MAME_WRITE_REGION_SUMMARY frames=%d printed=%d pc=%s tick016A=%s L12000=%s L124D0=%s",
			frames, printed, hex(reg("CURPC")), hex(u32(0x016a)),
			hex(u32(0x12000)), hex(u32(0x124d0))))
		manager.machine:exit()
	end
end, "macii_write_region_probe")
