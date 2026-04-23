{ pkgs, ... }:

let
  # Collapses the default two-panel layout into a single full-width bottom bar.
  # Iterates all current panel IDs so it works regardless of numbering, then
  # merges plugin-ids and removes every panel except panel-1.
  mergePanelsScript = pkgs.writeShellScript "xfce-merge-panels" ''
    for i in $(seq 20); do
      ids=$(${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$')
      [ -n "$ids" ] && break
      sleep 0.5
    done
    [ -z "$ids" ] && exit 1

    panel_count=0
    for id in $ids; do panel_count=$((panel_count + 1)); done
    [ "$panel_count" -le 1 ] && exit 0

    all_plugins=""
    for panel_id in $ids; do
      plugins=$(${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
        -p /panels/panel-$panel_id/plugin-ids 2>/dev/null | grep -E '^[0-9]+$')
      all_plugins="$all_plugins $plugins"
    done

    # Append an xkb layout indicator plugin. ID is max(existing) + 1 to
    # avoid colliding with any plugin-N already registered in /plugins.
    new_id=0
    for p in $all_plugins; do
      [ "$p" -gt "$new_id" ] && new_id=$p
    done
    new_id=$((new_id + 1))
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /plugins/plugin-$new_id --create -t string -s "xkb"
    all_plugins="$all_plugins $new_id"

    type_flags="" value_flags=""
    for p in $all_plugins; do
      [ -z "$p" ] && continue
      type_flags="$type_flags -t int"
      value_flags="$value_flags -s $p"
    done

    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels/panel-1/plugin-ids --create $type_flags $value_flags
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels --create -t int -s 1
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels/panel-1/position -s "p=10;x=0;y=0"
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels/panel-1/length -s 100

    ${pkgs.xfce4-panel}/bin/xfce4-panel -r 2>/dev/null || true
  '';

  # Dynamically finds all backdrop paths that xfdesktop registered for the
  # current monitor/workspace, then sets solid black. Using a retry loop
  # avoids a race against xfdesktop initialising its xfconf keys at startup.
  blackWallpaperScript = pkgs.writeShellScript "xfce-black-wallpaper" ''
    for i in $(seq 20); do
      paths=$(${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "/image-style$")
      [ -n "$paths" ] && break
      sleep 0.5
    done
    for p in $(${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "/image-style$"); do
      ${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop -p "$p" -s 0
    done
    for p in $(${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "/color-style$"); do
      ${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop -p "$p" -s 0
    done
    for p in $(${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "/rgba1$"); do
      ${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop -p "$p" \
        --create -t double -t double -t double -t double -s 0.0 -s 0.0 -s 0.0 -s 1.0
    done
  '';
in

{
  # X11 + XFCE session.
  # enableScreensaver = false: xfce4-screensaver locks the session after
  # ~10 min, which blocks remote-desktop capture (KasmVNC / Sunshine).
  services.xserver = {
    enable = true;
    desktopManager.xfce = {
      enable = true;
      enableScreensaver = false;
    };
    # Two layouts cycled with Alt+Shift; xfce4-xkb-plugin (added below to
    # the panel) surfaces the current layout as a clickable indicator.
    xkb = {
      layout = "us,fr";
      variant = ",";
      options = "grp:alt_shift_toggle";
    };
  };

  # Panel plugins have to live in the system profile so xfce4-panel
  # finds them via XDG_DATA_DIRS (the kasmvnc xstartup sources
  # /etc/set-environment which pulls in /run/current-system/sw/share).
  # Installing via home-manager puts them in ~/.nix-profile/share which
  # the panel never scans under a custom-launched session.
  environment.systemPackages = [
    pkgs.xfce4-whiskermenu-plugin
    pkgs.xfce4-xkb-plugin
  ];

  # LightDM with autologin so an X session is always running for remote
  # capture. getty.autologinUser from login.nix handles non-graphical TTYs.
  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "reginleif88";
  };
  services.displayManager.defaultSession = "xfce";

  # Disable the screen saver — suspending the framebuffer breaks
  # remote-desktop capture of an idle session.
  services.xserver.serverFlagsSection = ''
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
  '';

  # Force xfwm4's compositor off every session. The dotfile already sets
  # it to false, but home-manager symlinks the XML read-only from the
  # store, so xfconfd sometimes falls back to a cached value and the
  # compositor sneaks back on. An extra frame of compositor buffering is
  # the single biggest source of typing latency over remote streaming,
  # so we override imperatively at login via xfconf-query.
  environment.etc."xdg/autostart/disable-xfwm-compositor.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Disable xfwm4 compositor
    Exec=${pkgs.xfconf}/bin/xfconf-query -c xfwm4 -p /general/use_compositing -s false
    OnlyShowIn=XFCE;
    X-GNOME-Autostart-enabled=true
    NoDisplay=true
  '';

  # Merge the two default XFCE panels into one full-width bottom panel.
  environment.etc."xdg/autostart/xfce-single-bottom-panel.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Single bottom panel
    Exec=${mergePanelsScript}
    OnlyShowIn=XFCE;
    X-GNOME-Autostart-enabled=true
    NoDisplay=true
  '';

  # Solid black wallpaper — avoids default XFCE art burning into video frames.
  environment.etc."xdg/autostart/xfce-black-wallpaper.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Black wallpaper
    Exec=${blackWallpaperScript}
    OnlyShowIn=XFCE;
    X-GNOME-Autostart-enabled=true
    NoDisplay=true
  '';

  # Stream-friendly font hinting. Video codecs use 4:2:0 chroma subsampling,
  # which smears the colour fringes subpixel rendering paints on glyph edges.
  # Grayscale-only (RGBA=none) with light hinting keeps edges on integer pixel
  # boundaries — text stays sharp under bitrate adaptation.
  environment.etc."xdg/autostart/xfce-font-hinting.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Stream-friendly font hinting
    Exec=${pkgs.bash}/bin/bash -c '${pkgs.xfconf}/bin/xfconf-query -c xsettings -p /Xft/RGBA -s none; ${pkgs.xfconf}/bin/xfconf-query -c xsettings -p /Xft/Hinting -s true; ${pkgs.xfconf}/bin/xfconf-query -c xsettings -p /Xft/HintStyle -s hintslight; ${pkgs.xfconf}/bin/xfconf-query -c xsettings -p /Xft/Antialias -s true'
    OnlyShowIn=XFCE;
    X-GNOME-Autostart-enabled=true
    NoDisplay=true
  '';
}
