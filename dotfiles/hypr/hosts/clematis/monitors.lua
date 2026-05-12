-- Headless run: Hyprland 0.55+ (Aquamarine) creates a fallback output on
-- its own when no real monitors are present, but doesn't let us name or
-- size it. We add an explicit HEADLESS-1 at session start so the monitor
-- rule below can pin resolution and scale; wayvnc captures it via
-- wlr-screencopy.

hl.monitor({ output = "HEADLESS-1", mode = "1920x1080@60", position = "0x0", scale = 1.0 })

hl.on("hyprland.start", function()
  hl.exec_cmd("hyprctl output create headless HEADLESS-1")
end)
