-- Tap any SCSI access to see what addresses are hit
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "1500") or 1500
local hits = 0

local function tap(lo, hi, kind)
	mem:install_read_tap(lo, hi, "scsi_any_r", function(offset, data, mask)
		if hits < 50 then
			print(string.format("MAME_R %s frame=%d pc=%08X addr=%08X data=%08X",
				kind, frames, cpu.state["CURPC"].value, offset, data))
			hits = hits + 1
		end
	end)
	mem:install_write_tap(lo, hi, "scsi_any_w", function(offset, data, mask)
		if hits < 50 then
			print(string.format("MAME_W %s frame=%d pc=%08X addr=%08X data=%08X",
				kind, frames, cpu.state["CURPC"].value, offset, data))
			hits = hits + 1
		end
	end)
end

-- Both 0x500xxxxx and the mirrored 0x50FxXXXX paths
tap(0x50010000, 0x50011fff, "scsi_reg_lo")
tap(0x50f10000, 0x50f11fff, "scsi_reg_hi")
tap(0x50012000, 0x50013fff, "scsi_drq_lo")
tap(0x50f12000, 0x50f13fff, "scsi_drq_hi")
tap(0x50006000, 0x50006063, "scsi_dma_lo")
tap(0x50f06000, 0x50f06063, "scsi_dma_hi")

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format("MAME_DONE frames=%d hits=%d", frames, hits))
		manager.machine:exit()
	end
end, "scsi_any")
