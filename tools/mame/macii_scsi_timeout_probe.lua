local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local hits = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "520") or 520
local max_hits = tonumber(os.getenv("MAME_MAX_PRINT") or "200") or 200
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local frame_interval = tonumber(os.getenv("MAME_FRAME_INTERVAL") or "0") or 0
local start_pc = tonumber(os.getenv("MAME_PC_START") or "40826CB4", 16) or 0x40826cb4
local end_pc = tonumber(os.getenv("MAME_PC_END") or "40826CD4", 16) or 0x40826cd4

local last_key = ""

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

local function log_state(kind, pc)
	if frames < min_frame or hits >= max_hits or pc < start_pc or pc > end_pc then
		return
	end

	local sp = reg("A7")
	if sp == 0 then
		sp = reg("SP")
	end
	local ret = u32(sp)
	local key = kind .. ":" .. hex(pc) .. ":" .. hex(sp) .. ":" .. hex(ret) .. ":" .. hex(reg("D1")) .. ":" .. hex(reg("D5"))
	if key == last_key and pc ~= 0x40826cca then
		return
	end
	last_key = key

	print(string.format(
		"MAME_SCSI_TIMEOUT_%s hit=%03d frame=%d pc=%s tick016A=%s D0=%s D1=%s D3=%s D4=%s D5=%s D6=%s A1=%s A3=%s SP=%s RET=%s W0D00=%04X W0DA6=%04X",
		kind, hits, frames, hex(pc), hex(u32(0x016a)), hex(reg("D0")),
		hex(reg("D1")), hex(reg("D3")), hex(reg("D4")), hex(reg("D5")),
		hex(reg("D6")), hex(reg("A1")), hex(reg("A3")), hex(sp), hex(ret),
		u16(0x0d00), u16(0x0da6)))
	hits = hits + 1
end

mem:install_read_tap(start_pc, end_pc | 3, "scsi_timeout_fetch", function(offset, data, mask)
	log_state("TAP", reg("CURPC"))
end)

if cpu.debug then
	local pcs = { 0x40826cb6, 0x40826cd4 }
	if os.getenv("MAME_SCSI_TIMEOUT_BP_MODE") == "loop" then
		pcs = { 0x40826cb6, 0x40826cc6, 0x40826cca, 0x40826cd4 }
	end
	for _, pc in ipairs(pcs) do
		cpu.debug:bpset(pc, nil,
			"printf \"MAME_SCSI_TIMEOUT_BP pc=%08X tick=%08X d0=%08X d1=%08X d5=%08X d6=%08X a3=%08X sp=%08X ret=%08X w0d00=%04X w0da6=%04X\\n\",pc,d@16a,d0,d1,d5,d6,a3,a7,d@a7,w@0d00,w@0da6; g")
	end
end

emu.register_frame_done(function()
	frames = frames + 1
	local pc = reg("CURPC")
	if frame_interval > 0 and frames >= min_frame and (frames % frame_interval) == 0 then
		log_state("FRAME", pc)
	elseif pc >= start_pc and pc <= end_pc then
		log_state("FRAME", pc)
	end

	if frames >= stop_frame then
		print(string.format(
			"MAME_SCSI_TIMEOUT_SUMMARY frames=%d hits=%d pc=%s tick016A=%s D0=%s D1=%s D5=%s D6=%s A3=%s W0D00=%04X W0DA6=%04X",
			frames, hits, hex(pc), hex(u32(0x016a)), hex(reg("D0")),
			hex(reg("D1")), hex(reg("D5")), hex(reg("D6")), hex(reg("A3")),
			u16(0x0d00), u16(0x0da6)))
		manager.machine:exit()
	end
end, "macii_scsi_timeout_probe")
