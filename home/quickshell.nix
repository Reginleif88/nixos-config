{ pkgs, inputs, ... }:

let
  system = "x86_64-linux";
  quickshellWithWebEngine = inputs.quickshell.packages.${system}.default.withModules [
    pkgs.qt6.qtwebengine
  ];
in
{
  # Quickshell via flake (with qt6-webengine for GeminiSidebar)
  home.packages = [
    quickshellWithWebEngine
    inputs.elephant.packages.${system}.default
    pkgs.walker
    pkgs.grimblast
    pkgs.cliphist
    pkgs.wl-clipboard
    pkgs.swayimg
    pkgs.networkmanager
    pkgs.bluez
  ];

  # Place Quickshell config (recursive for entire bar directory)
  xdg.configFile."quickshell/bar" = {
    source = ../dotfiles/quickshell/bar;
    recursive = true;
  };

  # Mako notification daemon (managed as systemd user service)
  services.mako.enable = true;
}
