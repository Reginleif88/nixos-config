-- Desktop: NVIDIA workarounds
hl.config({
  cursor = {
    no_hardware_cursors = true,
  },
})

-- Treat the local Windows VM as the desktop on workspace 2.
hl.window_rule({
  name = "windows-11-desktop",
  match = { class = "^(windows-11)$" },
  workspace = "2 silent",
  tile = true,
  fullscreen = true,
  fullscreen_state = "2 2",
  immediate = true,
})

-- NOTE: misc.vrr (variable refresh rate) is intentionally NOT set here.
-- The NVIDIA proprietary driver (Pascal/GTX 1080, 580.x) exposes no
-- DRM `vrr_capable` connector property under Wayland, so Hyprland's VRR
-- request silently no-ops.
