-- Clematis autostart: lean variant of the shared autostart.lua, tailored
-- for a headless VM that's only ever used over noVNC. Skipped vs shared:
--   * hyprpaper        — solid grey fallback is fine and saves H.264 bits
--   * proton-mail      — no native client wanted on a server-style host
--   * claude-desktop   — Electron tray app, doesn't belong on the VM
--
-- Kept:
--   * gnome-keyring unlock (sops + git rely on it)
--   * quickshell bar (clock/network indicators in the streamed desktop)
--   * cliphist watchers (clipboard history works over the noVNC channel)
--   * gsettings color-scheme (matches GTK apps to Gruvbox dark)
--   * swaync (in-stream notifications)

hl.on("hyprland.start", function()
  hl.exec_cmd([[cat /run/secrets/keyring_password | gnome-keyring-daemon --unlock --components=secrets,pkcs11]])
  hl.exec_cmd("quickshell -c bar")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("wl-paste --primary --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --primary --type image --watch cliphist store")
  hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
  hl.exec_cmd("swaync")
end)
