local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local interval = tonumber(os.getenv("MAME_FRAME_INTERVAL") or "10") or 10
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "300") or 300

local last_region = ""

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function cpu_cycles()
	local ok, value = pcall(function() return cpu:total_cycles() end)
	if ok then
		return tostring(value)
	end
	return "?"
end

local function machine_seconds()
	local ok, value = pcall(function() return manager.machine.time:as_double() end)
	if ok then
		return string.format("%.9f", value)
	end
	return "?"
end

local function u16(addr)
	return (((mem:read_u8(addr) or 0) << 8) | (mem:read_u8(addr + 1) or 0)) & 0xffff
end

local function tick_016a()
	return ((u16(0x016a) << 16) | u16(0x016c)) & 0xffffffff
end

local function reg(name)
	return cpu.state[name].value
end

local function region_for_pc(pc)
	if pc >= 0x40805e4a and pc <= 0x40805f7c then
		return "asc_selftest"
	elseif pc >= 0x4080dde0 and pc <= 0x4080de70 then
		return "via_adb_rtc"
	elseif pc >= 0x40803d00 and pc <= 0x40804400 then
		return "nubus_declrom"
	end
	return ""
end

emu.register_frame_done(function()
	frames = frames + 1

	local pc = cpu.state["CURPC"].value
	local region = region_for_pc(pc)
	if region ~= "" and region ~= last_region then
		print(string.format("MAME_FRAME_REGION frame=%d time=%s cycles=%s tick016A=%s pc=%s region=%s",
			frames, machine_seconds(), cpu_cycles(), hex(tick_016a()), hex(pc), region))
	end
	last_region = region

	if frames == 1 or (interval > 0 and (frames % interval) == 0) or frames >= stop_frame then
		print(string.format("MAME_FRAME frame=%d time=%s cycles=%s tick016A=%s pc=%s region=%s D0=%s D5=%s D6=%s A0=%s A3=%s",
			frames, machine_seconds(), cpu_cycles(), hex(tick_016a()), hex(pc), region,
			hex(reg("D0")), hex(reg("D5")), hex(reg("D6")), hex(reg("A0")), hex(reg("A3"))))
	end

	if frames >= stop_frame then
		manager.machine:exit()
	end
end, "macii_frame_probe")
