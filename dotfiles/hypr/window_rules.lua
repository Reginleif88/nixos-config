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

-- Boosteroid cloud-gaming PWA (google-chrome --class=boosteroid). `immediate`
-- allows tearing so the WebRTC stream presents with the lowest latency, same
-- as Moonlight. The launcher already starts it fullscreen.
hl.window_rule({
  name      = "boosteroid-immediate",
  match     = { class = "^(boosteroid)$" },
  immediate = true,
})

hl.window_rule({
  name  = "move-hyprland-run",
  match = { class = "hyprland-run" },
  move  = { "20", "monitor_h-120" },
  float = true,
})

-- Start Proton Mail minimized: park it on special:minimized the instant it
-- opens. `silent` sends it there without switching the view, so it never
-- flashes on screen. Replaces the old autostart `hl.timer(5000)` park, which
-- raced the window's first map and could miss it on a slow boot.
hl.window_rule({
  name      = "minimize-proton-mail",
  match     = { class = "^(proton-mail)$" },
  workspace = "special:minimized silent",
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
