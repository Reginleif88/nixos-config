{ config, pkgs, hostname, lib, ... }:

let
  hyprlandPkg = pkgs.hyprland-patched;
  gruvbar = pkgs.stdenv.mkDerivation {
    pname = "gruvbar";
    version = "0.1";
    src = ../plugins/gruvbar;
    nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ] ++ hyprlandPkg.nativeBuildInputs;
    buildInputs = [ hyprlandPkg ] ++ hyprlandPkg.buildInputs;
  };
in
{
  # Hyprland user config (Hyprland 0.55+: Lua-based)
  wayland.windowManager.hyprland = {
    enable = true;
    package = hyprlandPkg;
  };

  # Place Hyprland config files
  xdg.configFile = {
    # Lua config (active path under Hyprland 0.55+)
    "hypr/hyprland.lua".source       = ../dotfiles/hypr/hyprland.lua;
    "hypr/look_and_feel.lua".source  = ../dotfiles/hypr/look_and_feel.lua;
    "hypr/input.lua".source          = ../dotfiles/hypr/input.lua;
    "hypr/binds.lua".source          = ../dotfiles/hypr/binds.lua;
    "hypr/window_rules.lua".source   = ../dotfiles/hypr/window_rules.lua;
    # Autostart: per-host so that clematis can omit hyprpaper / Proton Mail
    # / claude-desktop-tray, all of which are pointless on a headless VM
    # streamed over noVNC.
    "hypr/autostart.lua".source      =
      if builtins.pathExists (../dotfiles/hypr/hosts + "/${hostname}/autostart.lua")
      then ../dotfiles/hypr/hosts + "/${hostname}/autostart.lua"
      else ../dotfiles/hypr/autostart.lua;
    "hypr/gruvbar.lua".source        = ../dotfiles/hypr/gruvbar.lua;
    # Generated stub so the user-edited gruvbar.lua doesn't carry a /nix/store hash.
    "hypr/gruvbar_path.lua".text     = ''return "${gruvbar}/lib/libgruvbar.so"'';

    # Per-host overlays — flattened so the entry point can plain require() them.
    "hypr/env.lua".source        = ../dotfiles/hypr/hosts/${hostname}/env.lua;
    "hypr/monitors.lua".source   = ../dotfiles/hypr/hosts/${hostname}/monitors.lua;
    "hypr/workspaces.lua".source = ../dotfiles/hypr/hosts/${hostname}/workspaces.lua;
    "hypr/settings.lua".source   = ../dotfiles/hypr/hosts/${hostname}/settings.lua;

  } // lib.optionalAttrs (hostname != "clematis") {
    # Hyprpaper (separate program, unaffected by the Lua migration).
    # Skipped on clematis: nothing autostarts hyprpaper there, and
    # leaving the wallpaper out drops H.264 bitrate by 20-40% during
    # static desktop (a complex 1920x1080 background eats most of the
    # bits in every IDR frame). Hyprland's solid-grey fallback applies
    # automatically because settings.lua disables splash + logo.
    "hypr/hyprpaper.conf".source = ../dotfiles/hypr/hyprpaper.conf;
    "hypr/backgrounds/rainynight.png".source = ../dotfiles/hypr/backgrounds/rainynight.png;
  };

  # Unminimize script (needs executable bit)
  home.file.".config/hypr/unminimize.sh" = {
    source = ../dotfiles/hypr/unminimize.sh;
    executable = true;
  };

  # Smart-close script: minimize tray-apps instead of killing them
  home.file.".config/hypr/smart-close.sh" = {
    source = ../dotfiles/hypr/smart-close.sh;
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
