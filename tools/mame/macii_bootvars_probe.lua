local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local interval = tonumber(os.getenv("MAME_FRAME_INTERVAL") or "40") or 40
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "360") or 360

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function reg(name)
	local entry = cpu.state[name]
	return entry and entry.value or 0
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

local function log(kind)
	local q = u32(0x030a)
	print(string.format(
		"MAME_BOOTVARS_%s frame=%d pc=%s tick016A=%s D0=%s D1=%s D5=%s D6=%s A2=%s A3=%s A4=%s W017A=%04X B0C2F=%02X W0D24=%04X W0D28=%04X W09FA=%04X W09FC=%04X W09FE=%04X W0A00=%04X W0A02=%04X L08EE=%s L0D10=%s L0D14=%s L030A=%s Q_00=%s Q_04=%04X Q_06=%04X Q_08=%04X Q_0A=%04X Q_0C=%s A2_00=%s A2_04=%04X A2_06=%04X A2_08=%04X A2_0A=%04X A4_00=%s A4_04=%04X A4_06=%04X A4_08=%04X A4_0A=%04X A4_10=%s A4_14=%04X A4_18=%s A4_1C=%04X A4_20=%s A4_60=%04X A4_61=%02X",
		kind, frames, hex(reg("CURPC")), hex(u32(0x016a)), hex(reg("D0")), hex(reg("D1")),
		hex(reg("D5")), hex(reg("D6")), hex(reg("A2")), hex(reg("A3")), hex(reg("A4")),
		u16(0x017a), u8(0x0c2f),
		u16(0x0d24), u16(0x0d28), u16(0x09fa), u16(0x09fc), u16(0x09fe),
		u16(0x0a00), u16(0x0a02), hex(u32(0x08ee)), hex(u32(0x0d10)),
		hex(u32(0x0d14)), hex(q), hex(u32(q)), u16(q + 0x04), u16(q + 0x06),
		u16(q + 0x08), u16(q + 0x0a), hex(u32(q + 0x0c)), hex(u32(reg("A2"))),
		u16(reg("A2") + 0x04), u16(reg("A2") + 0x06), u16(reg("A2") + 0x08),
		u16(reg("A2") + 0x0a), hex(u32(reg("A4"))), u16(reg("A4") + 0x04),
		u16(reg("A4") + 0x06), u16(reg("A4") + 0x08), u16(reg("A4") + 0x0a),
		hex(u32(reg("A4") + 0x10)), u16(reg("A4") + 0x14),
		hex(u32(reg("A4") + 0x18)), u16(reg("A4") + 0x1c),
		hex(u32(reg("A4") + 0x20)), u16(reg("A4") + 0x60), u8(reg("A4") + 0x61)))
end

emu.register_frame_done(function()
	frames = frames + 1
	if frames == 1 or (interval > 0 and (frames % interval) == 0) or frames >= stop_frame then
		log("FRAME")
	end
	if frames >= stop_frame then
		manager.machine:exit()
	end
end, "macii_bootvars_probe")
