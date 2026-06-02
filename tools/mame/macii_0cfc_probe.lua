-- Track every write to $0CFC (the WLSC warm-start flag) and surrounding bytes
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "500") or 500
local p_last = 0
local p_log_cnt = 0

local function hex(v, w) return string.format("%0" .. tostring(w or 8) .. "X", v or 0) end

emu.register_periodic(function()
	if p_log_cnt >= 80 then return end
	local b0 = mem:read_u8(0x0CFC)
	local b1 = mem:read_u8(0x0CFD)
	local b2 = mem:read_u8(0x0CFE)
	local b3 = mem:read_u8(0x0CFF)
	local v = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
	if v ~= p_last then
		print(string.format("MAME_0CFC_CHG pc=%08X prev=%08X curr=%08X frame=%d",
			cpu.state["CURPC"].value, p_last, v, frames))
		p_last = v
		p_log_cnt = p_log_cnt + 1
	end
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames % 50 == 0 then
		local b0 = mem:read_u8(0x0CFC)
		local b1 = mem:read_u8(0x0CFD)
		local b2 = mem:read_u8(0x0CFE)
		local b3 = mem:read_u8(0x0CFF)
		print(string.format("MAME_0CFC frame=%d val=%02X%02X%02X%02X",
			frames, b0, b1, b2, b3))
	end
	if frames >= stop_frame then
		print(string.format("MAME_DONE frames=%d", frames))
		manager.machine:exit()
	end
end, "p0cfc")
