{
  config,
  pkgs,
  hostname,
  lib,
  ...
}:

let
  hyprlandPkg = pkgs.hyprland-patched;
  gruvbar = pkgs.stdenv.mkDerivation {
    pname = "gruvbar";
    version = "0.1";
    src = ../plugins/gruvbar;
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
    ]
    ++ hyprlandPkg.nativeBuildInputs;
    buildInputs = [ hyprlandPkg ] ++ hyprlandPkg.buildInputs;
  };

  keyringUnlock = pkgs.writeShellScript "unlock-gnome-keyring" ''
    set -euo pipefail
    if [ -r /run/secrets/keyring_password ]; then
      exec ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon \
        --foreground --unlock --components=secrets,pkcs11 < /run/secrets/keyring_password
    fi
    exec ${pkgs.coreutils}/bin/true
  '';

  cliphistWatchers = pkgs.writeShellScript "cliphist-watchers" ''
    set -euo pipefail
    trap 'kill 0' EXIT TERM INT
    ${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --primary --type text --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --primary --type image --watch ${pkgs.cliphist}/bin/cliphist store &
    wait
  '';
in
{
  # Home Manager owns the generated Lua entry point and loads the hand-written
  # modules in a deterministic order. The plugin is loaded before gruvbar.lua.
  wayland.windowManager.hyprland = {
    enable = true;
    package = hyprlandPkg;

    configType = "lua";
    systemd.enable = true;
    plugins = [ gruvbar ];

    extraLuaFiles = {
      "00_env" = ../dotfiles/hypr/hosts + "/${hostname}/env.lua";
      "10_look_and_feel" = ../dotfiles/hypr/look_and_feel.lua;
      "20_input" = ../dotfiles/hypr/input.lua;
      "30_binds" = ../dotfiles/hypr/binds.lua;
      "40_window_rules" = ../dotfiles/hypr/window_rules.lua;
      "50_gruvbar" = ../dotfiles/hypr/gruvbar.lua;
      "60_monitors" = ../dotfiles/hypr/hosts + "/${hostname}/monitors.lua";
      "70_workspaces" = ../dotfiles/hypr/hosts + "/${hostname}/workspaces.lua";
      "80_settings" = ../dotfiles/hypr/hosts + "/${hostname}/settings.lua";
      "gruvbar_path" = {
        content = ''return "${gruvbar}/lib/libgruvbar.so"'';
        autoLoad = false;
      };
    };
  };

  # Hyprpaper is independent of the Lua configuration.
  xdg.configFile = {
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
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  services.hyprpolkitagent.enable = true;

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        ignore_empty_input = true;
      };
      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
        }
      ];
      input-field = [
        {
          monitor = "";
          size = "320, 60";
          position = "0, -80";
          dots_center = true;
          fade_on_empty = false;
          inner_color = "rgb(3c3836)";
          outer_color = "rgb(fe8019)";
          font_color = "rgb(ebdbb2)";
          outline_thickness = 3;
          placeholder_text = "Password...";
        }
      ];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 900;
          on-timeout = "hyprlock";
        }
        {
          timeout = 1200;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  # SUPER+I is the deliberate opt-in for idle locking/DPMS; do not start this
  # service automatically with the graphical session.
  systemd.user.services.hypridle.Install.WantedBy = lib.mkForce [ ];

  systemd.user.services = {
    gnome-keyring = {
      Unit = {
        Description = "Unlock GNOME Keyring for the graphical session";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = keyringUnlock;
        Type = "simple";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    cliphist-watchers = {
      Unit = {
        Description = "Clipboard history watchers";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = cliphistWatchers;
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    hyprpaper = {
      Unit = {
        Description = "Hyprpaper wallpaper daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.hyprpaper}/bin/hyprpaper";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    quickshell = {
      Unit = {
        Description = "Quickshell status bar";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${config.home.profileDirectory}/bin/quickshell -c bar";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    swaync = {
      Unit = {
        Description = "SwayNotificationCenter";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.swaynotificationcenter}/bin/swaync";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    proton-mail = {
      Unit = {
        Description = "Proton Mail desktop client";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.flatpak}/bin/flatpak run me.proton.Mail";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    claude-desktop = {
      Unit = {
        Description = "Claude Desktop tray client";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        ExecStart = "${config.home.profileDirectory}/bin/claude-desktop --tray";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
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
