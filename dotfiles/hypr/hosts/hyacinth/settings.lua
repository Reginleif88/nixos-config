-- Desktop: NVIDIA workarounds
hl.config({
  cursor = {
    no_hardware_cursors = true,
  },
})
-- NOTE: misc.vrr (variable refresh rate) is intentionally NOT set here.
-- The NVIDIA proprietary driver (Pascal/GTX 1080, 580.x) exposes no
-- DRM `vrr_capable` connector property under Wayland, so Hyprland's VRR
-- request silently no-ops.
