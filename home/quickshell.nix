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
    pkgs.swaynotificationcenter
  ];

  # Place Quickshell config (recursive for entire bar directory)
  xdg.configFile."quickshell/bar" = {
    source = ../dotfiles/quickshell/bar;
    recursive = true;
  };

  xdg.configFile."fuzzel/fuzzel.ini".source = ../dotfiles/fuzzel/fuzzel.ini;

  # SwayNC notification center config + Gruvbox theme
  xdg.configFile."swaync/config.json".source = ../dotfiles/swaync/config.json;
  xdg.configFile."swaync/style.css".source = ../dotfiles/swaync/style.css;
}
