local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "1000") or 1000

local pcs = {
	0x4080151c,
	0x40801520,
	0x40801524,
	0x40801528,
	0x4080152e,
	0x40801532,
	0x40801536,
	0x4080153a,
	0x40801540,
	0x40801544,
	0x4080154a,
	0x40801550,
	0x40801556,
	0x40801666,
	0x408016d6,
	0x408016f4,
	0x40801700,
	0x40801714,
	0x40801724,
	0x40801742,
	0x4080174e,
	0x4080176e,
	0x4080178a,
	0x408017cc,
	0x408061fa,
	0x0082e7fe,
	0x0082e950,
	0x0082e96e,
}

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function reg(name)
	local entry = cpu.state[name]
	if entry == nil then
		return 0
	end
	return entry.value or 0
end

local function u8(addr)
	return mem:read_u8(addr) or 0
end

local function u16(addr)
	return (((u8(addr) << 8) | u8(addr + 1)) & 0xffff)
end

local function u32(addr)
	return (((u16(addr) << 16) | u16(addr + 2)) & 0xffffffff)
end

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		local a2 = reg("A2")
		print(string.format(
			"MAME_QUEUE_SUMMARY frames=%d pc=%s tick016A=%s q030A=%s A2=%s A2_00=%s A2_04=%04X A2_06=%04X A2_08=%04X A2_0A=%04X D0=%s D4=%s D5=%s D6=%s D7=%s",
			frames, hex(reg("CURPC")), hex(u32(0x016a)), hex(u32(0x030a)),
			hex(a2), hex(u32(a2)), u16(a2 + 4), u16(a2 + 6), u16(a2 + 8),
			u16(a2 + 10), hex(reg("D0")), hex(reg("D4")), hex(reg("D5")),
			hex(reg("D6")), hex(reg("D7"))))
		manager.machine:exit()
	end
end, "macii_queue_probe")

if cpu.debug then
	for _, pc in ipairs(pcs) do
		cpu.debug:bpset(pc, nil,
			"printf \"MAME_QUEUE pc=%08X tick=%08X d0=%08X d1=%08X d2=%08X d3=%08X d4=%08X d5=%08X d6=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a5=%08X a6=%08X a7=%08X ret=%08X q030A=%08X a2_00=%08X a2_04=%04X a2_06=%04X a2_08=%04X a2_0A=%04X w017A=%04X b0C2F=%02X w0B0E=%04X w0B34=%04X w0210=%04X\\n\",pc,d@16a,d0,d1,d2,d3,d4,d5,d6,d7,a0,a1,a2,a3,a4,a5,a6,a7,d@a7,d@30a,d@a2,w@(a2+4),w@(a2+6),w@(a2+8),w@(a2+10),w@17a,b@c2f,w@b0e,w@b34,w@210; g")
	end
end
