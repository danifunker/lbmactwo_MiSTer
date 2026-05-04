local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local reads = 0
local writes = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "500") or 500

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function interesting(pc, addr)
	return (pc >= 0x408268d0 and pc <= 0x40826920) or
		(addr == 0x50f10010) or
		(addr == 0x50f10020)
end

mem:install_read_tap(0x50010000, 0x50f11fff, "scsi_probe_r", function(offset, data, mask)
	local pc = cpu.state["CURPC"].value
	if reads < 160 and interesting(pc, offset) then
		local reg = ((offset - 0x50010000) >> 4) & 7
		print(string.format("MAME_SCSI_R frame=%d pc=%s addr=%s reg=%d data=%s mask=%s",
			frames, hex(pc), hex(offset), reg, hex(data, 8), hex(mask, 8)))
		reads = reads + 1
	end
end)

mem:install_write_tap(0x50010000, 0x50f11fff, "scsi_probe_w", function(offset, data, mask)
	local pc = cpu.state["CURPC"].value
	if writes < 160 and interesting(pc, offset) then
		local reg = ((offset - 0x50010000) >> 4) & 7
		print(string.format("MAME_SCSI_W frame=%d pc=%s addr=%s reg=%d data=%s mask=%s",
			frames, hex(pc), hex(offset), reg, hex(data, 8), hex(mask, 8)))
		writes = writes + 1
	end
end)

emu.register_frame_done(function()
	frames = frames + 1
	local pc = cpu.state["CURPC"].value
	if pc >= 0x408268d0 and pc <= 0x40826920 then
		print(string.format("MAME_SCSI_PC frame=%d pc=%s", frames, hex(pc)))
	end
	if frames >= stop_frame then
		print(string.format("MAME_SCSI_SUMMARY frame=%d reads=%d writes=%d pc=%s",
			frames, reads, writes, hex(pc)))
		manager.machine:exit()
	end
end, "macii_scsi_probe")
