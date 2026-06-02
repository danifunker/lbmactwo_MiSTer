-- Trace byte $260D (the address Verilator spins on at $40806DC0)
-- and surrounding bytes.  Log every time byte $260D changes.
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "500") or 500
local last_260d = -1
local last_24b0 = -1

local function hex(v, w) return string.format("%0" .. tostring(w or 8) .. "X", v or 0) end
local function u8(a) return mem:read_u8(a) or 0 end

-- Tap the WORD containing $260D ($260C-$260D).
mem:install_read_tap(0x260C, 0x260F, "rd260D", function(offset, data, mask)
	if (mask & 0xff) ~= 0 then  -- low byte touched
		print(string.format("MAME_R260D frame=%d pc=%08X data=%04X mask=%04X",
			frames, cpu.state["CURPC"].value, data & 0xffff, mask & 0xffff))
	end
end)

mem:install_write_tap(0x260C, 0x260F, "wr260D", function(offset, data, mask)
	if (mask & 0xff) ~= 0 then
		print(string.format("MAME_W260D frame=%d pc=%08X data=%04X mask=%04X",
			frames, cpu.state["CURPC"].value, data & 0xffff, mask & 0xffff))
	end
end)

-- All writes in the $2600-$26FF range, unfiltered (low volume — keep all)
local wr_count = 0
mem:install_write_tap(0x2600, 0x26FF, "wr_a3", function(offset, data, mask)
	if wr_count < 200 then
		print(string.format("MAME_W2600 frame=%d pc=%08X addr=%04X data=%08X mask=%08X",
			frames, cpu.state["CURPC"].value, offset, data, mask))
		wr_count = wr_count + 1
	end
end)

-- Periodically (very often) check byte $260D; when it changes, log the
-- current PC (best guess at the writer).  Use register_periodic at ~10kHz.
local p_last_260d = 0
local p_log_cnt = 0
emu.register_periodic(function()
	if p_log_cnt >= 80 then return end
	local v = mem:read_u8(0x260D) or 0
	if v ~= p_last_260d then
		print(string.format("MAME_260D_CHG pc=%08X prev=%02X curr=%02X frame=%d",
			cpu.state["CURPC"].value, p_last_260d, v, frames))
		p_last_260d = v
		p_log_cnt = p_log_cnt + 1
	end
end)

emu.register_frame_done(function()
	frames = frames + 1
	local v = u8(0x260D)
	local v2 = u8(0x24B0)
	if v ~= last_260d or v2 ~= last_24b0 or frames % 50 == 0 then
		print(string.format("MAME_BYTE frame=%d $260D=%02X $24B0=%02X $24B0=%02X %02X %02X %02X (around A3)",
			frames, v, v2, u8(0x24B0), u8(0x24B1), u8(0x24B2), u8(0x24B3)))
		last_260d = v
		last_24b0 = v2
	end
	if frames >= stop_frame then
		print(string.format("MAME_DONE frames=%d $260D=%02X", frames, u8(0x260D)))
		manager.machine:exit()
	end
end, "p260d")
