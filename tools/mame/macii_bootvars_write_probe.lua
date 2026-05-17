local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "450") or 450
local max_hits = tonumber(os.getenv("MAME_MAX_PRINT") or "120") or 120
local hits = 0

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function reg(name)
	local entry = cpu.state[name]
	return entry and entry.value or 0
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

local function log_write(kind, addr, data, mask)
	if hits >= max_hits then
		return
	end
	hits = hits + 1
	print(string.format(
		"MAME_BOOTVARS_W_%s hit=%03d frame=%d pc=%s tick016A=%s addr=%s data=%s mask=%s D0=%s D1=%s D2=%s D5=%s D6=%s A0=%s A1=%s A2=%s A3=%s A4=%s A7=%s W09FA=%04X W09FC=%04X W09FE=%04X W0A00=%04X W0A02=%04X B0B22=%02X B0B2E=%02X L030A=%s",
		kind, hits, frames, hex(reg("CURPC")), hex(u32(0x016a)), hex(addr),
		hex(data), hex(mask), hex(reg("D0")), hex(reg("D1")), hex(reg("D2")),
		hex(reg("D5")), hex(reg("D6")), hex(reg("A0")), hex(reg("A1")),
		hex(reg("A2")), hex(reg("A3")), hex(reg("A4")), hex(reg("A7")),
		u16(0x09fa), u16(0x09fc), u16(0x09fe), u16(0x0a00), u16(0x0a02),
		u8(0x0b22), u8(0x0b2e), hex(u32(0x030a))))
end

mem:install_write_tap(0x000009f8, 0x00000a03, "bootvars_w", function(offset, data, mask)
	log_write("TAP", offset, data, mask)
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format(
			"MAME_BOOTVARS_W_SUMMARY frames=%d hits=%d pc=%s tick016A=%s W09FA=%04X W09FC=%04X W09FE=%04X W0A00=%04X W0A02=%04X L030A=%s",
			frames, hits, hex(reg("CURPC")), hex(u32(0x016a)), u16(0x09fa),
			u16(0x09fc), u16(0x09fe), u16(0x0a00), u16(0x0a02), hex(u32(0x030a))))
		manager.machine:exit()
	end
end, "macii_bootvars_write_probe")
