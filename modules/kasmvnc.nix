{ config, pkgs, lib, ... }:

let
  user = "reginleif88";
  home = config.users.users.${user}.home;
  passwordSecret = config.sops.secrets."kasmvnc_password".path;

  # KasmVNC's perl wrapper tries to load /etc/ssl/certs/ssl-cert-snakeoil.{pem,key}
  # unconditionally on startup and exits 1 if they're missing, even with
  # require_ssl=false. NixOS doesn't ship those Debian paths, so we point
  # ssl.pem_certificate/pem_key at a self-signed cert generated lazily in
  # preStart. With protocol=http the cert is never presented to clients —
  # it exists only to satisfy the wrapper's config-load check.
  certPath = "${home}/.vnc/self.pem";
  keyPath  = "${home}/.vnc/self.key";

  systemConfig = pkgs.writeText "kasmvnc.yaml" ''
    desktop:
      resolution:
        width: 1920
        height: 1080
      allow_resize: true
      pixel_depth: 24
      # This VM has AMD Barcelo iGPU passthrough with /dev/dri/renderD128
      # available. hw3d=true routes OpenGL / VA-API calls through real
      # hardware instead of Mesa's software rasterizer — big win for
      # video playback (YouTube/Twitch in browser), any GPU-accelerated
      # web content, and any OpenGL app run inside the session.
      gpu:
        hw3d: true
        drinode: /dev/dri/renderD128

    network:
      protocol: http
      interface: 0.0.0.0
      websocket_port: 8443
      # WebUDP is a low-latency input channel that needs STUN reachability
      # and a publicly resolvable address. Loopback-bound + behind NAT means
      # it can never succeed; disable it to stop the "Failed to create WebUDP
      # host" warning on every startup. TCP-over-websocket handles all I/O.
      udp:
        port: 0
      ssl:
        require_ssl: false
        pem_certificate: ${certPath}
        pem_key: ${keyPath}

    encoding:
      max_frame_rate: 60
      video_encoding_mode:
        max_resolution:
          width: 1920
          height: 1080

    user_session:
      new_session_disconnects_existing_exclusive_session: true

    # Allow the client to enable bidirectional clipboard. KasmVNC gates
    # this behind data_loss_prevention naming because it's designed for
    # Kasm Workspaces (enterprise DLP use case); for personal use we
    # just declare the full set of copy/paste mimetypes here.
    data_loss_prevention:
      clipboard:
        allow_mimetypes:
          - chromium/x-web-custom-data
          - text/html
          - text/plain
          - image/png

    logging:
      log_writer_name: all
      log_dest: logfile
      # 20 = informational (auth events, errors, key state changes).
      # 30 is debug-verbose and bloats the log by ~10x.
      level: 20

    # Disable interactive prompting so the perl wrapper exits
    # cleanly (non-zero) if no kasm user exists, instead of
    # hanging on stdin from a systemd service.
    command_line:
      prompt: false
  '';

  # xstartup: executed by kasmvncserver once Xkasmvnc is up. `exec`
  # replaces the shell so that when xfce4-session exits, -fg in the
  # parent tears Xkasmvnc down and systemd restarts the unit.
  #
  # We source /etc/set-environment so home-manager-installed apps
  # (Obsidian, VSCode, Claude Desktop, etc.) and their .desktop entries
  # become visible to xfce4-panel and its whisker menu. Without this the
  # session PATH + XDG_DATA_DIRS only include xfce4-panel/session's own
  # store paths, which hides every per-user app and icon theme.
  xstartup = pkgs.writeShellScript "kasmvnc-xstartup" ''
    [ -f /etc/set-environment ] && . /etc/set-environment
    [ -f "$HOME/.profile" ] && . "$HOME/.profile"

    unset SESSION_MANAGER
    unset DBUS_SESSION_BUS_ADDRESS
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=XFCE
    exec ${pkgs.xfce4-session}/bin/xfce4-session
  '';
