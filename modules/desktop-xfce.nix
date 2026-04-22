{ pkgs, ... }:

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
    xkb.layout = "us";
  };

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
    Exec=${pkgs.xfce.xfconf}/bin/xfconf-query -c xfwm4 -p /general/use_compositing -s false
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
    Exec=${pkgs.bash}/bin/bash -c '${pkgs.xfce.xfconf}/bin/xfconf-query -c xsettings -p /Xft/RGBA -s none; ${pkgs.xfce.xfconf}/bin/xfconf-query -c xsettings -p /Xft/Hinting -s true; ${pkgs.xfce.xfconf}/bin/xfconf-query -c xsettings -p /Xft/HintStyle -s hintslight; ${pkgs.xfce.xfconf}/bin/xfconf-query -c xsettings -p /Xft/Antialias -s true'
    OnlyShowIn=XFCE;
    X-GNOME-Autostart-enabled=true
    NoDisplay=true
  '';
}
