local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local hits = 0
local periodic = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "900") or 900
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local frame_interval = tonumber(os.getenv("MAME_FRAME_INTERVAL") or "40") or 40
local max_hits = tonumber(os.getenv("MAME_MAX_PRINT") or "160") or 160
local last_pc = 0xffffffff
local last_tick = 0xffffffff

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

local function log_wait(source)
	local pc = reg("CURPC")
	if frames < min_frame or hits >= max_hits or pc < 0x40801600 or pc > 0x40801666 then
		return
	end

	local tick = u32(0x016a)
	local spin_pc = pc >= 0x40801652 and pc <= 0x40801658
	if spin_pc then
		if tick == last_tick then
			return
		end
	elseif pc == last_pc then
		return
	end

	last_pc = pc
	last_tick = tick
	hits = hits + 1

	local sp = reg("A7")
	local a2 = reg("A2")
	print(string.format(
		"MAME_WAIT_%s hit=%03d frame=%d periodic=%d pc=%s tick016A=%s D0=%s D1=%s D2=%s D5=%s D7=%s A0=%s A2=%s A3=%s A4=%s SP=%s RET=%s W017A=%04X B0C2F=%02X W0D24=%04X W0D28=%04X A2W8=%04X",
		source, hits, frames, periodic, hex(pc), hex(tick), hex(reg("D0")),
		hex(reg("D1")), hex(reg("D2")), hex(reg("D5")), hex(reg("D7")),
		hex(reg("A0")), hex(a2), hex(reg("A3")), hex(reg("A4")),
		hex(sp), hex(u32(sp)), u16(0x017a), u8(0x0c2f), u16(0x0d24),
		u16(0x0d28), u16(a2 + 8)))
end

emu.register_periodic(function()
	periodic = periodic + 1
	log_wait("PERIODIC")
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frame_interval > 0 and frames >= min_frame and (frames % frame_interval) == 0 then
		print(string.format(
			"MAME_WAIT_FRAME frame=%d periodic=%d pc=%s tick016A=%s D0=%s D5=%s D7=%s W017A=%04X B0C2F=%02X W0D24=%04X W0D28=%04X",
			frames, periodic, hex(reg("CURPC")), hex(u32(0x016a)),
			hex(reg("D0")), hex(reg("D5")), hex(reg("D7")), u16(0x017a),
			u8(0x0c2f), u16(0x0d24), u16(0x0d28)))
	end
	log_wait("FRAME")
	if frames >= stop_frame then
		print(string.format(
			"MAME_WAIT_SUMMARY frames=%d periodic=%d hits=%d pc=%s tick016A=%s D0=%s D5=%s D7=%s W017A=%04X B0C2F=%02X W0D24=%04X W0D28=%04X",
			frames, periodic, hits, hex(reg("CURPC")), hex(u32(0x016a)),
			hex(reg("D0")), hex(reg("D5")), hex(reg("D7")), u16(0x017a),
			u8(0x0c2f), u16(0x0d24), u16(0x0d28)))
		manager.machine:exit()
	end
end, "macii_wait_probe")
