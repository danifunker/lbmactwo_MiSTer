local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local printed = 0
local via_reads = 0
local via_writes = 0
local lowmem_writes = 0
local loop_hits = { 0, 0, 0 }
local loop_last_cycles = { nil, nil, nil }
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "320") or 320
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "600") or 600
local frame_interval = tonumber(os.getenv("MAME_FRAME_INTERVAL") or "20") or 20

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function machine_seconds()
	local ok, value = pcall(function() return manager.machine.time:as_double() end)
	if ok then
		return string.format("%.9f", value)
	end
	return "?"
end

local function cpu_cycles()
	local ok, value = pcall(function() return cpu:total_cycles() end)
	if ok then
		return tostring(value)
	end
	return "?"
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

local function via_reg(addr)
	return (addr >> 9) & 0x0f
end

local function log(line)
	if printed >= max_print then
		return
	end
	print(line)
	printed = printed + 1
end

local function via_name(addr)
	return ((addr & 0x00002000) ~= 0) and "VIA2" or "VIA1"
end

local function log_via(kind, addr, data, mask)
	if u16(0x0d28) == 0x4080 then
		return
	end

	local r = via_reg(addr)
	if not ((r >= 4 and r <= 9) or r == 0x0b or r == 0x0d or r == 0x0e) then
		return
	end

	log(string.format(
		"MAME_CALIB_VIA_%s frame=%d time=%s cycles=%s pc=%s %s reg=%X addr=%s data=%s mask=%s W0D00=%04X W0D02=%04X W0DA6=%04X W0D24=%04X W0D28=%04X",
		kind, frames, machine_seconds(), cpu_cycles(), hex(reg("CURPC")), via_name(addr), r, hex(addr), hex(data, 8),
		hex(mask, 8), u16(0x0d00), u16(0x0d02), u16(0x0da6), u16(0x0d24), u16(0x0d28)))
end

local function log_lowmem(kind, addr, data, mask)
	if addr ~= 0x0d00 and addr ~= 0x0d02 and addr ~= 0x0da6 then
		return
	end

	lowmem_writes = lowmem_writes + 1
	log(string.format(
		"MAME_CALIB_LM_%s frame=%d time=%s cycles=%s pc=%s addr=%s data=%s mask=%s W0D00=%04X W0D02=%04X W0DA6=%04X W0D24=%04X W0D28=%04X D0=%s",
		kind, frames, machine_seconds(), cpu_cycles(), hex(reg("CURPC")), hex(addr), hex(data, 8), hex(mask, 8),
		u16(0x0d00), u16(0x0d02), u16(0x0da6), u16(0x0d24), u16(0x0d28), hex(reg("D0"))))
end

mem:install_read_tap(0x50000000, 0x50f03fff, "calib_via_r", function(offset, data, mask)
	via_reads = via_reads + 1
	log_via("R", offset, data, mask)
end)

mem:install_write_tap(0x50000000, 0x50f03fff, "calib_via_w", function(offset, data, mask)
	via_writes = via_writes + 1
	log_via("W", offset, data, mask)
end)

mem:install_write_tap(0x00000d00, 0x00000daf, "calib_lm_w", function(offset, data, mask)
	log_lowmem("W", offset, data, mask)
end)

local loop_pcs = {
	[0x4080059c] = 1,
	[0x408005d6] = 2,
	[0x40800612] = 3,
}

local function log_loop_fetch(pc, data, mask)
	local idx = loop_pcs[pc]
	if idx == nil then
		return
	end

	loop_hits[idx] = loop_hits[idx] + 1
	local cycles = tonumber(cpu_cycles())
	local delta = 0
	if cycles ~= nil and loop_last_cycles[idx] ~= nil then
		delta = cycles - loop_last_cycles[idx]
	end
	loop_last_cycles[idx] = cycles

	if loop_hits[idx] <= 8 or (loop_hits[idx] & 0xff) == 0 then
		log(string.format(
			"MAME_CALIB_LOOP[%d] hit=%d frame=%d time=%s cycles=%s delta=%d pc=%s data=%04X mask=%s D0=%s D1=%s A0=%s A1=%s W0D00=%04X W0DA6=%04X",
			idx - 1, loop_hits[idx], frames, machine_seconds(), cpu_cycles(), delta, hex(pc),
			data or 0, hex(mask, 8), hex(reg("D0")), hex(reg("D1")), hex(reg("A0")), hex(reg("A1")),
			u16(0x0d00), u16(0x0da6)))
	end
end

mem:install_read_tap(0x4080059c, 0x4080059f, "calib_loop0_fetch", function(offset, data, mask)
	if reg("CURPC") == 0x4080059c then
		log_loop_fetch(0x4080059c, data, mask)
	end
end)

mem:install_read_tap(0x408005d4, 0x408005db, "calib_loop1_fetch", function(offset, data, mask)
	if reg("CURPC") == 0x408005d6 then
		log_loop_fetch(0x408005d6, data, mask)
	end
end)

mem:install_read_tap(0x40800610, 0x40800617, "calib_loop2_fetch", function(offset, data, mask)
	if reg("CURPC") == 0x40800612 then
		log_loop_fetch(0x40800612, data, mask)
	end
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frame_interval > 0 and (frames % frame_interval) == 0 then
		log(string.format(
			"MAME_CALIB_FRAME frame=%d time=%s cycles=%s pc=%s tick016A=%s W0D00=%04X W0D02=%04X W0DA6=%04X W0D24=%04X W0D28=%04X D5=%s",
			frames, machine_seconds(), cpu_cycles(), hex(reg("CURPC")), hex(u32(0x016a)), u16(0x0d00),
			u16(0x0d02), u16(0x0da6), u16(0x0d24), u16(0x0d28), hex(reg("D5"))))
	end
	if frames >= stop_frame then
		print(string.format(
			"MAME_CALIB_SUMMARY frames=%d time=%s cycles=%s printed=%d via_reads=%d via_writes=%d lowmem_writes=%d loops=%d/%d/%d pc=%s tick016A=%s W0D00=%04X W0D02=%04X W0DA6=%04X W0D24=%04X W0D28=%04X",
			frames, machine_seconds(), cpu_cycles(), printed, via_reads, via_writes, lowmem_writes,
			loop_hits[1], loop_hits[2], loop_hits[3],
			hex(reg("CURPC")), hex(u32(0x016a)), u16(0x0d00), u16(0x0d02), u16(0x0da6),
			u16(0x0d24), u16(0x0d28)))
		manager.machine:exit()
	end
end, "macii_calib_probe")
