local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local printed = 0
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "240") or 240
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "340") or 340

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function log(kind, addr, data, mask)
	if printed >= max_print then
		return
	end
	local pc = cpu.state["CURPC"].value
	print(string.format("MAME_VIDEO_VBL_%s frame=%d pc=%s addr=%s local=%06X data=%s mask=%s",
		kind, frames, hex(pc), hex(addr), addr & 0x00ffffff, hex(data, 8), hex(mask, 8)))
	printed = printed + 1
end

local function install(base, name)
	mem:install_read_tap(base, base + 0xffff, name .. "_r", function(offset, data, mask)
		log("R", offset, data, mask)
	end)
	mem:install_write_tap(base, base + 0xffff, name .. "_w", function(offset, data, mask)
		log("W", offset, data, mask)
	end)
end

install(0xfe090000, "m2hires_ramdac_vbl")
install(0xfe0a0000, "m2hires_vbl_ctl")

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		local pc = cpu.state["CURPC"].value
		print(string.format("MAME_VIDEO_VBL_SUMMARY frames=%d pc=%s printed=%d",
			frames, hex(pc), printed))
		manager.machine:exit()
	end
end, "macii_video_vbl_probe")
