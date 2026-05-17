local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local reads = 0
local writes = 0
local pc_hits = 0
local printed = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "160") or 160
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "800") or 800

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function state(name)
	local entry = cpu.state[name]
	if entry and entry.value ~= nil then
		return entry.value
	end
	return 0
end

local function in_watch_pc(pc)
	return (pc >= 0x40806d00 and pc <= 0x40806eff) or
	       (pc >= 0x4080dd00 and pc <= 0x4080deff)
end

local function via_reg(addr)
	return (addr >> 8) & 0xf
end

local function log_access(kind, addr, data, mask)
	local pc = state("CURPC")
	local watched = in_watch_pc(pc)
	if printed < 80 or watched or via_reg(addr) == 0x0 or via_reg(addr) == 0xa or via_reg(addr) == 0xb or via_reg(addr) == 0xd then
		if printed < max_print then
			print(string.format(
				"MAME_VIA_ADB_%s frame=%d pc=%s reg=%X addr=%s data=%s mask=%s d0=%s d1=%s d2=%s a0=%s",
				kind, frames, hex(pc), via_reg(addr), hex(addr), hex(data, 8), hex(mask, 8),
				hex(state("D0")), hex(state("D1")), hex(state("D2")), hex(state("A0"))))
			printed = printed + 1
		end
	end
	if watched then
		pc_hits = pc_hits + 1
	end
end

mem:install_read_tap(0x50000000, 0x50f01fff, "via_adb_probe_r", function(offset, data, mask)
	reads = reads + 1
	log_access("R", offset, data, mask)
end)

mem:install_write_tap(0x50000000, 0x50f01fff, "via_adb_probe_w", function(offset, data, mask)
	writes = writes + 1
	log_access("W", offset, data, mask)
end)

emu.register_frame_done(function()
	frames = frames + 1
	local pc = state("CURPC")
	if in_watch_pc(pc) and printed < max_print then
		print(string.format("MAME_VIA_ADB_PC frame=%d pc=%s d0=%s d1=%s d2=%s a0=%s",
			frames, hex(pc), hex(state("D0")), hex(state("D1")), hex(state("D2")), hex(state("A0"))))
		printed = printed + 1
	end

	if frames >= stop_frame then
		print(string.format("MAME_VIA_ADB_SUMMARY frames=%d reads=%d writes=%d pc_hits=%d pc=%s printed=%d",
			frames, reads, writes, pc_hits, hex(pc), printed))
		manager.machine:exit()
	end
end, "macii_via_adb_probe")
