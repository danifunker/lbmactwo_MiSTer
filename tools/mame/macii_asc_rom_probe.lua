local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "120") or 120
local max_bus = tonumber(os.getenv("MAME_ASC_BUS_LIMIT") or "256") or 256
local bus_count = 0
local last_pc = 0
local f5c_hits = 0

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function state(name)
	local entry = cpu.state[name]
	if entry and entry.value ~= nil then
		return hex(entry.value, 8)
	end
	return "????????"
end

local function dump_pc(pc)
	print(string.format(
		"MAME_ASC_PC frame=%d pc=%s d0=%s d1=%s d2=%s d3=%s d4=%s d7=%s a0=%s a3=%s a4=%s",
		frames, hex(pc), state("D0"), state("D1"), state("D2"),
		state("D3"), state("D4"), state("D7"),
		state("A0"), state("A3"), state("A4")))
end

local function interesting_pc(pc)
	return pc == 0x40805e4a or
	       pc == 0x40805f14 or
	       pc == 0x40805f28 or
	       pc == 0x40805f5c or
	       pc == 0x40805f60 or
	       pc == 0x40805f78
end

mem:install_read_tap(0x50f14000, 0x50f15fff, "asc_rom_probe_r", function(offset, data, mask)
	if bus_count < max_bus then
		local pc = cpu.state["CURPC"].value
		print(string.format("MAME_ASC_BUS frame=%d pc=%s rw=1 addr=%s data=%04X mask=%04X d0=%s d3=%s d7=%s a4=%s",
			frames, hex(pc), hex(offset), data or 0, mask or 0,
			state("D0"), state("D3"), state("D7"), state("A4")))
		bus_count = bus_count + 1
	end
end)

mem:install_write_tap(0x50f14000, 0x50f15fff, "asc_rom_probe_w", function(offset, data, mask)
	if bus_count < max_bus then
		local pc = cpu.state["CURPC"].value
		print(string.format("MAME_ASC_BUS frame=%d pc=%s rw=0 addr=%s data=%04X mask=%04X d0=%s d3=%s d7=%s a4=%s",
			frames, hex(pc), hex(offset), data or 0, mask or 0,
			state("D0"), state("D3"), state("D7"), state("A4")))
		bus_count = bus_count + 1
	end
end)

emu.register_frame_done(function()
	frames = frames + 1
	local pc = cpu.state["CURPC"].value
	if pc ~= last_pc then
		if interesting_pc(pc) then
			dump_pc(pc)
		end
		if pc == 0x40805f5c then
			f5c_hits = f5c_hits + 1
			if (f5c_hits % 256) == 1 then
				print(string.format("MAME_ASC_PROGRESS frame=%d f5c_hits=%d d3=%s d4=%s d7=%s a0=%s",
					frames, f5c_hits, state("D3"), state("D4"),
					state("D7"), state("A0")))
			end
		end
		last_pc = pc
	end

	if frames >= stop_frame then
		print(string.format("MAME_ASC_SUMMARY frames=%d bus=%d f5c_hits=%d pc=%s",
			frames, bus_count, f5c_hits, hex(pc)))
		manager.machine:exit()
	end
end, "macii_asc_rom_probe")
