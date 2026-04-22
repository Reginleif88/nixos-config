{ config, pkgs, lib, ... }:

let
  user = "reginleif88";
  home = config.users.users.${user}.home;

  # One of three config files the perl wrapper reads (defaults,
  # system, per-user). We run HTTP-only on localhost; TLS lives at
  # the Cloudflare edge, so require_ssl=false avoids needing the
  # snakeoil cert Debian ships at /etc/ssl/certs/ssl-cert-snakeoil.pem.
  systemConfig = pkgs.writeText "kasmvnc.yaml" ''
    desktop:
      resolution:
        width: 1920
        height: 1080
      allow_resize: true
      pixel_depth: 24

    network:
      protocol: http
      interface: 127.0.0.1
      websocket_port: 8443
      ssl:
        require_ssl: false

    encoding:
      max_frame_rate: 60
      video_encoding_mode:
        max_resolution:
          width: 1920
          height: 1080

    user_session:
      new_session_disconnects_existing_exclusive_session: true

    logging:
      log_writer_name: all
      log_dest: logfile
      level: 30

    # Disable interactive prompting so the perl wrapper exits
    # cleanly (non-zero) if no kasm user exists, instead of
    # hanging on stdin from a systemd service.
    command_line:
      prompt: false
  '';

  # xstartup: executed by kasmvncserver once Xkasmvnc is up. `exec`
  # replaces the shell so that when xfce4-session exits, -fg in the
  # parent tears Xkasmvnc down and systemd restarts the unit.
  xstartup = pkgs.writeShellScript "kasmvnc-xstartup" ''
    unset SESSION_MANAGER
    unset DBUS_SESSION_BUS_ADDRESS
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=XFCE
    exec ${pkgs.xfce.xfce4-session}/bin/xfce4-session
  '';
in
{
  environment.etc."kasmvnc/kasmvnc.yaml".source = systemConfig;

  # Expose kasmvncpasswd on PATH so the first-boot bootstrap
  # (`kasmvncpasswd -u reginleif88 ~/.kasmpasswd`) works from an SSH
  # session. KasmVNC has no no-auth mode; since this already lives
  # behind Cloudflare Access, the VNC password is a second factor.
  environment.systemPackages = [ pkgs.kasmvnc ];

  systemd.services.kasmvnc = {
    description = "KasmVNC server (XFCE on :1, WebSocket on 127.0.0.1:8443)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = home;
      USER = user;
    };

    path = with pkgs; [
      kasmvnc
      xfce.xfce4-session
      xfce.xfdesktop
      xfce.xfwm4
      xfce.xfce4-panel
      xfce.xfce4-settings
      dbus
    ];

    # The perl wrapper writes host:1.log and the pid file into ~/.vnc,
    # and refuses to start if ~/.kasmpasswd has no user with write
    # permissions — bail out early with a clear message so
    # `systemctl status` explains what the operator needs to do.
    preStart = ''
      mkdir -p "${home}/.vnc"
      chmod 700 "${home}/.vnc"
      if [ ! -s "${home}/.kasmpasswd" ]; then
        echo "ERROR: ${home}/.kasmpasswd not set up." >&2
        echo "Run (as ${user}): kasmvncpasswd -w -u ${user} ${home}/.kasmpasswd" >&2
        exit 1
      fi
    '';

    serviceConfig = {
      Type = "simple";
      User = user;
      Group = "users";

      # -fg runs xstartup in the foreground, so xfce4-session's exit
      # tears down Xkasmvnc cleanly. -xstartup skips the interactive
      # DE picker — we hard-code XFCE here.
      ExecStart = ''
        ${pkgs.kasmvnc}/bin/kasmvncserver :1 -fg -xstartup ${xstartup}
      '';

      ExecStop = "${pkgs.kasmvnc}/bin/kasmvncserver -kill :1";

      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
