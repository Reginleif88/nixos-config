-- Stream-friendly tuning. Every effect here costs encoder bandwidth or
-- pipeline latency over a VNC-over-WebSocket capture, with no visual
-- benefit a remote browser viewer can perceive — so they're all off.

hl.config({
  cursor = {
    -- Headless wlroots has no hardware cursor plane; force software
    -- cursor so it always renders into the captured framebuffer.
    no_hardware_cursors = true,
  },
  decoration = {
    rounding = 0,
    blur = {
      enabled = false,
    },
    shadow = {
      enabled = false,
    },
  },
  animations = {
    enabled = false,
  },
  misc = {
    -- Variable refresh: skip redraws when nothing changes, cutting
    -- encoder work to ~zero on an idle session.
    vfr = true,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },
  render = {
    -- No real scanout on headless; explicit off avoids warning spam.
    direct_scanout = false,
  },
})
