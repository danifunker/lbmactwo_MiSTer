local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local reads = 0
local writes = 0
local printed = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "300") or 300
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "5000") or 5000

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function iwm_reg(addr)
	return (addr >> 8) & 0x0f
end

local function log(kind, addr, data, mask)
	if printed >= max_print then
		return
	end

	local pc = cpu.state["CURPC"].value
	print(string.format("MAME_IWM_%s frame=%d pc=%s addr=%s reg=%X data=%s mask=%s",
		kind, frames, hex(pc), hex(addr), iwm_reg(addr), hex(data, 8), hex(mask, 8)))
	printed = printed + 1
end

local function install_iwm_taps(base, name)
	mem:install_read_tap(base, base + 0x1fff, name .. "_r", function(offset, data, mask)
		reads = reads + 1
		log("R", offset, data, mask)
	end)

	mem:install_write_tap(base, base + 0x1fff, name .. "_w", function(offset, data, mask)
		writes = writes + 1
		log("W", offset, data, mask)
	end)
end

install_iwm_taps(0x50016000, "iwm_probe_base")
install_iwm_taps(0x50f16000, "iwm_probe_mirror")

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		local pc = cpu.state["CURPC"].value
		print(string.format("MAME_IWM_SUMMARY frames=%d reads=%d writes=%d printed=%d pc=%s",
			frames, reads, writes, printed, hex(pc)))
		manager.machine:exit()
	end
end, "macii_iwm_probe")
