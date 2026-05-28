-- CDB goes via pseudo-DMA send (scsi_drq_w): 0x50012000-0x50013fff (mirror
-- 0x50f12000) and 0x50006000 (mirror 0x50f06000). 32-bit writes, SCSI bytes
-- high-first (data>>24, >>16, >>8, &0xff per mem_mask). Log raw data+mask.
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local frames = 0
local stop_frame = tonumber(os.getenv("MAME_STOP_FRAME") or "1500") or 1500
local function emit(data,mask)
  -- emit SCSI bytes in order per mem_mask (matches scsi_drq_w)
  if mask == 0xff000000 then
    print(string.format("DRQB %d", (data>>24)&0xff))
  elseif mask == 0xffff0000 then
    print(string.format("DRQB %d", (data>>24)&0xff)); print(string.format("DRQB %d", (data>>16)&0xff))
  elseif mask == 0xffffffff then
    print(string.format("DRQB %d", (data>>24)&0xff)); print(string.format("DRQB %d", (data>>16)&0xff))
    print(string.format("DRQB %d", (data>>8)&0xff));  print(string.format("DRQB %d", data&0xff))
  else
    print(string.format("DRQB %d", (data>>24)&0xff))
  end
end
local function tapw(lo,hi)
  mem:install_write_tap(lo,hi,"drqw", function(offset,data,mask) emit(data,mask) end)
end
tapw(0x50f12000,0x50f13fff)
tapw(0x50f06000,0x50f06003)
emu.register_frame_done(function()
  frames = frames + 1
  if frames >= stop_frame then print("DRQ_DONE frames="..frames); manager.machine:exit() end
end,"cdb")
