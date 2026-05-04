local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local hits = 0

local function hex(v, w)
	return string.format("%0" .. tostring(w or 8) .. "X", v or 0)
end

mem:install_read_tap(0x40801df8, 0x40801e33, "magic_rom", function(offset, data, mask)
	local pc = cpu.state["CURPC"].value
	if pc >= 0x40801df8 and pc <= 0x40801e33 then
		hits = hits + 1
		if hits < 100 then
			print(string.format("MAME_MAGIC_ROM frame=%d pc=%s addr=%s data=%s mask=%s",
				frames, hex(pc), hex(offset), hex(data, 8), hex(mask, 8)))
		end
	end
end)

mem:install_read_tap(0x00000db0, 0x00000db3, "magic_low_r", function(offset, data, mask)
	print(string.format("MAME_MAGIC_LOW_R frame=%d pc=%s addr=%s data=%s mask=%s",
		frames, hex(cpu.state["CURPC"].value), hex(offset), hex(data, 8), hex(mask, 8)))
end)

mem:install_write_tap(0x00000db0, 0x00000db3, "magic_low_w", function(offset, data, mask)
	print(string.format("MAME_MAGIC_LOW_W frame=%d pc=%s addr=%s data=%s mask=%s",
		frames, hex(cpu.state["CURPC"].value), hex(offset), hex(data, 8), hex(mask, 8)))
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= 120 then
		print(string.format("MAME_MAGIC_SUMMARY frames=%d hits=%d pc=%s",
			frames, hits, hex(cpu.state["CURPC"].value)))
		manager.machine:exit()
	end
end, "macii_magic_probe")
