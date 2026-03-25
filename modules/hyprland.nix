{ pkgs, inputs, ... }:

{
  imports = [ inputs.hyprland.nixosModules.default ];

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # dconf (needed for GTK theming)
  programs.dconf.enable = true;

  # XDG desktop portal
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  environment.pathsToLink = [
    "/share/xdg-desktop-portal"
    "/share/applications"
  ];
}
