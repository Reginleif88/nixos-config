{ config, pkgs, inputs, ... }:

let
  hyprlandPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  gruvbar = pkgs.stdenv.mkDerivation {
    pname = "gruvbar";
    version = "0.1";
    src = ../plugins/gruvbar;
    nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ] ++ hyprlandPkg.nativeBuildInputs;
    buildInputs = [ hyprlandPkg ] ++ hyprlandPkg.buildInputs;
  };
in
{
  # Hyprland user config
  wayland.windowManager.hyprland = {
    enable = true;
    package = hyprlandPkg;
    plugins = [ gruvbar ];
    extraConfig = ''
      source = ~/.config/hypr/hyprland-custom.conf
    '';
  };

  # Place Hyprland config files
  xdg.configFile = {
    "hypr/hyprland-custom.conf".source = ../dotfiles/hypr/hyprland.conf;
    "hypr/env.conf".source = ../dotfiles/hypr/env.conf;
    "hypr/monitors.conf".source = ../dotfiles/hypr/monitors.conf;
    "hypr/workspaces.conf".source = ../dotfiles/hypr/workspaces.conf;
    "hypr/hyprpaper.conf".source = ../dotfiles/hypr/hyprpaper.conf;
    "hypr/backgrounds/rainynight.png".source = ../dotfiles/hypr/backgrounds/rainynight.png;
  };

  # Unminimize script (needs executable bit)
  home.file.".config/hypr/unminimize.sh" = {
    source = ../dotfiles/hypr/unminimize.sh;
    executable = true;
  };

  # Enable hyprpolkitagent as a systemd user service
  systemd.user.services.hyprpolkitagent = {
    Unit.Description = "Hyprland Polkit Authentication Agent";
    Unit.After = [ "graphical-session.target" ];
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
      Restart = "on-failure";
    };
  };

  # Hyprland ecosystem packages
  home.packages = with pkgs; [
    hyprpaper
    hyprpolkitagent
    brightnessctl
    playerctl
  ];
}
