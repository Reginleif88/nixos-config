-- Autostart. The 0.54 hyprlang config used `exec-once = …` lines plus two
-- `sleep N && hyprctl dispatch …` shell delays; in Lua we batch them all
-- into hyprland.start and replace the shell sleeps with hl.timer.

hl.on("hyprland.start", function()
  -- Session bootstrap: publish the Wayland env into the systemd/D-Bus user
  -- manager, then bring up the session target. graphical-session.target is
  -- RefuseManualStart=yes, so we start hyprland-session.target (which BindsTo
  -- it) — that is what runs hyprpolkitagent and any other
  -- graphical-session.target user units. home-manager used to emit this line
  -- into hyprland.conf, but Hyprland 0.55 ignores that file once a
  -- hyprland.lua exists, so it has to live here in the loaded Lua. The two
  -- commands are chained in one exec so the env is published before the
  -- target starts (hl.exec_cmd is fire-and-forget, so separate calls would
  -- not be ordered).
  hl.exec_cmd("dbus-update-activation-environment --systemd DISPLAY HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE && systemctl --user start hyprland-session.target")

  hl.exec_cmd([[cat /run/secrets/keyring_password | gnome-keyring-daemon --unlock --components=secrets,pkcs11]])
  hl.exec_cmd("hyprpaper")
  hl.exec_cmd("quickshell -c bar")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("wl-paste --primary --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --primary --type image --watch cliphist store")
  hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
  hl.exec_cmd("swaync")
  -- Proton Mail is parked on special:minimized by a window rule
  -- (minimize-proton-mail in window_rules.lua), which fires on window.open
  -- instead of racing a fixed timer.
  hl.exec_cmd("proton-mail")

  hl.timer(function()
    hl.exec_cmd("claude-desktop --tray")
  end, { timeout = 3000, type = "oneshot" })
end)
