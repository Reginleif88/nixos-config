-- gruvbar plugin (Hyprland 0.55+ Lua-native).
--
-- Loads via `hl.plugin.load`; registers typed config values via the V2
-- API. Buttons are added through the plugin's own Lua function
-- `hl.plugin.gruvbar.add_button(table)` (registered by the plugin via
-- HyprlandAPI::addLuaFunction). This replaces the legacy `gruvbar-button`
-- keyword which has no V2 equivalent.
--
-- Note: this plugin is Lua-only. Under a legacy hyprland.conf,
-- `addLuaFunction` returns false and `hl.plugin.gruvbar` won't exist.

local pluginPath = require("gruvbar_path")
hl.plugin.load(pluginPath)

hl.config({
  plugin = {
    gruvbar = {
      bar_text_font = "Atkinson Hyperlegible",
    },
  },
})

-- Buttons are registered at top level so they're re-created on every
-- config reload (onPreConfigReload clears them, then this file re-runs).
hl.plugin.gruvbar.add_button({
  bg = "rgb(fb4934)", size = 14, glyph = "󰖭",
  command = "~/.config/hypr/smart-close.sh",
  fg = "rgb(282828)",
})
hl.plugin.gruvbar.add_button({
  bg = "rgb(fabd2f)", size = 14, glyph = "󰖯",
  command = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized" })']],
  fg = "rgb(282828)",
})
hl.plugin.gruvbar.add_button({
  bg = "rgb(b8bb26)", size = 14, glyph = "󰖰",
  command = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:minimized", silent = true })']],
  fg = "rgb(282828)",
})
