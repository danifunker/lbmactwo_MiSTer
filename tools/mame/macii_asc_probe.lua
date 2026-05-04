local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local last_pc = 0
local pc_hits = {}
local asc_reads = 0
local asc_writes = 0
local asc_test_reads = 0
local asc_test_writes = 0
local entered_asc = false
local exited_asc = false
local frames = 0

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

mem:install_read_tap(0x50014000, 0x50f15fff, "asc_probe_r", function(offset, data, mask)
	local pc = cpu.state["CURPC"].value
	local in_asc_test = pc >= 0x40805e00 and pc <= 0x40805fff
	if asc_reads < 64 or (in_asc_test and asc_test_reads < 260) then
		print(string.format("MAME_ASC_R pc=%s addr=%s data=%s mask=%s",
			hex(pc), hex(offset), hex(data, 8), hex(mask, 8)))
	end
	asc_reads = asc_reads + 1
	if in_asc_test then asc_test_reads = asc_test_reads + 1 end
end)

mem:install_write_tap(0x50014000, 0x50f15fff, "asc_probe_w", function(offset, data, mask)
	local pc = cpu.state["CURPC"].value
	local in_asc_test = pc >= 0x40805e00 and pc <= 0x40805fff
	if asc_writes < 96 or (in_asc_test and asc_test_writes < 180) then
		print(string.format("MAME_ASC_W pc=%s addr=%s data=%s mask=%s",
			hex(pc), hex(offset), hex(data, 8), hex(mask, 8)))
	end
	asc_writes = asc_writes + 1
	if in_asc_test then asc_test_writes = asc_test_writes + 1 end
end)

emu.register_frame_done(function()
	frames = frames + 1
	local pc = cpu.state["CURPC"].value
	if pc ~= last_pc then
		if pc == 0x40805e4a and not entered_asc then
			print("MAME_ASC_ENTER frame=" .. frames)
			entered_asc = true
		end
		if pc == 0x40805f60 and not exited_asc then
			print("MAME_ASC_EXIT_5F60 frame=" .. frames)
			exited_asc = true
		end
		if pc >= 0x40805e00 and pc <= 0x40805fff then
			pc_hits[pc] = (pc_hits[pc] or 0) + 1
		end
		last_pc = pc
	end

	if frames >= 1000 then
		print(string.format("MAME_SUMMARY entered=%s exited=%s asc_reads=%d asc_writes=%d",
			tostring(entered_asc), tostring(exited_asc), asc_reads, asc_writes))
		for pcaddr, count in pairs(pc_hits) do
			if count > 10 then
				print(string.format("MAME_PC_HIT pc=%s count=%d", hex(pcaddr), count))
			end
		end
		manager.machine:exit()
	end
end, "macii_asc_probe")
