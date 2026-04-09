{ config, pkgs, inputs, hostname, lib, ... }:

let
  isHyprland = builtins.elem hostname [ "hyacinth" "wisteria" ];
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
