local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "120") or 120
local hits = 0
local last_pc = -1

local watch = {
	[0x40805e4a] = true,
	[0x40805f14] = true,
	[0x40805f28] = true,
	[0x40805f5c] = true,
	[0x40805f60] = true,
	[0x40805f78] = true,
}

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

local function u8(addr)
	return mem:read_u8(addr) or 0
end

local function fnv_bank(base)
	local h = 0x811c9dc5
	for i = 0, 1023 do
		h = ((h ~ u8(base + i)) * 0x01000193) & 0xffffffff
	end
	return h
end

local function bytes16(base)
	local out = {}
	for i = 0, 15 do
		out[#out + 1] = string.format("%02X", u8(base + i))
	end
	return table.concat(out, "", 1, 4) .. "_" ..
	       table.concat(out, "", 5, 8) .. "_" ..
	       table.concat(out, "", 9, 12) .. "_" ..
	       table.concat(out, "", 13, 16)
end

local function snapshot(pc)
	hits = hits + 1
	if hits >= 32 and pc ~= 0x40805e4a and pc ~= 0x40805f14 and pc ~= 0x40805f78 and (hits & 0x7ff) ~= 0 then
		return
	end

	print(string.format(
		"MAME_ASC_STATE frame=%d hit=%d pc=%s d2=%s d3=%s d4=%s d7=%s a0=%s a3=%s mode=%02X ctl=%02X fifo_mode=%02X fifo_irq=?? wt=%02X vol=%02X clk=%02X hash_a=%s hash_b=%s a0_0f=%s b0_0f=%s",
		frames, hits, hex(pc),
		hex(state("D2")), hex(state("D3")), hex(state("D4")),
		hex(state("D7")), hex(state("A0")), hex(state("A3")),
		u8(0x50f14801), u8(0x50f14802), u8(0x50f14803),
		u8(0x50f14805), u8(0x50f14806),
		u8(0x50f14807),
		hex(fnv_bank(0x50f14000)), hex(fnv_bank(0x50f14400)),
		bytes16(0x50f14000), bytes16(0x50f14400)))
end

local function maybe_snapshot()
	local pc = cpu.state["CURPC"].value
	if pc ~= last_pc and watch[pc] then
		snapshot(pc)
	end
	last_pc = pc
end

mem:install_read_tap(0x40805e48, 0x40805f7f, "asc_state_pc_r", function(offset, data, mask)
	maybe_snapshot()
end)

emu.register_frame_done(function()
	frames = frames + 1
	maybe_snapshot()
	if frames >= stop_frame then
		print(string.format("MAME_ASC_STATE_SUMMARY frames=%d hits=%d pc=%s",
			frames, hits, hex(cpu.state["CURPC"].value)))
		manager.machine:exit()
	end
end, "macii_asc_state_probe")
