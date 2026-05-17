local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "180") or 180
local max_hits = tonumber(os.getenv("MAME_RAMTEST_LIMIT") or "240") or 240
local verbose_loops = os.getenv("MAME_RAMTEST_VERBOSE") == "1"
local hits = 0
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

local function u32(addr)
	local b0 = mem:read_u8(addr) or 0
	local b1 = mem:read_u8(addr + 1) or 0
	local b2 = mem:read_u8(addr + 2) or 0
	local b3 = mem:read_u8(addr + 3) or 0
	return (((((b0 << 8) | b1) << 8) | b2) << 8) | b3
end

local interesting = {
	[0x40802bbc] = true,
	[0x40802bf0] = true,
	[0x40802c10] = true,
	[0x40802c28] = true,
	[0x40802c3c] = true,
	[0x40802cdc] = true,
	[0x40803714] = true,
	[0x40803734] = true,
	[0x40803760] = true,
	[0x40803778] = true,
	[0x4080378e] = true,
	[0x40803794] = true,
	[0x4080379a] = true,
	[0x4080379e] = true,
	[0x408037a0] = true,
	[0x408037a2] = true,
	[0x408037a4] = true,
	[0x408037a6] = true,
	[0x408037a8] = true,
	[0x408037aa] = true,
}

local function log_pc(pc, data, mask)
	if hits >= max_hits or pc == last_pc or not interesting[pc] then
		return
	end
	if not verbose_loops and (pc == 0x40803740 or pc == 0x40803744) then
		return
	end
	if not verbose_loops and (pc == 0x40803786 or pc == 0x4080378a) and reg("D5") > 4 then
		return
	end
	last_pc = pc
	print(string.format(
		"MAME_RAMTEST hit=%03d frame=%d pc=%s data=%04X mask=%08X D0=%s D1=%s D2=%s D3=%s D4=%s D5=%s D6=%s D7=%s A0=%s A1=%s A2=%s A3=%s A4=%s A6=%s M0=%s M8=%s MSP=%s MTOP=%s",
		hits, frames, hex(pc), data or 0, mask or 0,
		hex(reg("D0")), hex(reg("D1")), hex(reg("D2")), hex(reg("D3")),
		hex(reg("D4")), hex(reg("D5")), hex(reg("D6")), hex(reg("D7")),
		hex(reg("A0")), hex(reg("A1")), hex(reg("A2")), hex(reg("A3")),
		hex(reg("A4")), hex(reg("A6")),
		hex(u32(0)), hex(u32(8)), hex(u32(0x1ffd00)), hex(u32(0x1ffffc))))
	hits = hits + 1
end

local function fetch_probe(offset, data, mask)
	log_pc(reg("CURPC"), data, mask)
end

mem:install_read_tap(0x40802bb8, 0x40802c3f, "ramtest_orchestrator_fetch", fetch_probe)
mem:install_read_tap(0x40802cdc, 0x40802cf3, "ramtest_error_fetch", fetch_probe)
mem:install_read_tap(0x40803710, 0x408037af, "ramtest_pattern_fetch", fetch_probe)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format("MAME_RAMTEST_SUMMARY frames=%d hits=%d pc=%s D6=%s D7=%s A2=%s A3=%s",
			frames, hits, hex(reg("CURPC")), hex(reg("D6")), hex(reg("D7")),
			hex(reg("A2")), hex(reg("A3"))))
		manager.machine:exit()
	end
end, "macii_ramtest_probe")
