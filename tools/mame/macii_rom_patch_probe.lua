local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "260") or 260
local fetch_hits = 0
local mem_hits = 0
local max_hits = tonumber(os.getenv("MAME_MAX_PRINT") or "160") or 160

local pcs = {
	0x4080dc32,
	0x4080dc3a,
	0x4080dc3c,
	0x4080dc3e,
	0x4080dc4a,
	0x4080dc56,
	0x4080dc7e,
	0x4080dc80,
	0x4080dc84,
	0x4080dc88,
	0x4080dc8e,
}

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
	local a0 = reg("A0")
	local a1 = reg("A1")
	local a7 = reg("A7")
	print(string.format(
		"MAME_ROM_PATCH_%s frame=%d pc=%s d0=%s d1=%s a0=%s a1=%s a7=%s a0_00=%s a1_00=%s sp00=%04X sp02=%04X sp04=%04X sp06=%04X m01e4=%s m01e8=%s m01ec=%s m01f0=%s b0b22=%02X b0b2e=%02X",
		kind, frames, hex(reg("CURPC")), hex(reg("D0")), hex(reg("D1")), hex(a0),
		hex(a1), hex(a7), hex(u32(a0)), hex(u32(a1)), u16(a7), u16(a7 + 2),
		u16(a7 + 4), u16(a7 + 6), hex(u32(0x01e4)), hex(u32(0x01e8)),
		hex(u32(0x01ec)), hex(u32(0x01f0)), u8(0x0b22), u8(0x0b2e)))
end

local function log_mem(kind, addr, data, mask)
	if mem_hits >= max_hits then
		return
	end
	mem_hits = mem_hits + 1
	print(string.format(
		"MAME_ROM_PATCH_%s frame=%d pc=%s addr=%s data=%s mask=%s d0=%s d1=%s a0=%s a1=%s a7=%s sp00=%04X m01e4=%s m01e8=%s m01ec=%s m01f0=%s b0b22=%02X b0b2e=%02X",
		kind, frames, hex(reg("CURPC")), hex(addr), hex(data), hex(mask), hex(reg("D0")),
		hex(reg("D1")), hex(reg("A0")), hex(reg("A1")), hex(reg("A7")), u16(reg("A7")),
		hex(u32(0x01e4)), hex(u32(0x01e8)), hex(u32(0x01ec)), hex(u32(0x01f0)),
		u8(0x0b22), u8(0x0b2e)))
end

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		log("SUMMARY")
		manager.machine:exit()
	end
end, "macii_rom_patch_probe")

mem:install_read_tap(0x4080dc30, 0x4080dc93, "rom_patch_fetch", function(offset, data, mask)
	local pc = reg("CURPC")
	if pc >= 0x4080dc32 and pc <= 0x4080dc93 and fetch_hits < max_hits then
		fetch_hits = fetch_hits + 1
		log("FETCH")
	end
end)

mem:install_write_tap(0x000001e4, 0x000001ff, "rom_patch_stub_w", function(offset, data, mask)
	log_mem("STUB_W", offset, data, mask)
end)

mem:install_write_tap(0x00000b20, 0x00000b2f, "rom_patch_bootvars_w", function(offset, data, mask)
	log_mem("BOOTVAR_W", offset, data, mask)
end)

if cpu.debug then
	for _, pc in ipairs(pcs) do
		cpu.debug:bpset(pc, nil,
			string.format("printf \"MAME_ROM_PATCH_BP frame=%%d pc=%%08X d0=%%08X d1=%%08X a0=%%08X a1=%%08X a7=%%08X a0_00=%%08X a1_00=%%08X sp00=%%04X sp02=%%04X sp04=%%04X sp06=%%04X m01e4=%%08X m01e8=%%08X m01ec=%%08X m01f0=%%08X b0b22=%%02X b0b2e=%%02X\\n\",%d,pc,d0,d1,a0,a1,a7,d@a0,d@a1,w@a7,w@(a7+2),w@(a7+4),w@(a7+6),d@1e4,d@1e8,d@1ec,d@1f0,b@b22,b@b2e; g", frames))
	end
end
