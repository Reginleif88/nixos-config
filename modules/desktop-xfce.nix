{ pkgs, ... }:

{
  # X11 + XFCE session
  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
    xkb.layout = "us";
  };

  # LightDM with autologin so an X session is always running for Sunshine
  # to capture. getty.autologinUser from login.nix continues to handle the
  # non-graphical TTYs (vt2..vt6) in parallel.
  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "reginleif88";
  };
  services.displayManager.defaultSession = "xfce";

  # Disable the screen saver — it suspends the X server's framebuffer,
  # which breaks Sunshine's capture of an idle session.
  services.xserver.serverFlagsSection = ''
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
  '';
}
