-- Comparable-with-Verilator PC sampling for MAME.
-- Maintains a 512-entry PC ring identical to Verilator's bootmask_history,
-- then dumps at each MAME_DUMP_FRAMES checkpoint (comma-separated).  Output
-- format is line-compatible with Verilator's MULTI_PC_DUMP / MULTI_PC_TOP.
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local ring_size = 512
local ring = {}
local ring_pos = 0
local ring_count = 0
for i = 1, ring_size do ring[i] = 0 end

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "2000") or 2000
local dump_str  = os.getenv("MAME_DUMP_FRAMES") or "800,900,1000,1100,1200,1300,1400,1500"
local snap_str  = os.getenv("MAME_SNAP_FRAMES") or "1000,1500,2000"

local dump_at = {}
for f in string.gmatch(dump_str, "[^,]+") do dump_at[tonumber(f)] = true end
local snap_at = {}
for f in string.gmatch(snap_str, "[^,]+") do snap_at[tonumber(f)] = true end

local function hex(v, w) return string.format("%0" .. tostring(w or 8) .. "X", v or 0) end
local function u8(a)  return mem:read_u8(a) or 0 end
local function u16(a) return ((mem:read_u8(a) << 8) | mem:read_u8(a + 1)) & 0xffff end
local function u32(a) return ((u16(a) << 16) | u16(a + 2)) & 0xffffffff end

-- Sample PC many times per frame to fill the ring.  m68k CURPC is the
-- currently-executing PC at the point we read it; sample at high rate
-- to approximate Verilator's per-fetch capture.
emu.register_periodic(function()
	local pc = cpu.state["CURPC"].value
	ring_pos = (ring_pos % ring_size) + 1
	ring[ring_pos] = pc
	if ring_count < ring_size then ring_count = ring_count + 1 end
end)

local function dump_ring(target_frame, pc_now)
	local buckets = {}
	for i = 1, ring_count do
		local b = ring[i] & ~0x3F   -- 64-byte bucket
		buckets[b] = (buckets[b] or 0) + 1
	end
	local sorted = {}
	for b, c in pairs(buckets) do sorted[#sorted + 1] = { bucket = b, count = c } end
	table.sort(sorted, function(a, b) return a.count > b.count end)
	local best = sorted[1] or { bucket = 0, count = 0 }
	print(string.format(
		"MULTI_PC_DUMP target=%d frame=%d pc=%s dominant_bucket=%s count=%d/%d "
		.. "MBState=%02X $173=%02X $0D10=%s $0D14=%s $08EE=%s",
		target_frame, frames, hex(pc_now), hex(best.bucket), best.count, ring_count,
		u8(0x172), u8(0x173), hex(u32(0x0D10)), hex(u32(0x0D14)), hex(u32(0x08EE))))
	for k = 1, math.min(10, #sorted) do
		print(string.format("MULTI_PC_TOP target=%d rank=%d bucket=%s count=%d",
			target_frame, k - 1, hex(sorted[k].bucket), sorted[k].count))
	end
end

emu.register_frame_done(function()
	frames = frames + 1
	if dump_at[frames] then
		dump_ring(frames, cpu.state["CURPC"].value)
	end
	if snap_at[frames] then
		manager.machine.video:snapshot()
		print(string.format("MAME_SNAP frame=%d taken", frames))
	end
	if frames >= stop_frame then
		print(string.format("MAME_DONE frames=%d", frames))
		manager.machine:exit()
	end
end, "pc_compare")