in
{
  environment.etc."kasmvnc/kasmvnc.yaml".source = systemConfig;

  # Xkasmvnc was compiled on Debian with XKBBINDIR=/usr/bin, so it
  # popen()s the literal string "/usr/bin/xkbcomp" when compiling the
  # keymap at server startup. KasmVNC 1.4 has no flag to override this
  # path, so we populate it. `L+` creates/replaces the symlink; the
  # parent `d /usr/bin` is defensive in case nothing else in the
  # system has created it yet.
  systemd.tmpfiles.rules = [
    "d /usr/bin 0755 root root -"
    "L+ /usr/bin/xkbcomp - - - - ${pkgs.xkbcomp}/bin/xkbcomp"
  ];

  # Expose kasmvncpasswd on PATH so an operator can rotate the password
  # from an SSH session (`kasmvncpasswd -u reginleif88 ~/.kasmpasswd`).
  environment.systemPackages = [ pkgs.kasmvnc ];

  # kasmvnc.yaml binds 0.0.0.0:8443, so the LAN needs the port open.
  # Auth is the VNC password only — no TLS, no tunnel — so anything
  # routable to this host can attempt to brute-force it.
  networking.firewall.allowedTCPPorts = [ 8443 ];

  systemd.services.kasmvnc = {
    description = "KasmVNC server (XFCE on :1, WebSocket on 0.0.0.0:8443)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = home;
      USER = user;
    };

    path = with pkgs; [
      kasmvnc
      # mcookie (util-linux) is invoked by kasmvncserver's perl wrapper to
      # generate an Xauth magic cookie; without it the wrapper exits early
      # with `Can't exec "mcookie"` and `Use of uninitialized value $cookie`.
      util-linux
      xfce4-session
      xfdesktop
      xfwm4
      xfce4-panel
      xfce4-settings
      dbus
    ];

    # Re-start the unit whenever the YAML, xstartup, or password-file
    # derivations change. Without this, edits to kasmvnc.yaml land in
    # /etc/ on rebuild but the running process keeps its old config
    # because the systemd unit definition itself is unchanged.
    restartTriggers = [ systemConfig xstartup ];

    preStart = ''
      mkdir -p "${home}/.vnc"
      chmod 700 "${home}/.vnc"

      if [ ! -s "${home}/.kasmpasswd" ]; then
        PASSWORD=$(cat ${passwordSecret})
        # -wo = write + owner permissions. Without any permission flag
        # the user gets none, and the session logs "User reginleif88
        # has no read permissions" and never sends frames to the client.
        printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | \
          ${pkgs.kasmvnc}/bin/kasmvncpasswd -wo -u ${user} "${home}/.kasmpasswd"
        chmod 600 "${home}/.kasmpasswd"
      fi

      if [ ! -s "${certPath}" ] || [ ! -s "${keyPath}" ]; then
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
          -keyout "${keyPath}" -out "${certPath}" -subj "/CN=localhost"
        chmod 600 "${certPath}" "${keyPath}"
      fi
    '';

    serviceConfig = {
      Type = "simple";
      User = user;
      Group = "users";

      # -fg runs xstartup in the foreground, so xfce4-session's exit
      # tears down Xkasmvnc cleanly. -xstartup skips the interactive
      # DE picker — we hard-code XFCE here. -xkbdir overrides the
      # compile-time /usr/share/X11/xkb data path (absent on NixOS);
      # the matching xkbcomp binary path is not overridable by flag
      # in KasmVNC 1.4, so we compensate with a /usr/bin/xkbcomp
      # symlink in systemd.tmpfiles.rules below.
      ExecStart = ''
        ${pkgs.kasmvnc}/bin/kasmvncserver :1 -fg \
          -xstartup ${xstartup} \
          -xkbdir ${pkgs.xkeyboard_config}/etc/X11/xkb
      '';

      ExecStop = "${pkgs.kasmvnc}/bin/kasmvncserver -kill :1";

      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
