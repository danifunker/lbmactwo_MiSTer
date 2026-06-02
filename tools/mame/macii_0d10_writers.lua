-- Track every write to $0D10 word + the writer's PC, stack-top return address
-- (the caller), and registers.  Used to identify the trap call sequence that
-- drives $0D10 from $2748 to $93A2 in MAME (and to whatever in Verilator).
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "700") or 700
local p_last = 0
local p_log_cnt = 0

local function hex(v, w) return string.format("%0" .. tostring(w or 8) .. "X", v or 0) end
local function reg(n) return cpu.state[n] and cpu.state[n].value or 0 end

local function ram_u16(a)
	return ((mem:read_u8(a) << 8) | mem:read_u8(a + 1)) & 0xffff
end
local function ram_u32(a)
	return ((ram_u16(a) << 16) | ram_u16(a + 2)) & 0xffffffff
end

emu.register_periodic(function()
	if p_log_cnt >= 50 then return end
	local v = ram_u32(0x0D10)
	if v ~= p_last then
		local sp = reg("SP")
		local ret = ram_u32(sp)  -- top of stack: usually return PC for current routine
		print(string.format("MAME_0D10_CHG frame=%d pc=%s prev=%08X curr=%08X "
		                    .. "SP=%s ret=%s A1=%s D0=%s D1=%s A0=%s",
			frames, hex(reg("CURPC")), p_last, v,
			hex(sp), hex(ret), hex(reg("A1")), hex(reg("D0")),
			hex(reg("D1")), hex(reg("A0"))))
		p_last = v
		p_log_cnt = p_log_cnt + 1
	end
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format("MAME_DONE frames=%d $0D10=%08X", frames, ram_u32(0x0D10)))
		manager.machine:exit()
	end
end, "p0d10")
