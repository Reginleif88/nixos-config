-- Window rules

hl.window_rule({
  name  = "tile-obsidian",
  match = { class = "^(obsidian)$" },
  tile  = true,
})

hl.window_rule({
  name  = "fix-xwayland-drags",
  match = {
    class      = "^$",
    title      = "^$",
    xwayland   = true,
    float      = true,
    fullscreen = false,
    pin        = false,
  },
  no_focus = true,
})

hl.window_rule({
  name      = "moonlight-immediate",
  match     = { class = "^(moonlight-qt)$" },
  immediate = true,
})

hl.window_rule({
  name  = "move-hyprland-run",
  match = { class = "hyprland-run" },
  move  = { "20", "monitor_h-120" },
  float = true,
})

-- Layer rules

hl.layer_rule({
  name         = "swaync-control-center",
  match        = { namespace = "^(swaync-control-center)$" },
  blur         = true,
  ignore_alpha = 0,
  no_anim      = true,
})

hl.layer_rule({
  name         = "swaync-notifications",
  match        = { namespace = "^(swaync-notification-window)$" },
  blur         = true,
  ignore_alpha = 0,
  no_anim      = true,
})
