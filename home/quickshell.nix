{ pkgs, inputs, ... }:

let
  system = "x86_64-linux";
  # NOTE: qt6-webengine removed — it crashes quickshell on startup
  # (FATAL: "Argument list is empty, the program name is not passed to QCoreApplication")
  # GeminiSidebar is disabled until quickshell fixes WebEngine support
  quickshellPkg = inputs.quickshell.packages.${system}.default;
in
{
  home.packages = [
    quickshellPkg
    pkgs.fuzzel
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
