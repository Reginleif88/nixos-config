-- Autostart. The 0.54 hyprlang config used `exec-once = …` lines plus two
-- `sleep N && hyprctl dispatch …` shell delays; in Lua we batch them all
-- into hyprland.start and replace the shell sleeps with hl.timer.

hl.on("hyprland.start", function()
  hl.exec_cmd([[cat /run/secrets/keyring_password | gnome-keyring-daemon --unlock --components=secrets,pkcs11]])
  hl.exec_cmd("hyprpaper")
  hl.exec_cmd("quickshell -c bar")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("wl-paste --primary --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --primary --type image --watch cliphist store")
  hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
  hl.exec_cmd("swaync")
  hl.exec_cmd("proton-mail")

  -- Wait for the Proton Mail window to actually appear before parking it.
  hl.timer(function()
    hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", silent = true, window = "title:Proton Mail" }))
  end, { timeout = 5000, type = "oneshot" })

  hl.timer(function()
    hl.exec_cmd("claude-desktop --tray")
  end, { timeout = 3000, type = "oneshot" })
end)
