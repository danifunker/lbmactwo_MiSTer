-- Track every write to $0CB0 word, $0CB4 long (ROM pointer), $0CB8 long
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "500") or 500
local p_last_cb0 = 0
local p_last_cb4 = 0
local p_last_cb8 = 0
local p_log_cnt = 0

local function hex(v, w) return string.format("%0" .. tostring(w or 8) .. "X", v or 0) end

-- Tap all writes to a wide range to figure out what's hitting $0CB0 area
local wr_count = 0
mem:install_write_tap(0x0000, 0x0FFF, "wr_cb0", function(offset, data, mask)
	if wr_count < 30 and offset >= 0x0CB0 and offset <= 0x0CBF then
		print(string.format("MAME_W_CB0 frame=%d pc=%08X addr=%08X data=%08X mask=%08X",
			frames, cpu.state["CURPC"].value, offset, data, mask))
		wr_count = wr_count + 1
	end
end)

emu.register_periodic(function()
	if p_log_cnt >= 100 then return end
	local cb0 = ((mem:read_u8(0x0CB0) << 8) | mem:read_u8(0x0CB1)) & 0xffff
	local cb4_h = ((mem:read_u8(0x0CB4) << 8) | mem:read_u8(0x0CB5)) & 0xffff
	local cb4_l = ((mem:read_u8(0x0CB6) << 8) | mem:read_u8(0x0CB7)) & 0xffff
	local cb4 = ((cb4_h << 16) | cb4_l) & 0xffffffff
	local cb8_h = ((mem:read_u8(0x0CB8) << 8) | mem:read_u8(0x0CB9)) & 0xffff
	local cb8_l = ((mem:read_u8(0x0CBA) << 8) | mem:read_u8(0x0CBB)) & 0xffff
	local cb8 = ((cb8_h << 16) | cb8_l) & 0xffffffff
	if cb0 ~= p_last_cb0 then
		print(string.format("MAME_0CB0_CHG pc=%08X prev=%04X curr=%04X frame=%d",
			cpu.state["CURPC"].value, p_last_cb0, cb0, frames))
		p_last_cb0 = cb0
		p_log_cnt = p_log_cnt + 1
	end
	if cb4 ~= p_last_cb4 then
		print(string.format("MAME_0CB4_CHG pc=%08X prev=%08X curr=%08X frame=%d",
			cpu.state["CURPC"].value, p_last_cb4, cb4, frames))
		p_last_cb4 = cb4
		p_log_cnt = p_log_cnt + 1
	end
	if cb8 ~= p_last_cb8 then
		print(string.format("MAME_0CB8_CHG pc=%08X prev=%08X curr=%08X frame=%d",
			cpu.state["CURPC"].value, p_last_cb8, cb8, frames))
		p_last_cb8 = cb8
		p_log_cnt = p_log_cnt + 1
	end
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format("MAME_DONE frames=%d", frames))
		manager.machine:exit()
	end
end, "p0cb0")
