local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "") or 90
local log_limit = tonumber(os.getenv("MAME_RAM_SIZE_LOG_LIMIT") or "") or 260
local log_count = 0
local via2_log_count = 0
local last_pc = 0
local last_trace_pc = 0xffffffff

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

local function u32(addr)
	local b0 = mem:read_u8(addr) or 0
	local b1 = mem:read_u8(addr + 1) or 0
	local b2 = mem:read_u8(addr + 2) or 0
	local b3 = mem:read_u8(addr + 3) or 0
	return (((((b0 << 8) | b1) << 8) | b2) << 8) | b3
end

local function in_ram_size(pc)
	return pc >= 0x40803944 and pc <= 0x408039ff
end

local function log_line(kind, addr, data, mask)
	if log_count >= log_limit then
		return
	end

	local pc = reg("CURPC")
	if not in_ram_size(pc) then
		return
	end

	log_count = log_count + 1
	print(string.format(
		"MAME_RAM_SIZE_%s[%03d] frame=%d pc=%s addr=%s data=%s mask=%s D0=%s D5=%s D6=%s A2=%s A3=%s",
		kind, log_count - 1, frames, hex(pc), hex(addr), hex(data, 8), hex(mask, 8),
		hex(reg("D0")), hex(reg("D5")), hex(reg("D6")), hex(reg("A2")), hex(reg("A3"))))
end

local function install_ram_watch(addr)
	mem:install_read_tap(addr, addr + 3, "ram_size_r_" .. hex(addr), function(offset, data, mask)
		log_line("RD", offset, data, mask)
	end)
	mem:install_write_tap(addr, addr + 3, "ram_size_w_" .. hex(addr), function(offset, data, mask)
		log_line("WR", offset, data, mask)
	end)
end

install_ram_watch(0)
local addr = 4
while addr <= 0x400000 do
	install_ram_watch(addr)
	addr = addr << 1
end

mem:install_read_tap(0x50f02000, 0x50f03fff, "ram_size_via2_r", function(offset, data, mask)
	log_line("VIA2_RD", offset, data, mask)
end)

mem:install_write_tap(0x50f02000, 0x50f03fff, "ram_size_via2_w", function(offset, data, mask)
	if via2_log_count < 80 then
		local pc = reg("CURPC")
		print(string.format("MAME_VIA2_W[%02d] frame=%d pc=%s addr=%s data=%s mask=%s D0=%s",
			via2_log_count, frames, hex(pc), hex(offset), hex(data, 8), hex(mask, 8), hex(reg("D0"))))
		via2_log_count = via2_log_count + 1
	end
	log_line("VIA2_WR", offset, data, mask)
end)

mem:install_read_tap(0x40803944, 0x408039ff, "ram_size_rom_trace", function(offset, data, mask)
	local pc = reg("CURPC")
	if pc == last_trace_pc or not in_ram_size(pc) or log_count >= log_limit then
		return
	end
	last_trace_pc = pc
	log_count = log_count + 1
	print(string.format(
		"MAME_RAM_SIZE_PC[%03d] frame=%d pc=%s D0=%s D5=%s D6=%s A2=%s A3=%s MEM0=%s MEM200000=%s",
		log_count - 1, frames, hex(pc), hex(reg("D0")), hex(reg("D5")), hex(reg("D6")),
		hex(reg("A2")), hex(reg("A3")), hex(u32(0)), hex(u32(0x200000))))
end)

emu.register_frame_done(function()
	frames = frames + 1

	local pc = reg("CURPC")
	if in_ram_size(pc) and pc ~= last_pc and log_count < log_limit then
		print(string.format("MAME_RAM_SIZE_PC frame=%d pc=%s D0=%s D5=%s D6=%s A2=%s A3=%s",
			frames, hex(pc), hex(reg("D0")), hex(reg("D5")), hex(reg("D6")), hex(reg("A2")), hex(reg("A3"))))
	end
	last_pc = pc

	if frames >= stop_frame then
		print(string.format("MAME_RAM_SIZE_SUMMARY frames=%d logs=%d pc=%s D0=%s D5=%s D6=%s A2=%s A3=%s",
			frames, log_count, hex(pc), hex(reg("D0")), hex(reg("D5")), hex(reg("D6")),
			hex(reg("A2")), hex(reg("A3"))))
		manager.machine:exit()
	end
end, "macii_ram_size_probe")
