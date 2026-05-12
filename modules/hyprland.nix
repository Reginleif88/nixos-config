{ pkgs, inputs, ... }:

{
  imports = [ inputs.hyprland.nixosModules.default ];

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # dconf (needed for GTK theming)
  programs.dconf.enable = true;

  # Don't add xdg-desktop-portal-{hyprland,gtk} to xdg.portal.extraPortals
  # here: programs.hyprland.enable wires both up automatically (the
  # nixpkgs module adds cfg.portalPackage, and its wayland-session.nix
  # adds the GTK portal). Adding pkgs.xdg-desktop-portal-hyprland on top
  # collides with the flake-built one that inputs.hyprland.nixosModules
  # pins via programs.hyprland.portalPackage — same service file name,
  # different store path, user-units build fails with "File exists".
  environment.pathsToLink = [
    "/share/xdg-desktop-portal"
    "/share/applications"
  ];
}
