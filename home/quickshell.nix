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

  # Walker launcher config
  xdg.configFile."walker/config.toml".source = ../dotfiles/walker/config.toml;

  # Mako notification daemon (managed as systemd user service)
  services.mako.enable = true;
}
