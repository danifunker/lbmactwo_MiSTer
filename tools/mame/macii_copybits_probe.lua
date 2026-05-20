local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "1300") or 1300

local function u16(addr)
	return (((mem:read_u8(addr) or 0) << 8) | (mem:read_u8(addr + 1) or 0)) & 0xffff
end

local function tick_016a()
	return ((u16(0x016a) << 16) | u16(0x016c)) & 0xffffffff
end

local breakpoints = {
	0x001fe69c,
	0x001fe6a0,
	0x001fe6b6,
	0x001fe6ba,
	0x001fe6bc,
	0x001fe6c4,
	0x001fe6c8,
	0x001fe6cc,
	0x000fefc0,
	0x000fefda,
	0x000fefea,
	0x000feff2,
	0x4080deac,
	0x4080dede,
	0x4080dee0,
	0x000124d0,
	0x00017cbe,
	0x00017ccc,
	0x00017cce,
	0x00017cd0,
	0x408018be,
	0x40802120,
}

local function hex(v)
	return string.format("%08X", v or 0)
end

if cpu.debug then
	for _, pc in ipairs(breakpoints) do
		cpu.debug:bpset(pc, nil,
			"logerror \"MAME_COPYBITS pc=%08X tick=%08X d0=%08X d1=%08X d2=%08X d7=%08X a0=%08X a1=%08X a2=%08X a5=%08X a7=%08X sp0=%04X sp2=%04X sp4=%08X sp8=%08X dserr=%04X savedpc=%08X\\n\",pc,d@16a,d0,d1,d2,d7,a0,a1,a2,a5,a7,w@a7,w@(a7+2),d@(a7+4),d@(a7+8),w@af0,d@c70; printf \"MAME_COPYBITS pc=%08X tick=%08X d0=%08X d1=%08X d2=%08X d7=%08X a0=%08X a1=%08X a2=%08X a5=%08X a7=%08X sp0=%04X sp2=%04X sp4=%08X sp8=%08X dserr=%04X savedpc=%08X\\n\",pc,d@16a,d0,d1,d2,d7,a0,a1,a2,a5,a7,w@a7,w@(a7+2),d@(a7+4),d@(a7+8),w@af0,d@c70; g")
	end
else
	print("MAME_COPYBITS no debugger API")
end

emu.register_frame_done(function()
	frames = frames + 1
	if frames == 1 or (frames % 100) == 0 then
		print(string.format("MAME_COPYBITS_FRAME frame=%d tick=%s pc=%s dserr=%04X savedpc=%s",
			frames, hex(tick_016a()), hex(cpu.state["CURPC"].value), u16(0x0af0), hex((u16(0x0c70) << 16) | u16(0x0c72))))
	end

	if frames >= stop_frame then
		manager.machine:exit()
	end
end, "macii_copybits_probe")
