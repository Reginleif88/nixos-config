{ pkgs, ... }:

let
  # Collapses the default two-panel layout into a single full-width bottom bar,
  # ensures an xkb layout indicator is present, then reorders plugins so
  # info/status widgets anchor left and apps/launchers anchor right.
  # Classification is by plugin type, making the script fully idempotent.
  mergePanelsScript = pkgs.writeShellScript "xfce-merge-panels" ''
    for i in $(seq 20); do
      ids=$(${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$')
      [ -n "$ids" ] && break
      sleep 0.5
    done
    [ -z "$ids" ] && exit 1

    # Collect all plugin-ids across every current panel. Works on fresh
    # install (two panels) and on subsequent boots (one merged panel).
    all_plugins=""
    for panel_id in $ids; do
      plugins=$(${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
        -p /panels/panel-$panel_id/plugin-ids 2>/dev/null | grep -E '^[0-9]+$')
      all_plugins="$all_plugins $plugins"
    done

    # Locate (or create) the xkb layout indicator plugin and track its ID
    # so we can also set its display properties below.
    xkb_id=""
    for pid in $all_plugins; do
      [ -z "$pid" ] && continue
      ptype=$(${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel -p /plugins/plugin-$pid 2>/dev/null)
      if [ "$ptype" = "xkb" ]; then xkb_id=$pid; break; fi
    done
    if [ -z "$xkb_id" ]; then
      max_id=0
      for p in $all_plugins; do
        [ -z "$p" ] && continue
        [ "$p" -gt "$max_id" ] && max_id=$p
      done
      xkb_id=$((max_id + 1))
      ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
        -p /plugins/plugin-$xkb_id --create -t string -s "xkb"
      all_plugins="$all_plugins $xkb_id"
    fi
    # display-type=1 → text (layout code like "us"/"fr") instead of a flag
    # image. group-policy=0 → same layout across all windows.
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /plugins/plugin-$xkb_id/display-type --create -t uint -s 1
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /plugins/plugin-$xkb_id/group-policy --create -t uint -s 0

    # Reorder: classify each plugin by type, put apps/launchers on the left
    # and info/status widgets on the right, with the expand separator between
    # them. Classification is by type (not position), so running this
    # repeatedly always converges on the same layout.
    left_plugins="" right_plugins="" expand_id=""
    for pid in $all_plugins; do
      [ -z "$pid" ] && continue
      ptype=$(${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel -p /plugins/plugin-$pid 2>/dev/null)
      [ -z "$ptype" ] && continue
      case "$ptype" in
        applicationsmenu|whiskermenu|tasklist|launcher|directorymenu|showdesktop|pager|appfinder|windowmenu|quicklauncher)
          left_plugins="$left_plugins $pid" ;;
        clock|systray|statusnotifier|notification-plugin|notification-area|xkb|actions|pulseaudio|power-manager-plugin|battery|weather)
          right_plugins="$right_plugins $pid" ;;
        separator)
          expand=$(${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel -p /plugins/plugin-$pid/expand 2>/dev/null)
          if [ "$expand" = "true" ] && [ -z "$expand_id" ]; then
            expand_id=$pid
          fi
          # Non-expand separators are dropped for a cleaner layout.
          ;;
        *)
          left_plugins="$left_plugins $pid" ;;
      esac
    done

    # If no expand separator exists, fabricate one so the two groups actually
    # anchor to opposite edges instead of collapsing together on the left.
    if [ -z "$expand_id" ]; then
      max_id=0
      for p in $all_plugins; do
        [ -z "$p" ] && continue
        [ "$p" -gt "$max_id" ] && max_id=$p
      done
      expand_id=$((max_id + 1))
      ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
        -p /plugins/plugin-$expand_id --create -t string -s "separator"
      ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
        -p /plugins/plugin-$expand_id/expand --create -t bool -s true
      ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
        -p /plugins/plugin-$expand_id/style --create -t uint -s 0
    fi

    all_plugins="$left_plugins $expand_id $right_plugins"

    type_flags="" value_flags=""
    for p in $all_plugins; do
      [ -z "$p" ] && continue
      type_flags="$type_flags -t int"
      value_flags="$value_flags -s $p"
    done

    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels/panel-1/plugin-ids --create $type_flags $value_flags
    # --force-array (-a) is critical: without it, xfconf-query flattens a
    # single-element array to a scalar int, which breaks /panels parsing.
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels --create -a -t int -s 1
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels/panel-1/position -s "p=10;x=0;y=0"
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels/panel-1/length -s 100
    # Default panel-1 ships with size=26 / icon-size=16, which is cramped
    # over a scaled VNC stream. Bumping both makes targets legible.
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels/panel-1/size --create -t uint -s 54
    ${pkgs.xfconf}/bin/xfconf-query -c xfce4-panel \
      -p /panels/panel-1/icon-size --create -t uint -s 33

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

    # Update any paths xfdesktop has already registered.
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

    # Fallback: force-write the common monitor/workspace paths. If xfdesktop
    # hadn't registered its keys yet (happens in some KasmVNC sessions), the
    # loops above no-op. Writing speculative paths is harmless — xfdesktop
    # ignores monitor names that don't match a real RandR output.
    for mon in VNC-0 VNC0 screen screen0 0; do
      for ws in 0 1 2 3; do
        base="/backdrop/screen0/monitor$mon/workspace$ws"
        ${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop \
          -p "$base/image-style" --create -t int -s 0
        ${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop \
          -p "$base/color-style" --create -t int -s 0
        ${pkgs.xfconf}/bin/xfconf-query -c xfce4-desktop -p "$base/rgba1" \
          --create -t double -t double -t double -t double -s 0.0 -s 0.0 -s 0.0 -s 1.0
      done
    done

    ${pkgs.xfdesktop}/bin/xfdesktop --reload 2>/dev/null || true
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

  # services.xserver.xkb only writes /etc/X11/xorg.conf.d/, which Xkasmvnc
  # doesn't read — it spawns its own X server with a single default layout.
  # setxkbmap at session start injects both layouts so the xkb plugin and
  # the Alt+Shift toggle actually see us *and* fr.
  environment.etc."xdg/autostart/xfce-keyboard-layouts.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Configure keyboard layouts
    Exec=${pkgs.xorg.setxkbmap}/bin/setxkbmap -layout us,fr -option "" -option grp:alt_shift_toggle
    OnlyShowIn=XFCE;
    X-GNOME-Autostart-enabled=true
    NoDisplay=true
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
    Exec=${pkgs.bash}/bin/bash -c '${pkgs.xfconf}/bin/xfconf-query -c xsettings -p /Xft/DPI -s 120; ${pkgs.xfconf}/bin/xfconf-query -c xsettings -p /Xft/RGBA -s none; ${pkgs.xfconf}/bin/xfconf-query -c xsettings -p /Xft/Hinting -s true; ${pkgs.xfconf}/bin/xfconf-query -c xsettings -p /Xft/HintStyle -s hintslight; ${pkgs.xfconf}/bin/xfconf-query -c xsettings -p /Xft/Antialias -s true'
    OnlyShowIn=XFCE;
    X-GNOME-Autostart-enabled=true
    NoDisplay=true
  '';
}
