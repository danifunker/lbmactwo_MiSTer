local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "180") or 180
local max_hits = tonumber(os.getenv("MAME_ASC_ENTRY_LIMIT") or "160") or 160
local hits = 0

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

local interesting = {
	[0x408000d0] = true,
	[0x40802cdc] = true,
	[0x40802ce2] = true,
	[0x40802ce4] = true,
	[0x40802cea] = true,
	[0x40802cee] = true,
	[0x40805e4a] = true,
	[0x40805e5c] = true,
	[0x40805e62] = true,
	[0x40805e66] = true,
	[0x40805e68] = true,
	[0x40805e6e] = true,
	[0x40805e70] = true,
	[0x40805f78] = true,
}

local function fetch_probe(offset, data, mask)
	if hits >= max_hits then
		return
	end
	local pc = cpu.state["CURPC"].value
	if interesting[pc] then
		print(string.format(
			"MAME_ASC_ENTRY frame=%d pc=%s data=%04X mask=%08X d0=%s d7=%s a0=%s a3=%s a4=%s a6=%s",
			frames, hex(pc), data or 0, mask or 0,
			state("D0"), state("D7"), state("A0"), state("A3"),
			state("A4"), state("A6")))
		hits = hits + 1
	end
end

mem:install_read_tap(0x408000c0, 0x408000df, "asc_entry_fetch_reset", fetch_probe)
mem:install_read_tap(0x40802cdc, 0x40802cf3, "asc_entry_fetch_late", fetch_probe)
mem:install_read_tap(0x40805e48, 0x40805e73, "asc_entry_fetch_entries", fetch_probe)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format("MAME_ASC_ENTRY_SUMMARY frames=%d hits=%d pc=%s",
			frames, hits, hex(cpu.state["CURPC"].value)))
		manager.machine:exit()
	end
end, "macii_asc_entry_probe")
