-- Stream-friendly tuning. Every effect here costs encoder bandwidth or
-- pipeline latency over a VNC-over-WebSocket capture, with no visual
-- benefit a remote browser viewer can perceive — so they're all off.

hl.config({
  cursor = {
    -- Force the cursor into the captured framebuffer so VNC clients always
    -- see it, independent of the virtual display's cursor-plane behavior.
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
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },
  render = {
    -- Remote capture benefits more from predictable compositing than direct
    -- scanout bypasses.
    direct_scanout = false,
  },
})
