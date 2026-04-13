{ config, pkgs, inputs, hostname, lib, ... }:

let
  # Hosts running the Hyprland Wayland compositor (gets hyprland + quickshell)
  isHyprland = builtins.elem hostname [ "hyacinth" "wisteria" ];
  # Hosts with any graphical desktop (gets desktop apps + browser).
  # clematis runs XFCE on X11, hyacinth/wisteria run Hyprland.
  isGraphical = isHyprland || builtins.elem hostname [ "clematis" ];
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
