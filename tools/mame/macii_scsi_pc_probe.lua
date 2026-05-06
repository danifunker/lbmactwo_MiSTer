local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local printed = 0
local reads = 0
local writes = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "330") or 330
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "500") or 500
local min_frame = tonumber(os.getenv("MAME_MIN_FRAME") or "0") or 0
local pc_min = tonumber(os.getenv("MAME_PC_MIN") or "0x408268d0") or 0x408268d0
local pc_max = tonumber(os.getenv("MAME_PC_MAX") or "0x40826cd4") or 0x40826cd4

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function scsi_reg(addr)
	return ((addr - (addr & 0xff000000) - 0x010000) >> 4) & 0x07
end

local function log(kind, addr, data, mask)
	local pc = cpu.state["CURPC"].value
	if frames < min_frame or printed >= max_print or pc < pc_min or pc > pc_max then
		return
	end

	print(string.format("MAME_SCSI_PC_%s frame=%d pc=%s addr=%s reg=%d data=%s mask=%s",
		kind, frames, hex(pc), hex(addr), scsi_reg(addr), hex(data, 8), hex(mask, 8)))
	printed = printed + 1
end

local function install_scsi_taps(base, name)
	mem:install_read_tap(base, base + 0x1fff, name .. "_r", function(offset, data, mask)
		reads = reads + 1
		log("R", offset, data, mask)
	end)

	mem:install_write_tap(base, base + 0x1fff, name .. "_w", function(offset, data, mask)
		writes = writes + 1
		log("W", offset, data, mask)
	end)
end

install_scsi_taps(0x50010000, "scsi_pc_base")
install_scsi_taps(0x50f10000, "scsi_pc_mirror")

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		local pc = cpu.state["CURPC"].value
		print(string.format("MAME_SCSI_PC_SUMMARY frames=%d reads=%d writes=%d printed=%d pc=%s",
			frames, reads, writes, printed, hex(pc)))
		manager.machine:exit()
	end
end, "macii_scsi_pc_probe")
