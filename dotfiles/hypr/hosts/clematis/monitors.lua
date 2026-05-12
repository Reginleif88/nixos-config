-- Headless wlroots backend: WLR_BACKENDS=headless creates no outputs by
-- default. We spawn one virtual output named HEADLESS-1 at session start,
-- then the monitor rule below configures its resolution and scale.
-- wayvnc captures whichever output is exposed via wlr-screencopy.

hl.monitor({ output = "HEADLESS-1", mode = "1920x1080@60", position = "0x0", scale = 1.0 })

hl.on("hyprland.start", function()
  hl.exec_cmd("hyprctl output create headless HEADLESS-1")
end)
