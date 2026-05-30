local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local n = 0
local function hex(v,w) return string.format("%0"..tostring(w or 8).."X", v or 0) end
local function tap(lo,hi,kind)
  local fn = (kind=="r") and "install_read_tap" or "install_write_tap"
  mem[fn](mem, lo, hi, "disc_"..kind..hex(lo), function(offset,data,mask)
    if n < 120 then
      print(string.format("SCSIDISC %s addr=%s data=%s pc=%s", kind, hex(offset), hex(data&0xff,2), hex(cpu.state["CURPC"].value)))
      n = n + 1
    end
  end)
end
tap(0x50f00000,0x50f1ffff,"w")
tap(0x50f00000,0x50f1ffff,"r")
local frames=0
emu.register_frame_done(function()
  frames=frames+1
  if frames>=400 or n>=120 then print("SCSIDISC_DONE frames="..frames.." n="..n); manager.machine:exit() end
end,"disc")
