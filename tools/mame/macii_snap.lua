local snapf = tonumber(os.getenv("MAME_SNAP_FRAME") or "3000")
local stopf = tonumber(os.getenv("MAME_STOP_FRAME") or "3100")
local frames = 0
emu.register_frame_done(function()
  frames = frames + 1
  if frames == snapf then manager.machine.video:snapshot(); print("SNAP frame="..frames) end
  if frames >= stopf then print("SNAP_DONE frame="..frames); manager.machine:exit() end
end, "snap")
