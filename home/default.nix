{ config, pkgs, inputs, ... }:

{
  imports = [
    ./shell.nix
    ./git.nix
    ./ai.nix
    ./hyprland.nix
    ./kitty.nix
    ./gtk.nix
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
    hyprcursor.enable = true;
  };

  # XDG user directories
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = true;
  };

  programs.home-manager.enable = true;
}
