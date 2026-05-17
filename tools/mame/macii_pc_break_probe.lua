local cpu = manager.machine.devices[":maincpu"]
local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "330") or 330

local pcs = {
	0x40825558,
	0x4082559c,
	0x4080e97c,
	0x4080ec50,
	0x4080e23a,
	0x40821cba,
	0x408061f2,
	0x40826cc6,
}

if cpu.debug then
	for _, pc in ipairs(pcs) do
		cpu.debug:bpset(pc, nil, string.format(
			"printf \"MAME_BP pc=%%08X frame=%d tick=%%08X d0=%%08X d1=%%08X d5=%%08X d6=%%08X a0=%%08X a1=%%08X a3=%%08X a4=%%08X\\n\",pc,d@16a,d0,d1,d5,d6,a0,a1,a3,a4; g",
			frames))
	end
end

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		manager.machine:exit()
	end
end, "macii_pc_break_probe")
