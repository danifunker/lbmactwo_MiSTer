local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local scc_reads = 0
local scc_writes = 0
local poll_hits = 0
local last_pc = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "") or 1200
local log_limit = tonumber(os.getenv("MAME_SCC_LOG_LIMIT") or "") or 128

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function in_poll(pc)
	return pc >= 0x40803280 and pc <= 0x40803310
end

mem:install_read_tap(0x50004000, 0x50f05fff, "scc_probe_r", function(offset, data, mask)
	local pc = cpu.state["CURPC"].value
	if scc_reads < log_limit or in_poll(pc) then
		print(string.format("MAME_SCC_R frame=%d pc=%s addr=%s data=%s mask=%s",
			frames, hex(pc), hex(offset), hex(data, 8), hex(mask, 8)))
	end
	scc_reads = scc_reads + 1
end)

mem:install_write_tap(0x50004000, 0x50f05fff, "scc_probe_w", function(offset, data, mask)
	local pc = cpu.state["CURPC"].value
	if scc_writes < log_limit or in_poll(pc) then
		print(string.format("MAME_SCC_W frame=%d pc=%s addr=%s data=%s mask=%s",
			frames, hex(pc), hex(offset), hex(data, 8), hex(mask, 8)))
	end
	scc_writes = scc_writes + 1
end)

emu.register_frame_done(function()
	frames = frames + 1
	local pc = cpu.state["CURPC"].value
	if pc ~= last_pc then
		if in_poll(pc) then
			poll_hits = poll_hits + 1
			if poll_hits <= 64 then
				print(string.format("MAME_POLL_PC frame=%d pc=%s", frames, hex(pc)))
			end
		end
		last_pc = pc
	end

	if frames >= stop_frame then
		print(string.format("MAME_SCC_SUMMARY frames=%d reads=%d writes=%d poll_hits=%d pc=%s",
			frames, scc_reads, scc_writes, poll_hits, hex(pc)))
		manager.machine:exit()
	end
end, "macii_scc_probe")
