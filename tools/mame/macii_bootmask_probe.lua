local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "1200") or 1200
local frame_interval = tonumber(os.getenv("MAME_FRAME_INTERVAL") or "200") or 200
local max_taps = tonumber(os.getenv("MAME_MAX_PRINT") or "120") or 120
local tap_hits = 0
local last_tap_key = ""

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

local function print_state(kind)
	local sp = reg("A7")
	print(string.format(
		"MAME_BOOTMASK_%s frame=%d pc=%s tick016A=%s D0=%s D1=%s D2=%s D5=%s A1=%s A2=%s A7=%s RET=%s B0B22=%02X B0B2E=%02X W017A=%04X B0C2F=%02X L030A=%s",
		kind, frames, hex(reg("CURPC")), hex(u32(0x016a)), hex(reg("D0")),
		hex(reg("D1")), hex(reg("D2")), hex(reg("D5")), hex(reg("A1")),
		hex(reg("A2")), hex(sp), hex(u32(sp)), u8(0x0b22), u8(0x0b2e),
		u16(0x017a), u8(0x0c2f), hex(u32(0x030a))))
end

if cpu.debug then
	local pcs = {
		0x408016d6, 0x408016ee, 0x408016f2,
		0x40807ad4, 0x40807ae0, 0x40807ae8, 0x40807aec,
		0x40807af2, 0x40807af4, 0x40807af8,
		0x40807b08, 0x40807b22, 0x40807c78,
	}
	for _, pc in ipairs(pcs) do
		cpu.debug:bpset(pc, nil,
			"printf \"MAME_BOOTMASK_BP pc=%08X tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X a1=%08X a2=%08X a7=%08X ret=%08X b0b22=%02X b0b2e=%02X w017a=%04X b0c2f=%02X l030a=%08X\\n\",pc,d@16a,d0,d1,d2,d5,a1,a2,a7,d@a7,b@0b22,b@0b2e,w@017a,b@0c2f,d@030a; g")
	end
else
	print("MAME_BOOTMASK_WARN no cpu.debug; using frame summaries only")
end

local function maybe_tap(kind)
	if tap_hits >= max_taps then
		return
	end
	local pc = reg("CURPC")
	local in_wait_call = pc >= 0x408016d6 and pc <= 0x408016f2
	local in_bootmask = pc >= 0x40807ad4 and pc <= 0x40807c78
	if not in_wait_call and not in_bootmask then
		return
	end
	local key = kind .. ":" .. hex(pc) .. ":" .. hex(reg("A7")) .. ":" .. hex(reg("D0")) .. ":" .. hex(reg("D5"))
	if key == last_tap_key then
		return
	end
	last_tap_key = key
	tap_hits = tap_hits + 1
	print_state("TAP")
end

mem:install_read_tap(0x408016d4, 0x408016f7, "bootmask_wait_fetch", function(offset, data, mask)
	maybe_tap("wait")
end)

mem:install_read_tap(0x40807ad4, 0x40807c7f, "bootmask_fetch", function(offset, data, mask)
	maybe_tap("bootmask")
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames == 1 or (frame_interval > 0 and (frames % frame_interval) == 0) or frames >= stop_frame then
		print_state("FRAME")
	end
	if frames >= stop_frame then
		print_state("SUMMARY")
		manager.machine:exit()
	end
end, "macii_bootmask_probe")
