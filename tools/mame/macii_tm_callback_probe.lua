local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "900") or 900

local pcs = {
	0x408061e4,
	0x408061ee,
	0x408061f2,
	0x408061f4,
	0x408061f6,
	0x40806200,
	0x40806208,
	0x4080622c,
	0x40806486,
	0x4080649a,
	0x40807ad4,
	0x40807c78,
	0x40807ca4,
	0x40807cae,
	0x40826756,
	0x40826970,
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

local function print_state(prefix)
	local a1 = reg("A1")
	local a2 = reg("A2")
	local a4 = reg("A4")
	local sp = reg("A7")
	local q = u32(0x030a)
	print(string.format(
		"%s frame=%d pc=%s tick016A=%s D0=%s D1=%s D2=%s D3=%s D4=%s D5=%s D6=%s D7=%s A0=%s A1=%s A2=%s A3=%s A4=%s A7=%s RET=%s L08EE=%s L0D10=%s L0D14=%s L030A=%s Q_00=%s Q_06=%04X Q_08=%04X Q_0C=%s A1_00=%s A1_06=%04X A1_08=%04X A1_0A=%04X A1_0C=%s A2_00=%s A2_04=%04X A2_06=%04X A2_08=%04X A2_0A=%04X A4_00=%s A4_60=%04X A4_61=%02X W09FA=%04X W09FC=%04X W09FE=%04X B0B22=%02X B0B2E=%02X N2748=%s/%04X/%04X/%04X/%s N33C4=%s/%04X/%04X/%04X/%s N47A8=%s/%04X/%04X/%04X/%s",
		prefix, frames, hex(reg("CURPC")), hex(u32(0x016a)),
		hex(reg("D0")), hex(reg("D1")), hex(reg("D2")), hex(reg("D3")),
		hex(reg("D4")), hex(reg("D5")), hex(reg("D6")), hex(reg("D7")),
		hex(reg("A0")), hex(a1), hex(a2), hex(reg("A3")), hex(a4), hex(sp),
		hex(u32(sp)), hex(u32(0x08ee)), hex(u32(0x0d10)), hex(u32(0x0d14)),
		hex(q), hex(u32(q)), u16(q + 0x06), u16(q + 0x08), hex(u32(q + 0x0c)),
		hex(u32(a1)), u16(a1 + 0x06), u16(a1 + 0x08), u16(a1 + 0x0a),
		hex(u32(a1 + 0x0c)), hex(u32(a2)), u16(a2 + 0x04), u16(a2 + 0x06),
		u16(a2 + 0x08), u16(a2 + 0x0a), hex(u32(a4)), u16(a4 + 0x60),
		u8(a4 + 0x61), u16(0x09fa), u16(0x09fc), u16(0x09fe), u8(0x0b22),
		u8(0x0b2e), hex(u32(0x2748)), u16(0x274c), u16(0x274e),
		u16(0x2750), hex(u32(0x2754)), hex(u32(0x33c4)), u16(0x33c8),
		u16(0x33ca), u16(0x33cc), hex(u32(0x33d0)), hex(u32(0x47a8)),
		u16(0x47ac), u16(0x47ae), u16(0x47b0), hex(u32(0x47b4))))
end

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print_state("MAME_TM_CALLBACK_SUMMARY")
		manager.machine:exit()
	end
end, "macii_tm_callback_probe")

if cpu.debug then
	for _, pc in ipairs(pcs) do
		cpu.debug:bpset(pc, nil,
			"printf \"MAME_TM_CALLBACK pc=%08X tick=%08X d0=%08X d1=%08X d2=%08X d3=%08X d4=%08X d5=%08X d6=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X l08ee=%08X l0d10=%08X l0d14=%08X l030a=%08X q00=%08X q06=%04X q08=%04X q0c=%08X a1_00=%08X a1_06=%04X a1_08=%04X a1_0a=%04X a1_0c=%08X a2_00=%08X a2_04=%04X a2_06=%04X a2_08=%04X a2_0a=%04X a4_00=%08X a4_60=%04X a4_61=%02X w09fa=%04X w09fc=%04X w09fe=%04X b0b22=%02X b0b2e=%02X\\n\",pc,d@16a,d0,d1,d2,d3,d4,d5,d6,d7,a0,a1,a2,a3,a4,a7,d@a7,d@8ee,d@d10,d@d14,d@30a,d@(d@30a),w@(d@30a+6),w@(d@30a+8),d@(d@30a+0xc),d@a1,w@(a1+6),w@(a1+8),w@(a1+0xa),d@(a1+0xc),d@a2,w@(a2+4),w@(a2+6),w@(a2+8),w@(a2+0xa),d@a4,w@(a4+0x60),b@(a4+0x61),w@9fa,w@9fc,w@9fe,b@b22,b@b2e; g")
	end
end
