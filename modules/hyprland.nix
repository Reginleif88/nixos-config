{ pkgs, ... }:

{
  # Hyprland from nixpkgs (not flake) — tracks releases within days
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # XDG desktop portal
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}
