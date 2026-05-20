local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "700") or 700
local printed = 0
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "120") or 120
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local mode = os.getenv("MAME_PC_TAP_MODE") or "rom"
local last_pc = 0xffffffff

local function hex(v)
	return string.format("%08X", v or 0)
end

local function reg(name)
	local entry = cpu.state[name]
	return entry and entry.value or 0
end

local function in_mode_pc(pc)
	if mode == "ramboot" then
		return pc >= 0x000fe000 and pc <= 0x000fffff
	end
	if mode == "ramboot_callers" then
		return (pc >= 0x40812f40 and pc <= 0x40812f8b)
			or (pc >= 0x40813360 and pc <= 0x40813393)
	end
	return (pc >= 0x4080dea4 and pc <= 0x4080dee7)
		or (pc >= 0x40812640 and pc <= 0x4081272b)
end

local function tap_fetch(offset, data, mask)
	local pc = reg("CURPC")
	if frames < min_frame or printed >= max_print or pc == last_pc or not in_mode_pc(pc) then
		return
	end
	last_pc = pc
	print(string.format(
		"MAME_PC_TAP frame=%d pc=%s op=%04X d0=%s d1=%s a0=%s a6=%s a7=%s",
		frames, hex(pc), data or 0, hex(reg("D0")), hex(reg("D1")),
		hex(reg("A0")), hex(reg("A6")), hex(reg("A7"))))
	printed = printed + 1
end

if mode == "ramboot" then
	mem:install_read_tap(0x000fe000, 0x000fffff, "pc_tap_ramboot", tap_fetch)
elseif mode == "ramboot_callers" then
	mem:install_read_tap(0x40812f40, 0x40812f8b, "pc_tap_ramboot_caller_12f", tap_fetch)
	mem:install_read_tap(0x40813360, 0x40813393, "pc_tap_ramboot_caller_133", tap_fetch)
else
	mem:install_read_tap(0x4080dea4, 0x4080dee7, "pc_tap_appzone", tap_fetch)
	mem:install_read_tap(0x40812640, 0x4081272b, "pc_tap_a996", tap_fetch)
end

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format("MAME_PC_TAP_SUMMARY frames=%d printed=%d pc=%s",
			frames, printed, hex(reg("CURPC"))))
		manager.machine:exit()
	end
end, "macii_pc_tap_probe")
