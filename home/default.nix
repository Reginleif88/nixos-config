{ config, pkgs, inputs, hostname, lib, ... }:

let
  # Hosts running the Hyprland Wayland compositor (gets hyprland + quickshell).
  # clematis runs headless Hyprland under wayvnc — same compositor, no
  # physical display — so it gets the same home-manager stack.
  isHyprland = builtins.elem hostname [ "hyacinth" "wisteria" "clematis" ];
  # Hosts with any graphical desktop (gets desktop apps + browser).
  # Currently redundant with isHyprland but kept as a predicate in case a
  # future host wants graphical apps without the Hyprland compositor.
  isGraphical = isHyprland;
in
{
  imports = [
    inputs.claude-desktop.homeManagerModules.default
    ./shell.nix
    ./git.nix
    ./ai.nix
    ./kitty.nix
    ./gtk.nix
  ] ++ lib.optionals isHyprland [
    ./hyprland.nix
    ./quickshell.nix
  ] ++ lib.optionals isGraphical [
    ./apps.nix
    ./browser.nix
    ./mpv.nix
  ];

  home.username = "reginleif88";
  home.homeDirectory = "/home/reginleif88";
  home.stateVersion = "25.11";

  home.pointerCursor = {
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
