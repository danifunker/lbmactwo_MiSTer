local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local reads = 0
local writes = 0
local adb_pc_hits = 0
local adb_prints = 0

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function in_adb(pc)
	return pc >= 0x4080dd00 and pc <= 0x4080deff
end

local function log(kind, addr, data, mask)
	local pc = cpu.state["CURPC"].value
	local count = (kind == "R") and reads or writes
	local adb = in_adb(pc)
	if count < 128 or (adb and adb_prints < 256) then
		print(string.format("MAME_VIA_%s frame=%d pc=%s addr=%s local=%06X data=%s mask=%s",
			kind, frames, hex(pc), hex(addr), addr & 0x00ffffff, hex(data, 8), hex(mask, 8)))
	end
	if adb then
		adb_pc_hits = adb_pc_hits + 1
		adb_prints = adb_prints + 1
	end
end

mem:install_read_tap(0x50000000, 0x50f01fff, "via_probe_r", function(offset, data, mask)
	reads = reads + 1
	log("R", offset, data, mask)
end)

mem:install_write_tap(0x50000000, 0x50f01fff, "via_probe_w", function(offset, data, mask)
	writes = writes + 1
	log("W", offset, data, mask)
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= 1200 then
		local pc = cpu.state["CURPC"].value
		print(string.format("MAME_VIA_SUMMARY frames=%d reads=%d writes=%d adb_pc_hits=%d pc=%s",
			frames, reads, writes, adb_pc_hits, hex(pc)))
		manager.machine:exit()
	end
end, "macii_via_probe")
