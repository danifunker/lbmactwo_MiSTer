local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local hits = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "520") or 520
local max_hits = tonumber(os.getenv("MAME_MAX_PRINT") or "120") or 120
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local frame_interval = tonumber(os.getenv("MAME_FRAME_INTERVAL") or "0") or 0
local start_pc = tonumber(os.getenv("MAME_PC_START") or "40826C70", 16) or 0x40826c70
local end_pc = tonumber(os.getenv("MAME_PC_END") or "40826CDF", 16) or 0x40826cdf
local tap_start = tonumber(os.getenv("MAME_TAP_START") or "", 16) or start_pc
local tap_end = tonumber(os.getenv("MAME_TAP_END") or "", 16) or end_pc
local last_pc = 0xffffffff

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

local function u16(addr)
	return (((mem:read_u8(addr) or 0) << 8) | (mem:read_u8(addr + 1) or 0)) & 0xffff
end

local function u32(addr)
	return ((u16(addr) << 16) | u16(addr + 2)) & 0xffffffff
end

local function u8(addr)
	return mem:read_u8(addr) or 0
end

local function fetch_probe(offset, data, mask)
	local pc = reg("CURPC")
	if frames < min_frame or hits >= max_hits or pc < start_pc or pc > end_pc then
		return
	end
	if pc == last_pc and pc ~= 0x40826ca8 and pc ~= 0x40826cca then
		return
	end
	last_pc = pc
	print(string.format(
		"MAME_PC_REGION hit=%03d frame=%d pc=%s data=%04X mask=%s tick016A=%s D0=%s D1=%s D5=%s D7=%s A0=%s A3=%s A4=%s",
		hits, frames, hex(pc), data or 0, hex(mask or 0),
		hex(u32(0x016a)), hex(reg("D0")), hex(reg("D1")), hex(reg("D5")),
		hex(reg("D7")), hex(reg("A0")), hex(reg("A3")), hex(reg("A4"))))
	hits = hits + 1
end

mem:install_read_tap(tap_start, tap_end, "pc_region_fetch", fetch_probe)

emu.register_frame_done(function()
	frames = frames + 1
	if frame_interval > 0 and frames >= min_frame and (frames % frame_interval) == 0 then
		print(string.format("MAME_PC_FRAME frame=%d pc=%s tick016A=%s D0=%s D1=%s D5=%s D7=%s A0=%s A3=%s A4=%s W017A=%04X B0C2F=%02X W0D24=%04X W0D28=%04X",
			frames, hex(reg("CURPC")), hex(u32(0x016a)), hex(reg("D0")),
			hex(reg("D1")), hex(reg("D5")), hex(reg("D7")), hex(reg("A0")),
			hex(reg("A3")), hex(reg("A4")), u16(0x017a), u8(0x0c2f),
			u16(0x0d24), u16(0x0d28)))
	end
	if frames >= stop_frame then
		print(string.format("MAME_PC_REGION_SUMMARY frames=%d hits=%d pc=%s tick016A=%s D0=%s D1=%s D5=%s D7=%s A3=%s A4=%s W017A=%04X B0C2F=%02X W0D24=%04X W0D28=%04X",
			frames, hits, hex(reg("CURPC")), hex(u32(0x016a)), hex(reg("D0")),
			hex(reg("D1")), hex(reg("D5")), hex(reg("D7")), hex(reg("A3")),
			hex(reg("A4")), u16(0x017a), u8(0x0c2f), u16(0x0d24), u16(0x0d28)))
		manager.machine:exit()
	end
end, "macii_pc_region_probe")
