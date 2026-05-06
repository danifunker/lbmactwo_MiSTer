local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local hits = 0
local printed = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "360") or 360
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "200") or 200
local start_pc = tonumber(os.getenv("MAME_PC_START") or "0082E220", 16) or 0x0082e220
local end_pc = tonumber(os.getenv("MAME_PC_END") or "0082E2DF", 16) or 0x0082e2df
local last_pc = 0xffffffff

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
	return mem:read_u8(addr & 0xffffffff) or 0
end

local function u16(addr)
	return (((u8(addr) << 8) | u8(addr + 1)) & 0xffff)
end

local function u32(addr)
	return (((u16(addr) << 16) | u16(addr + 2)) & 0xffffffff)
end

local function dump_drive_state(label, pc)
	if frames < min_frame or printed >= max_print then
		return
	end

	local ptr0134 = u32(0x0134)
	local a1 = reg("A1")
	local d0w = reg("D0") & 0xffff
	local d1w = reg("D1") & 0xffff
	local d3w = reg("D3") & 0xffff
	local base = ptr0134

	print(string.format(
		"MAME_IWM_STATE %s hit=%03d frame=%d pc=%s D0=%s D1=%s D2=%s D3=%s A0=%s A1=%s L0134=%s " ..
		"baseW00=%04X b03=%02X b04=%02X b05=%02X b12=%02X b18=%02X b19=%02X w1A=%04X w40=%04X " ..
		"bA1D0=%02X bA1D1=%02X bA1D3=%02X bA1D1p3=%02X bA1D1p4=%02X",
		label, printed, frames, hex(pc), hex(reg("D0")), hex(reg("D1")),
		hex(reg("D2")), hex(reg("D3")), hex(reg("A0")), hex(a1), hex(ptr0134),
		u16(base + 0x00), u8(base + 0x03), u8(base + 0x04), u8(base + 0x05),
		u8(base + 0x12), u8(base + 0x18), u8(base + 0x19), u16(base + 0x1a),
		u16(base + 0x40), u8(a1 + d0w), u8(a1 + d1w), u8(a1 + d3w),
		u8(a1 + d1w + 3), u8(a1 + d1w + 4)))
	printed = printed + 1
end

local function fetch_probe(offset, data, mask)
	local pc = reg("CURPC")
	if pc < start_pc or pc > end_pc then
		return
	end
	hits = hits + 1
	if pc == last_pc then
		return
	end
	last_pc = pc
	dump_drive_state("FETCH", pc)
end

mem:install_read_tap(start_pc, end_pc, "iwm_state_fetch", fetch_probe)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format(
			"MAME_IWM_STATE_SUMMARY frames=%d hits=%d printed=%d pc=%s L0134=%s tick016A=%s",
			frames, hits, printed, hex(reg("CURPC")), hex(u32(0x0134)), hex(u32(0x016a))))
		manager.machine:exit()
	end
end, "macii_iwm_state_probe")
