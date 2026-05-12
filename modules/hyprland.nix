{ pkgs, inputs, ... }:

{
  imports = [ inputs.hyprland.nixosModules.default ];

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # dconf (needed for GTK theming)
  programs.dconf.enable = true;

  # XDG desktop portal. xdg-desktop-portal-hyprland provides the
  # wlr-screencopy-backed pipewire screencast source that apps
  # (browsers, OBS) and clematis's wayvnc-adjacent screen-share
  # use. The GTK portal stays alongside for file pickers etc.
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
    ];
  };

  environment.pathsToLink = [
    "/share/xdg-desktop-portal"
    "/share/applications"
  ];
}
