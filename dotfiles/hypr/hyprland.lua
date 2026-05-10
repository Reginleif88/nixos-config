-- Hyprland Lua configuration entry point (Hyprland 0.55+).
--
-- Each require() runs in its own Lua scope per Hyprland's loader, so a
-- syntax error in one module does not abort the others.

require("look_and_feel")
require("input")
require("binds")
require("window_rules")
require("autostart")
require("gruvbar")

-- Per-host overlays. home-manager copies the active host's files into
-- ~/.config/hypr/{env,monitors,workspaces,settings}.lua so this entry
-- point stays host-agnostic.
require("env")
require("monitors")
require("workspaces")
require("settings")
