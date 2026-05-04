local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "1200") or 1200
local counts = {
	slot_r = 0, slot_w = 0,
	super_r = 0, super_w = 0,
	rom_r = 0, vram_r = 0, vram_w = 0,
	reg_w = 0, ramdac_r = 0, ramdac_w = 0,
	vbl_w = 0, other_r = 0, other_w = 0,
}

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

local function category(addr, rw)
	local local_addr = addr & 0x00ffffff
	local mb = (local_addr >> 20) & 0xf
	local low = local_addr & 0x0fffff

	if low < 0x080000 then
		return rw == "W" and "VRAM_W" or "VRAM_R"
	elseif low >= 0x080000 and low <= 0x08ffff then
		return rw == "W" and "REG_W" or "REG_R"
	elseif low >= 0x090000 and low <= 0x09ffff then
		return rw == "W" and "RAMDAC_W" or "RAMDAC_R"
	elseif low >= 0x0a0000 and low <= 0x0affff then
		return rw == "W" and "VBL_W" or "VBL_R"
	elseif mb == 0xf then
		return rw == "W" and "ROM_W" or "ROM_R"
	end
	return rw == "W" and "OTHER_W" or "OTHER_R"
end

local function should_print(cat, count)
	if cat == "ROM_R" then return count < 96 end
	if cat == "REG_W" then return count < 64 end
	if cat == "RAMDAC_W" then return count < 64 end
	if cat == "RAMDAC_R" then return count < 32 end
	if cat == "VBL_W" then return count < 32 end
	if cat == "VRAM_W" then return count < 32 end
	if cat == "VRAM_R" then return count < 16 end
	return count < 32
end

local function log_access(kind, addr, data, mask)
	local pc = cpu.state["CURPC"].value
	local cat = category(addr, kind)
	local key = string.lower(cat)
	counts[key] = (counts[key] or 0) + 1

	if should_print(cat, counts[key]) then
		print(string.format("MAME_VIDEO_%s frame=%d pc=%s addr=%s local=%06X data=%s mask=%s",
			cat, frames, hex(pc), hex(addr), addr & 0x00ffffff, hex(data, 8), hex(mask, 8)))
	end
end

mem:install_read_tap(0xfe000000, 0xfeffffff, "nbe_slot_video_r", function(offset, data, mask)
	counts.slot_r = counts.slot_r + 1
	log_access("R", offset, data, mask)
end)

mem:install_write_tap(0xfe000000, 0xfeffffff, "nbe_slot_video_w", function(offset, data, mask)
	counts.slot_w = counts.slot_w + 1
	log_access("W", offset, data, mask)
end)

mem:install_read_tap(0xe0000000, 0xefffffff, "nbe_super_video_r", function(offset, data, mask)
	counts.super_r = counts.super_r + 1
	log_access("R", offset, data, mask)
end)

mem:install_write_tap(0xe0000000, 0xefffffff, "nbe_super_video_w", function(offset, data, mask)
	counts.super_w = counts.super_w + 1
	log_access("W", offset, data, mask)
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		local pc = cpu.state["CURPC"].value
		print(string.format(
			"MAME_VIDEO_SUMMARY frames=%d pc=%s slot_r=%d slot_w=%d super_r=%d super_w=%d rom_r=%d vram_r=%d vram_w=%d reg_w=%d ramdac_r=%d ramdac_w=%d vbl_w=%d other_r=%d other_w=%d",
			frames, hex(pc), counts.slot_r, counts.slot_w, counts.super_r, counts.super_w,
			counts.rom_r, counts.vram_r, counts.vram_w, counts.reg_w, counts.ramdac_r,
			counts.ramdac_w, counts.vbl_w, counts.other_r, counts.other_w))
		manager.machine:exit()
	end
end, "macii_video_probe")
