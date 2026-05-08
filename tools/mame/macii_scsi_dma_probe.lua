local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local printed = 0
local reads = 0
local writes = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "900") or 900
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "800") or 800

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function region(addr)
	local low = addr & 0x000fffff
	if low >= 0x010000 and low <= 0x011fff then
		return "REG", ((low - 0x010000) >> 4) & 7
	end
	if low >= 0x006000 and low <= 0x006fff then
		return "DMA_R", -1
	end
	if low >= 0x012000 and low <= 0x013fff then
		return "DMA_RW", -1
	end
	return "OTHER", -1
end

local function log(kind, addr, data, mask)
	if printed >= max_print or frames < min_frame then
		return
	end
	local pc = cpu.state["CURPC"].value
	local name, reg = region(addr)
	print(string.format("MAME_SCSI_DMA_%s frame=%d pc=%s addr=%s region=%s reg=%d data=%s mask=%s",
		kind, frames, hex(pc), hex(addr), name, reg, hex(data, 8), hex(mask, 8)))
	printed = printed + 1
end

local function install_range(base, first, last, name)
	mem:install_read_tap(base + first, base + last, name .. "_r", function(offset, data, mask)
		reads = reads + 1
		log("R", offset, data, mask)
	end)
	mem:install_write_tap(base + first, base + last, name .. "_w", function(offset, data, mask)
		writes = writes + 1
		log("W", offset, data, mask)
	end)
end

for _, base in ipairs({ 0x50000000, 0x50f00000 }) do
	install_range(base, 0x006000, 0x006fff, "scsi_dma_r_" .. hex(base))
	install_range(base, 0x010000, 0x013fff, "scsi_regs_dma_" .. hex(base))
end

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format("MAME_SCSI_DMA_SUMMARY frames=%d reads=%d writes=%d printed=%d pc=%s",
			frames, reads, writes, printed, hex(cpu.state["CURPC"].value)))
		manager.machine:exit()
	end
end, "macii_scsi_dma_probe")
