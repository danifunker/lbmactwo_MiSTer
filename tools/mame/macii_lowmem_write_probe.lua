local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "1300") or 1300
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "200") or 200
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
	return (((u16(addr) << 16) | u16(addr + 2)) & 0xffffffff)
end

local function log_write(addr, data, mask)
	if frames < min_frame or printed >= max_print then
		return
	end
	if not ((addr >= 0x00000108 and addr <= 0x00000137) or
	        (addr >= 0x000002a6 and addr <= 0x000002ad)) then
		return
	end
	printed = printed + 1
	print(string.format(
		"MAME_LOWMEM_WRITE hit=%03d frame=%d pc=%s tick016A=%s addr=%s data=%s mask=%s D0=%s D1=%s A0=%s A2=%s A4=%s A5=%s MemTop=%s BufPtr=%s StkLowPt=%s HeapEnd=%s ApplLimit=%s SysZone=%s ApplZone=%s",
		printed, frames, hex(reg("CURPC")), hex(u32(0x016a)), hex(addr),
		hex(data), hex(mask), hex(reg("D0")), hex(reg("D1")), hex(reg("A0")),
		hex(reg("A2")), hex(reg("A4")), hex(reg("A5")),
		hex(u32(0x0108)), hex(u32(0x010c)), hex(u32(0x0110)),
		hex(u32(0x0114)), hex(u32(0x0130)), hex(u32(0x02a6)), hex(u32(0x02aa))))
end

mem:install_write_tap(0x00000108, 0x00000137, "lowmem_size_w", function(offset, data, mask)
	log_write(offset, data, mask)
end)

mem:install_write_tap(0x000002a4, 0x000002af, "lowmem_zone_w", function(offset, data, mask)
	log_write(offset, data, mask)
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format(
			"MAME_LOWMEM_SUMMARY frames=%d pc=%s tick016A=%s printed=%d MemTop=%s BufPtr=%s StkLowPt=%s HeapEnd=%s ApplLimit=%s SysZone=%s ApplZone=%s DSErr=%04X savedPC=%s savedSR=%04X",
			frames, hex(reg("CURPC")), hex(u32(0x016a)), printed,
			hex(u32(0x0108)), hex(u32(0x010c)), hex(u32(0x0110)),
			hex(u32(0x0114)), hex(u32(0x0130)), hex(u32(0x02a6)),
			hex(u32(0x02aa)), u16(0x0af0), hex(u32(0x0c70)), u16(0x0c74)))
		manager.machine:exit()
	end
end, "macii_lowmem_write_probe")
