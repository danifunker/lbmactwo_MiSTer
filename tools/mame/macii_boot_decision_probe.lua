local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "900") or 900
local max_hits = tonumber(os.getenv("MAME_MAX_PRINT") or "200") or 200
local hits = 0
local last_key = ""

local pcs = {
	0x408015ea,
	0x40801600,
	0x40807ca4,
	0x40807cb0,
	0x40807cc2,
	0x40807cdc,
	0x40807cf2,
	0x40807d18,
	0x40807d1c,
	0x408266a4,
	0x40826660,
	0x4082667a,
	0x4082669e,
	0x408061e4,
	0x408061f2,
	0x40806260,
	0x40806274,
	0x40806278,
	0x40806282,
	0x40806284,
	0x4082672a,
	0x40826756,
	0x4082675e,
	0x40826762,
	0x40826764,
	0x40826768,
	0x4082682c,
	0x40826832,
	0x40826850,
	0x40826870,
	0x40826874,
	0x408268cc,
	0x40826970,
	0x40826976,
	0x40826986,
	0x40826cb6,
	0x40826cd4,
}

if os.getenv("MAME_BOOT_DECISION_FLOPPY_MODE") == "1" then
	table.insert(pcs, 0x0082e80c)
	table.insert(pcs, 0x0082e950)
	table.insert(pcs, 0x0082e96e)
end

if os.getenv("MAME_BOOT_DECISION_WAIT_MODE") == "1" then
	table.insert(pcs, 0x40801652)
	table.insert(pcs, 0x40801656)
	table.insert(pcs, 0x40801658)
end

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

local function log_hit(kind, pc)
	if hits >= max_hits then
		return
	end
	if not ((pc >= 0x408061e4 and pc <= 0x40806284) or
	        (pc >= 0x40807ad4 and pc <= 0x40807d20) or
	        (pc >= 0x40826636 and pc <= 0x408266a2) or
	        (pc >= 0x408266a4 and pc <= 0x40826990) or
	        (pc >= 0x40826cb4 and pc <= 0x40826cd4)) then
		return
	end

	local sp = reg("A7")
	local drive_queue = u32(0x030a)
	local key = kind .. ":" .. hex(pc) .. ":" .. hex(u32(0x016a)) .. ":" ..
		hex(sp) .. ":" .. hex(reg("D5")) .. ":" .. hex(reg("A4"))
	if key == last_key then
		return
	end
	last_key = key

	print(string.format(
		"MAME_BOOT_DECISION_%s hit=%03d frame=%d pc=%s tick016A=%s D0=%s D1=%s D2=%s D3=%s D4=%s D5=%s D6=%s D7=%s A0=%s A1=%s A2=%s A3=%s A4=%s A6=%s A7=%s RET=%s EXCPC=%s SP00=%04X SP02=%04X SP04=%04X SP06=%04X SP08=%04X SP0A=%04X SP0C=%04X SP0E=%04X SP10=%04X SP12=%04X SP14=%04X SP16=%04X W09FA=%04X W09FC=%04X W09FE=%04X W0A00=%04X W0A02=%04X L0134=%s W017A=%04X B0B22=%02X B0B2E=%02X B0C2F=%02X W0D00=%04X W0DA6=%04X L08EE=%s L0D10=%s L0D14=%s L030A=%s Q_00=%s Q_06=%04X Q_08=%04X A4_60=%04X A4_61=%02X",
		kind, hits, frames, hex(pc), hex(u32(0x016a)), hex(reg("D0")),
		hex(reg("D1")), hex(reg("D2")), hex(reg("D3")), hex(reg("D4")),
		hex(reg("D5")), hex(reg("D6")), hex(reg("D7")), hex(reg("A0")),
		hex(reg("A1")), hex(reg("A2")), hex(reg("A3")), hex(reg("A4")),
		hex(reg("A6")), hex(sp), hex(u32(sp)), hex(u32(sp + 2)),
		u16(sp), u16(sp + 2), u16(sp + 4), u16(sp + 6),
		u16(sp + 8), u16(sp + 10), u16(sp + 12), u16(sp + 14),
		u16(sp + 16), u16(sp + 18), u16(sp + 20), u16(sp + 22),
		u16(0x09fa), u16(0x09fc), u16(0x09fe), u16(0x0a00), u16(0x0a02), hex(u32(0x0134)),
		u16(0x017a), u8(0x0b22), u8(0x0b2e), u8(0x0c2f), u16(0x0d00),
		u16(0x0da6), hex(u32(0x08ee)), hex(u32(0x0d10)), hex(u32(0x0d14)),
		hex(drive_queue), hex(u32(drive_queue)), u16(drive_queue + 0x06),
		u16(drive_queue + 0x08), u16(reg("A4") + 0x60), u8(reg("A4") + 0x61)))
	hits = hits + 1
