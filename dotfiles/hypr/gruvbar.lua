-- gruvbar plugin: load + typed config + button injection workaround.
--
-- gruvbar-button is registered via addConfigKeyword (handler-based), not
-- addConfigValue. The Lua hl.config() path only reaches typed values, so
-- the buttons are pushed in via hyprctl after Hyprland starts. See plan
-- file: nested-wiggling-milner.md, Risk #1.

local pluginPath = require("gruvbar_path")
hl.plugin.load(pluginPath)

hl.config({
  plugin = {
    gruvbar = {
      bar_height                 = 28,
      bar_color                  = "rgb(282828)",
      bar_precedence_over_border = true,
      bar_padding                = 10,
      bar_button_padding         = 8,
      bar_title_enabled          = true,
      ["col.text"]               = "rgb(ebdbb2)",
      bar_text_size              = 12,
      bar_text_font              = "Atkinson Hyperlegible",
      bar_text_align             = "center",
      bar_buttons_alignment      = "right",
    },
  },
})

-- Close (red) | Maximize (yellow) | Minimize (green)
hl.on("hyprland.start", function()
  hl.exec_cmd([[hyprctl keyword 'plugin:gruvbar:gruvbar-button rgb(fb4934), 14, 󰖭, ~/.config/hypr/smart-close.sh, rgb(282828)']])
  hl.exec_cmd([[hyprctl keyword 'plugin:gruvbar:gruvbar-button rgb(fabd2f), 14, 󰖯, hyprctl dispatch fullscreen 1, rgb(282828)']])
  hl.exec_cmd([[hyprctl keyword 'plugin:gruvbar:gruvbar-button rgb(b8bb26), 14, 󰖰, hyprctl dispatch movetoworkspacesilent special:minimized, rgb(282828)']])
end)
