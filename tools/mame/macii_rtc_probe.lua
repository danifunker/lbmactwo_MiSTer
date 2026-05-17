local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "120") or 120
local max_print = tonumber(os.getenv("MAME_MAX_PRINT") or "200") or 200
local printed = 0

local rtc_ce = 1
local rtc_clk = 0
local rtc_dat = 0
local bit_count = 0
local byte_value = 0

local function hex(v, w)
	return string.format("%0" .. tostring(w or 2) .. "X", v or 0)
end

local function state(name)
	local entry = cpu.state[name]
	if entry and entry.value ~= nil then
		return entry.value
	end
	return 0
end

local function via_reg(addr)
	return (addr >> 8) & 0xf
end

local function log_byte(value)
	if printed < max_print then
		print(string.format("MAME_RTC_BYTE frame=%d pc=%s byte=%s bits=%d",
			frames, hex(state("CURPC"), 8), hex(value, 2), bit_count + 1))
		printed = printed + 1
	end
end

local function update_rtc_lines(data)
	local new_ce = (data >> 2) & 1
	local new_clk = (data >> 1) & 1
	local new_dat = data & 1

	if new_ce ~= rtc_ce then
		if printed < max_print then
			print(string.format("MAME_RTC_CE frame=%d pc=%s ce=%d",
				frames, hex(state("CURPC"), 8), new_ce))
			printed = printed + 1
		end
		bit_count = 0
		byte_value = 0
	end

	if rtc_ce == 0 and new_ce == 0 and rtc_clk == 1 and new_clk == 0 then
		byte_value = ((byte_value << 1) | new_dat) & 0xff
		if bit_count == 7 then
			log_byte(byte_value)
			bit_count = 0
			byte_value = 0
		else
			bit_count = bit_count + 1
		end
	end

	rtc_ce = new_ce
	rtc_clk = new_clk
	rtc_dat = new_dat
end

mem:install_write_tap(0x50000000, 0x50f01fff, "rtc_probe_w", function(offset, data, mask)
	if via_reg(offset) == 0 then
		local byte = (data >> 24) & 0xff
		update_rtc_lines(byte)
	end
end)

emu.register_frame_done(function()
	frames = frames + 1
	if frames >= stop_frame then
		print(string.format("MAME_RTC_SUMMARY frames=%d printed=%d pc=%s",
			frames, printed, hex(state("CURPC"), 8)))
		manager.machine:exit()
	end
end, "macii_rtc_probe")
