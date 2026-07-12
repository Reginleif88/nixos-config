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

    # Adopt home-manager's new default config backend (silences the
    # configType deprecation warning) and emit a generated hypr/.luarc.json
    # so an editor's Lua LSP knows the `hl` API. We don't use HM's renderer:
    # the real config is our hand-written Lua tree placed via xdg.configFile
    # below, so HM generates no Hyprland config of its own.
    configType = "lua";

    # Disable HM's systemd integration. Under configType = "lua" it would
    # otherwise generate its own hypr/hyprland.lua, colliding with the
    # hand-written one in xdg.configFile. Disabling it also flips the
    # module's shouldGenerate to false (no hyprland.lua/.conf emitted) and
    # silences the "systemd.enable but no settings" warning. We re-create
    # hyprland-session.target ourselves (below) and start it from
    # autostart.lua, because HM's startup hook only ever landed in
    # hyprland.conf — which Hyprland 0.55 ignores once a hyprland.lua
    # exists, leaving graphical-session.target (hyprpolkitagent et al.) dead.
    systemd.enable = false;
  };

  # Place Hyprland config files
  xdg.configFile = {
    # Lua config (active path under Hyprland 0.55+)
    "hypr/hyprland.lua".source       = ../dotfiles/hypr/hyprland.lua;
    "hypr/look_and_feel.lua".source  = ../dotfiles/hypr/look_and_feel.lua;
    "hypr/input.lua".source          = ../dotfiles/hypr/input.lua;
    "hypr/binds.lua".source          = ../dotfiles/hypr/binds.lua;
    "hypr/window_rules.lua".source   = ../dotfiles/hypr/window_rules.lua;
    # Allow a host-specific autostart overlay when one exists.
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

  } // {
    # Hyprpaper (separate program, unaffected by the Lua migration).
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

  systemd.user.services.windows-desktop = lib.mkIf (hostname == "hyacinth") {
    Unit = {
      Description = "Windows 11 workspace via SDL FreeRDP";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "windows-desktop" ''
        until ${pkgs.netcat-openbsd}/bin/nc -z 127.0.0.1 3389; do
          sleep 2
        done
        exec ${pkgs.freerdp}/bin/sdl-freerdp \
          /v:127.0.0.1 /u:Docker /p:admin \
          /wm-class:windows-11 /t:"Windows 11" \
          /size:1920x1080 /gfx:AVC444 /gdi:hw /network:auto \
          -grab-keyboard \
          +dynamic-resolution +auto-reconnect \
          /clipboard /sound:sys:pulse /cert:tofu
      '';
      Restart = "always";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Session target that graphical-session.target BindsTo. home-manager
  # normally provides this when hyprland.systemd.enable = true, which we
  # turned off (see above) to stop it generating hyprland.lua. autostart.lua
  # starts this target after publishing the Wayland env into the systemd/
  # D-Bus user manager; graphical-session.target has RefuseManualStart=yes,
  # so it can only be brought up by being pulled in through this one. This
  # is what (re)starts hyprpolkitagent and any other graphical-session.target
  # user units.
  systemd.user.targets.hyprland-session = {
    Unit = {
      Description = "Hyprland compositor session";
      Documentation = [ "man:systemd.special(7)" ];
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
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
