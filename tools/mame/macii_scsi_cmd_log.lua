-- Log every 6/10/12-byte SCSI CDB sent via pseudo-DMA, plus the running PC at the
-- start of each command.  Used to compare with Verilator's "New command on target"
-- to find where the boot diverges.  CDB bytes are written word-at-a-time to
-- 0x50F12000-0x50F13FFF (DMA send) and 0x50F06000-0x50F06003 (single byte path).
-- Reset assembly on a "long" gap between bytes (>= 4 cycles).
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "1500") or 1500
local max_cmds  = tonumber(os.getenv("MAME_MAX_CMDS")  or "1000") or 1000
local cmd_count = 0

local cdb = {}
local cdb_pc = 0
local last_byte_time = 0

local function expected_len(op)
	if op < 0x20 then return 6
	elseif op < 0xA0 then return 10
	else return 12 end
end

local function emit_byte(b)
	local now = manager.machine.time:as_ticks(1000000)  -- 1MHz ticks
	if #cdb > 0 and (now - last_byte_time) > 100 then
		-- gap too big — discard partial
		cdb = {}
	end
	if #cdb == 0 then
		cdb_pc = cpu.state["CURPC"].value
	end
	last_byte_time = now
	cdb[#cdb + 1] = b
	local need = expected_len(cdb[1] or 0)
	if #cdb >= need then
		if cmd_count < max_cmds then
			local parts = {}
			for i = 1, #cdb do parts[i] = string.format("%02x", cdb[i]) end
			print(string.format("MAME_SCSI_CMD frame=%d pc=%08X cdb=%s",
				frames, cdb_pc, table.concat(parts, " ")))
			cmd_count = cmd_count + 1
		end
		cdb = {}
	end
end

local function tapw(lo, hi)
	mem:install_write_tap(lo, hi, "scsi_cmd_log", function(offset, data, mask)
		if mask == 0xff000000 then
			emit_byte((data >> 24) & 0xff)
		elseif mask == 0xffff0000 then
			emit_byte((data >> 24) & 0xff)
			emit_byte((data >> 16) & 0xff)
		elseif mask == 0xffffffff then
			emit_byte((data >> 24) & 0xff)
			emit_byte((data >> 16) & 0xff)
			emit_byte((data >> 8)  & 0xff)
			emit_byte( data        & 0xff)
		elseif mask == 0x000000ff then
			emit_byte(data & 0xff)
		else
			emit_byte((data >> 24) & 0xff)
		end
	end)
end

tapw(0x50f12000, 0x50f13fff)
tapw(0x50f06000, 0x50f06003)

emu.register_frame_done(function()
	frames = frames + 1
	if frames % 100 == 0 then
		print(string.format("MAME_FRAME progress frame=%d cmd_count=%d", frames, cmd_count))
	end
	if frames >= stop_frame then
		print(string.format("MAME_DONE frames=%d total_cmds=%d", frames, cmd_count))
		manager.machine:exit()
	end
end, "scsi_cmd_log")
