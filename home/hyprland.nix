{ config, pkgs, inputs, hostname, ... }:

let
  # Upstream Hyprland workaround against HEAD commit ee58a513 (2026-05-09).
  # `--replace-fail` makes the build error if upstream changes the matched string,
  # so the patch announces itself when it can be dropped.
  #
  # device-tags null deref (commit 497b48e852, PR #13728):
  #   InputManager calls `getDeviceString(devname, "tags")` with no fallback.
  #   getConfigValueSafeDevice returns nullptr when the keyboard isn't in any
  #   explicit `device { name = … }` block, and getDeviceString deref's it
  #   without a null check → SIGSEGV in libinput new-keyboard signal.
  #   Replacing the call expression with `std::string("")` makes the for-loop
  #   iterate zero items, disabling the device-tags feature (which we don't use
  #   anyway) until upstream null-checks the call. As of ee58a513 there are two
  #   identical call sites (applyConfigToKeyboard and the second pass over
  #   already-attached keyboards); substituteInPlace patches both.
  hyprlandPkg = (inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland).overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/managers/input/InputManager.cpp \
        --replace-fail 'CVarList2(Config::mgr()->getDeviceString(devname, "tags"))' 'CVarList2(std::string(""))'
    '';
  });
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
    "hypr/autostart.lua".source      = ../dotfiles/hypr/autostart.lua;
    "hypr/gruvbar.lua".source        = ../dotfiles/hypr/gruvbar.lua;
    # Generated stub so the user-edited gruvbar.lua doesn't carry a /nix/store hash.
    "hypr/gruvbar_path.lua".text     = ''return "${gruvbar}/lib/libgruvbar.so"'';

    # Per-host overlays — flattened so the entry point can plain require() them.
    "hypr/env.lua".source        = ../dotfiles/hypr/hosts/${hostname}/env.lua;
    "hypr/monitors.lua".source   = ../dotfiles/hypr/hosts/${hostname}/monitors.lua;
    "hypr/workspaces.lua".source = ../dotfiles/hypr/hosts/${hostname}/workspaces.lua;
    "hypr/settings.lua".source   = ../dotfiles/hypr/hosts/${hostname}/settings.lua;

    # Hyprpaper (separate program, unaffected by the Lua migration)
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
