{
  pkgs,
  inputs,
  hostname,
  lib,
  ...
}:

let
  # Hosts running the Hyprland Wayland compositor (gets hyprland + quickshell).
  isHyprland = hostname == "hyacinth";
  # Hosts with any graphical desktop (gets desktop apps + browser).
  # Currently redundant with isHyprland but kept as a predicate in case a
  # future host wants graphical apps without the Hyprland compositor.
  isGraphical = isHyprland;
in
{
  imports = [
    ./shell.nix
    ./git.nix
  ]
  ++ lib.optionals isGraphical [
    inputs.claude-desktop.homeManagerModules.default
    ./ai.nix
    ./kitty.nix
    ./gtk.nix
  ]
  ++ lib.optionals isHyprland [
    ./hyprland.nix
    ./quickshell.nix
  ]
  ++ lib.optionals isGraphical [
    ./apps.nix
    ./browser.nix
  ];

  # Expose the host predicates to sibling home modules (e.g. gtk.nix) so they
  # can gate features without re-deriving the host list. dconf.settings, for
  # instance, only works on hosts where programs.dconf is enabled system-side
  # (the graphical ones); headless hosts have no dconf D-Bus service.
  _module.args = { inherit isHyprland isGraphical; };

  home.username = "reginleif88";
  home.homeDirectory = "/home/reginleif88";
  home.stateVersion = "25.11";

  home.pointerCursor = lib.mkIf isGraphical {
    enable = true;
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
    hyprcursor.enable = isHyprland;
  };

  # XDG user directories
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = true;
  };

  programs.home-manager.enable = true;
}
