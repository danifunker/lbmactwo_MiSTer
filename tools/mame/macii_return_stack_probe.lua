local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "720") or 720
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "240") or 240
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local printed = 0
local last_pc = 0xffffffff

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function reg(name)
	local entry = cpu.state[name]
	return entry and entry.value or 0
end

local function u8(addr)
	return mem:read_u8(addr & 0x00ffffff) or 0
end

local function u16(addr)
	return (((u8(addr) << 8) | u8(addr + 1)) & 0xffff)
end

local function u32(addr)
	return (((u16(addr) << 16) | u16(addr + 2)) & 0xffffffff)
end

local function in_target_pc(pc)
	return (pc >= 0x40806530 and pc <= 0x40806566)
		or (pc >= 0x4080d650 and pc <= 0x4080d6b4)
		or (pc >= 0x4080de80 and pc <= 0x4080dfc0)
		or (pc >= 0x4080e100 and pc <= 0x4080e160)
		or (pc >= 0x000fe000 and pc < 0x00100000)
end

local function probe_fetch(offset, data, mask)
	local pc = reg("CURPC")
	if frames < min_frame or printed >= max_print or pc == last_pc or not in_target_pc(pc) then
		return
	end
	last_pc = pc
	local sp = reg("A7") & 0x00ffffff
	print(string.format(
		"MAME_RETURN frame=%d pc=%s op=%04X tick=%s d0=%s d1=%s d2=%s d5=%s d6=%s a0=%s a1=%s a2=%s a3=%s a4=%s a5=%s a6=%s a7=%s spw=%04X spl0=%s spl1=%s memtop=%s bufptr=%s heapend=%s appllimit=%s syszone=%s applzone=%s dserr=%04X savedpc=%s ioresult_ffc0c=%04X l08ee=%s l0d10=%s l0d14=%s",
		frames, hex(pc), data or 0, hex(u32(0x016a)), hex(reg("D0")), hex(reg("D1")),
		hex(reg("D2")), hex(reg("D5")), hex(reg("D6")), hex(reg("A0")), hex(reg("A1")),
		hex(reg("A2")), hex(reg("A3")), hex(reg("A4")), hex(reg("A5")), hex(reg("A6")), hex(reg("A7")),
		u16(sp), hex(u32(sp + 2)), hex(u32(sp + 6)), hex(u32(0x0108)), hex(u32(0x010c)),
		hex(u32(0x0114)), hex(u32(0x0130)), hex(u32(0x02a6)), hex(u32(0x02aa)),
		u16(0x0af0), hex(u32(0x0c70)),
		u16(0x0ffc0c), hex(u32(0x08ee)),
		hex(u32(0x0d10)), hex(u32(0x0d14))))
	printed = printed + 1
end

mem:install_read_tap(0x40806530, 0x40806567, "return_stack_trap", probe_fetch)
mem:install_read_tap(0x4080d650, 0x4080d6b7, "return_stack_d6", probe_fetch)
mem:install_read_tap(0x4080de80, 0x4080dfc3, "return_stack_de", probe_fetch)
mem:install_read_tap(0x4080e100, 0x4080e163, "return_stack_e1", probe_fetch)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format("MAME_RETURN_SUMMARY frames=%d printed=%d pc=%s tick=%s",
			frames, printed, hex(reg("CURPC")), hex(u32(0x016a))))
		manager.machine:exit()
	end
end, "macii_return_stack_probe")
