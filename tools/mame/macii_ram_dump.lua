-- Dump several RAM regions at specified frames so we can diff against
-- Verilator's RAM_HEX output and find the first diverging byte.
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "600") or 600
local dump_str  = os.getenv("MAME_DUMP_FRAMES") or "300,400,450,500"
local dump_at = {}
for f in string.gmatch(dump_str, "[^,]+") do dump_at[tonumber(f)] = true end

-- Regions: { name, base_addr, length }.  Full low-RAM sweep so we catch
-- the divergent bytes regardless of where they live.
local regions = {
	{ "low128K", 0x0000, 0x20000 },   -- 0-128KB so we catch System code at ~0x12000
}

local function dump_region(target_frame, name, base, len)
	for ofs = 0, len - 1, 16 do
		local b = {}
		for k = 0, 15 do
			b[k+1] = string.format("%02X", mem:read_u8(base + ofs + k))
		end
		print(string.format("RAM_HEX target=%d %s %08X %s",
			target_frame, name, base + ofs, table.concat(b, " ")))
	end
end

emu.register_frame_done(function()
	frames = frames + 1
	if dump_at[frames] then
		for _, r in ipairs(regions) do
			dump_region(frames, r[1], r[2], r[3])
		end
		print(string.format("RAM_HEX_DONE target=%d", frames))
	end
	if frames >= stop_frame then
		print("MAME_DONE frames=" .. frames)
		manager.machine:exit()
	end
end, "ram_dump")
