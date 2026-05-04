local cpu = manager.machine.devices[":maincpu"]

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
		print(string.format("MAME_FRAME_REGION frame=%d time=%s cycles=%s pc=%s region=%s",
			frames, machine_seconds(), cpu_cycles(), hex(pc), region))
	end
	last_region = region

	if frames == 1 or (interval > 0 and (frames % interval) == 0) or frames >= stop_frame then
		print(string.format("MAME_FRAME frame=%d time=%s cycles=%s pc=%s region=%s",
			frames, machine_seconds(), cpu_cycles(), hex(pc), region))
	end

	if frames >= stop_frame then
		manager.machine:exit()
	end
end, "macii_frame_probe")