end

local tap_ranges = {
	{ 0x408061e4, 0x40806284, "tm_service" },
	{ 0x40807ad4, 0x40807d20, "boot_scan" },
	{ 0x40826634, 0x408266a2, "scsi_pram_boot" },
	{ 0x408266a4, 0x40826990, "scsi_driver" },
	{ 0x40826cb4, 0x40826cd4, "scsi_timeout" },
}

for _, range in ipairs(tap_ranges) do
	mem:install_read_tap(range[1], range[2] | 3, range[3] .. "_fetch", function(offset, data, mask)
		log_hit("TAP", reg("CURPC"))
	end)
end

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		local sp = reg("A7")
		print(string.format(
			"MAME_BOOT_DECISION_SUMMARY frames=%d pc=%s tick016A=%s D0=%s D1=%s D5=%s D6=%s A3=%s A4=%s A6=%s A7=%s RET=%s EXCPC=%s SP00=%04X SP02=%04X SP04=%04X SP06=%04X SP08=%04X SP0A=%04X SP0C=%04X SP0E=%04X L0134=%s W0D00=%04X W0DA6=%04X",
			frames, hex(reg("CURPC")), hex(u32(0x016a)), hex(reg("D0")),
			hex(reg("D1")), hex(reg("D5")), hex(reg("D6")), hex(reg("A3")),
			hex(reg("A4")), hex(reg("A6")), hex(sp), hex(u32(sp)),
			hex(u32(sp + 2)), u16(sp), u16(sp + 2), u16(sp + 4),
			u16(sp + 6), u16(sp + 8), u16(sp + 10), u16(sp + 12),
			u16(sp + 14), hex(u32(0x0134)), u16(0x0d00), u16(0x0da6)))
		manager.machine:exit()
	end
end, "macii_boot_decision_probe")

if cpu.debug then
	for _, pc in ipairs(pcs) do
		cpu.debug:bpset(pc, nil,
			"printf \"MAME_BOOT_DECISION pc=%08X tick=%08X d0=%08X d1=%08X d2=%08X d3=%08X d4=%08X d5=%08X d6=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a5=%08X a6=%08X a7=%08X ret=%08X sp00=%04X sp02=%04X sp04=%04X sp06=%04X fp08=%04X fp0a=%04X fp0c=%04X fp0e=%04X fp14=%04X d6w00=%04X d6w02=%04X d6w04=%04X d6w06=%04X d6w08=%04X d6w0a=%04X w09fa=%04X w09fc=%04X w09fe=%04X w0a00=%04X w0a02=%04X l0134=%08X w017a=%04X b0c2f=%02X w0d00=%04X w0da6=%04X a4b61=%02X\\n\",pc,d@16a,d0,d1,d2,d3,d4,d5,d6,d7,a0,a1,a2,a3,a4,a5,a6,a7,d@a7,w@a7,w@(a7+2),w@(a7+4),w@(a7+6),w@(a6+0x08),w@(a6+0x0a),w@(a6+0x0c),w@(a6+0x0e),w@(a6+0x14),w@d6,w@(d6+2),w@(d6+4),w@(d6+6),w@(d6+8),w@(d6+10),w@9fa,w@9fc,w@9fe,w@a00,w@a02,d@134,w@17a,b@c2f,w@d00,w@da6,b@(a4+0x61); g")
	end
end
