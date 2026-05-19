local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "1300") or 1300
local stop_tick = tonumber(os.getenv("MAME_STOP_TICK") or "")
local extra_dump_start = tonumber(os.getenv("MAME_DUMP_START") or "", 16)
local extra_dump_count = tonumber(os.getenv("MAME_DUMP_COUNT") or "64") or 64

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

local function dump_words(label, start, count)
	local parts = {}
	for i = 0, count - 1 do
		parts[#parts + 1] = string.format("%04X", u16(start + i * 2))
	end
	print(string.format("MAME_RAM_DUMP %s %s %s", label, hex(start), table.concat(parts, " ")))
end

local function find_bytes(first, last, bytes)
	for addr = first, last - #bytes + 1 do
		local ok = true
		for i = 1, #bytes do
			if u8(addr + i - 1) ~= bytes[i] then
				ok = false
				break
			end
		end
		if ok then
			return addr
		end
	end
	return nil
end

local function dump_state()
	local sp = reg("A7")
	local lba60_at = find_bytes(0x000000, 0x1fffff, { 0x4c, 0x4b, 0x60, 0x00, 0x00, 0x86, 0x44, 0x18 })
	print(string.format(
		"MAME_RAM_STATE frame=%d pc=%s tick016A=%s D0=%s D1=%s D2=%s D3=%s D4=%s D5=%s D6=%s D7=%s A0=%s A1=%s A2=%s A3=%s A4=%s A5=%s A6=%s A7=%s",
		frames, hex(reg("CURPC")), hex(u32(0x016a)),
		hex(reg("D0")), hex(reg("D1")), hex(reg("D2")), hex(reg("D3")),
		hex(reg("D4")), hex(reg("D5")), hex(reg("D6")), hex(reg("D7")),
		hex(reg("A0")), hex(reg("A1")), hex(reg("A2")), hex(reg("A3")),
		hex(reg("A4")), hex(reg("A5")), hex(reg("A6")), hex(sp)))
	print(string.format(
		"MAME_RAM_LOW DSErr=%04X savedPC=%s savedSR=%04X MemTop=%s BufPtr=%s HeapEnd=%s ApplLimit=%s SysZone=%s ApplZone=%s DSAlertTab=%s L12000=%s L124D0=%s LBA60=%s",
		u16(0x0af0), hex(u32(0x0c70)), u16(0x0c74),
		hex(u32(0x0108)), hex(u32(0x010c)), hex(u32(0x0114)),
		hex(u32(0x0130)), hex(u32(0x02a6)), hex(u32(0x02aa)),
		hex(u32(0x02ba)), hex(u32(0x12000)), hex(u32(0x124d0)),
		lba60_at and hex(lba60_at) or "notfound"))
	dump_words("001FF700", 0x001ff700, 64)
	dump_words("001FE500", 0x001fe500, 64)
	dump_words("000C7F20", 0x000c7f20, 64)
	dump_words("000C7F58", 0x000c7f58, 64)
	dump_words("00012000", 0x00012000, 64)
	dump_words("000124C0", 0x000124c0, 64)
	dump_words("00007F40", 0x00007f40, 32)
	dump_words("0000D040", 0x0000d040, 32)
	dump_words("000FE600", 0x000fe600, 32)
	dump_words("00100000", 0x00100000, 64)
	dump_words("000FFC00", 0x000ffc00, 64)
	dump_words("A2", reg("A2") & 0xffffff, 64)
	dump_words("A4", reg("A4") & 0xffffff, 64)
	dump_words("SP", sp & 0xffffff, 32)
	if extra_dump_start ~= nil then
		dump_words("EXTRA", extra_dump_start & 0xffffff, extra_dump_count)
	end
end

emu.register_frame_done(function()
	frames = frames + 1
	local tick = u32(0x016a)
	local tick_ready = tick < 0x01000000
	if (stop_tick ~= nil and tick_ready and tick >= stop_tick) or frames >= stop_frame then
		dump_state()
		manager.machine:exit()
	end
end, "macii_ram_dump_probe")
