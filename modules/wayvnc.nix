{ config, pkgs, lib, inputs, ... }:

let
  user      = "reginleif88";
  userGroup = "users";
  uid       = 1000;
  homeDir   = "/home/${user}";

  # ── Public-facing identity ──────────────────────────────────────────
  # hostname: what the browser hits (`https://${hostname}/`). A Cloudflare
  # A record for this name must point at clematis's public IP, in DNS-only
  # mode (grey cloud, not the proxied orange cloud).
  # acmeEmail: Let's Encrypt sends expiry-warning mail here.
  hostname  = "clematis.reginleif.xyz";
  acmeEmail = "acme@reginleif.xyz";

  # Group shared between the acme renewer (writer) and websockify
  # (reader) so the latter can read fullchain.pem/key.pem without
  # being root. reginleif88 is added to this group below.
  certGroup = "wayvnc-cert";
  certDir   = config.security.acme.certs.${hostname}.directory;

  # ── Hyprland package ────────────────────────────────────────────────
  # Identical override to home/hyprland.nix:18-23. Patches a SIGSEGV
  # in upstream commit ee58a513 (device-tags null deref). If the
  # upstream PR #13728 merges and you drop the patch in home/, drop
  # it here too — both copies must update together or the headless
  # session will run a different binary than the interactive one.
  hyprlandPkg = (inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland).overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/managers/input/InputManager.cpp \
        --replace-fail 'CVarList2(Config::mgr()->getDeviceString(devname, "tags"))' 'CVarList2(std::string(""))'
    '';
  });

  websockifyAuthPlugin = pkgs.writeTextDir "websockify_file_auth.py" ''
    from websockify.auth_plugins import BasicHTTPAuth


    class ClematisHTTPAuth(BasicHTTPAuth):
        """Protect static noVNC files, but let token auth cover WebSockets."""

        def __init__(self, src=None):
            self.src = src

        def authenticate(self, headers, target_host, target_port):
            if headers.get("Upgrade", "").lower() == "websocket":
                return

            return super().authenticate(headers, target_host, target_port)

        def validate_creds(self, username, password):
            if self.src is None:
                return False

            try:
                with open(self.src, "r", encoding="utf-8") as credentials:
                    expected = credentials.read().strip()
            except OSError:
                return False

            return "%s:%s" % (username, password) == expected
  '';
in
{
  # ── Pipewire (screencast portal + future audio) ─────────────────────
  # Not pulled from modules/services.nix because that module also
  # enables bluetooth + thunar + a bunch of desktop packages that are
  # wasted on a headless Proxmox VM. Keep clematis lean.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # ── Seat manager (libseat → seatd, in VT-less mode) ─────────────────
  # Hyprland needs seat-mediated access to the VM's DRM/KMS device for the
  # Proxmox VirtIO/QEMU display. seatd is the only thing on this service-run
  # VM desktop that can provide it (logind would too, but only for an
  # "active" session on a real VT, which we don't have).
  #
  # Default seatd creates VT-bound seats: the seat is "active" only
  # when its tty is the foreground console. With no foreground VT in a
  # Proxmox guest, Hyprland's DRM session would never activate and the
  # compositor would refuse to render frames ("Attempted to render
  # frame on inactive session!").
  #
  # SEATD_VTBOUND=0 (documented in seatd(1)) tells seatd to skip VT
  # binding entirely. The resulting seat is *always active*, devices
  # get handed out as soon as a client connects, and Hyprland gets
  # drmMaster without needing a foreground VT.
  services.seatd.enable = true;
  systemd.services.seatd.serviceConfig.Environment = [ "SEATD_VTBOUND=0" ];

  # ── ACME / Let's Encrypt via Cloudflare DNS-01 ──────────────────────
  # DNS-01 avoids needing a public-facing port 80 for the HTTP-01
  # challenge. The cloudflare_dns_token sops secret must contain the
  # raw API token *only* (no `KEY=` prefix) — lego reads the file at
  # the path given in credentialFiles and the env-var name is taken
  # from the attribute key.
  #
  # The Cloudflare token needs `Zone:DNS:Edit` scoped to the zone
  # serving ${hostname}. Generate at
  # https://dash.cloudflare.com/profile/api-tokens.
  users.groups.${certGroup} = {};
  # `seat` lets the user reach /dev/dri/card0 via seatd; `${certGroup}`
  # lets websockify read fullchain.pem/key.pem from /var/lib/acme.
  users.users.${user}.extraGroups = [ "seat" certGroup ];

  security.acme = {
    acceptTerms = true;
    defaults.email = acmeEmail;
    certs.${hostname} = {
      dnsProvider = "cloudflare";
      credentialFiles = {
        "CLOUDFLARE_DNS_API_TOKEN_FILE" = config.sops.secrets.cloudflare_dns_token.path;
      };
      group = certGroup;
      # Renewal restarts websockify so the new cert is picked up.
      # ~2 s downtime every ~60-90 days; invisible if no active session.
      reloadServices = [ "websockify.service" ];
    };
  };

  # ── Firewall: only 443/TCP for the websockify entrypoint ────────────
  # wayvnc itself binds 127.0.0.1 and is never directly exposed.
  networking.firewall.allowedTCPPorts = [ 443 ];

  # ── Hyprland session for remote capture ─────────────────────────────
  # Proxmox exposes a normal virtual KMS monitor named Virtual-1, so we let
  # Hyprland use its standard DRM path instead of trying to create an
  # Aquamarine headless output. seatd (above, in VT-less mode) provides the
  # DRM fd; the user is added to the `seat` group to reach the socket.
  #
  # PAMName=login is the systemd trick that gets logind to provision
  # /run/user/${uid} with the right ownership and XDG_RUNTIME_DIR,
  # without needing user-mode systemd / lingering. The seat itself
  # comes from seatd (logind would refuse — no active VT).
  systemd.services.hyprland-headless = {
    description = "Headless Hyprland session for wayvnc capture";
    wantedBy = [ "multi-user.target" ];
    after    = [ "network.target" "pipewire.service" "seatd.service" ];
    requires = [ "seatd.service" ];

    environment = {
      XDG_SESSION_TYPE    = "wayland";
      XDG_RUNTIME_DIR     = "/run/user/${toString uid}";
      WAYLAND_DISPLAY     = "wayland-1";
      XDG_CURRENT_DESKTOP = "Hyprland";
      HOME                = homeDir;
    };

    path = with pkgs; [
      hyprlandPkg
      coreutils
      procps
      util-linux
    ];

    serviceConfig = {
      Type      = "simple";
      User      = user;
      Group     = userGroup;
      PAMName   = "login";
      Restart   = "on-failure";
      RestartSec = 5;
      # start-hyprland is Hyprland's watchdog launcher. --path keeps the
      # service pinned to the patched package above instead of relying on PATH.
      ExecStart = "${hyprlandPkg}/bin/start-hyprland --path ${hyprlandPkg}/bin/Hyprland";
    };
  };

  # ── wayvnc: Wayland VNC server, localhost-only ──────────────────────
  # Captures Virtual-1 via wlr-screencopy from the Hyprland session,
  # encodes via VAAPI on /dev/dri/renderD128 (Barcelo iGPU, provided
  # by modules/amdgpu.nix). WayVNC's native auth advertises RFB security
  # types that noVNC 1.7 does not accept, so it stays localhost-only and
  # websockify owns browser-facing HTTPS auth below.
  systemd.services.wayvnc = {
    description = "wayvnc — Wayland VNC server on 127.0.0.1:5900";
    wantedBy = [ "multi-user.target" ];
    after    = [ "hyprland-headless.service" ];
    bindsTo  = [ "hyprland-headless.service" ];

    environment = {
      WAYLAND_DISPLAY = "wayland-1";
      XDG_RUNTIME_DIR = "/run/user/${toString uid}";
      HOME            = homeDir;
    };

    serviceConfig = {
      Type      = "simple";
      User      = user;
      Group     = userGroup;
      Restart   = "on-failure";
      RestartSec = 5;

      # Tmpfs runtime dir for the rendered config — 0700, cleaned on stop.
      RuntimeDirectory     = "wayvnc";
      RuntimeDirectoryMode = "0700";

      ExecStartPre = pkgs.writeShellScript "wayvnc-prestart" ''
        set -eu

        # Wait for Hyprland's Wayland socket and Virtual-1 monitor to appear.
        # If Hyprland crashed or the VM display vanished, fail fast instead
        # of starting wayvnc against a missing/incorrect output.
        find_hypr_instance() {
          for dir in "$XDG_RUNTIME_DIR"/hypr/*; do
            [ -S "$dir/.socket.sock" ] || continue
            [ "$(${pkgs.gnused}/bin/sed -n '2p' "$dir/hyprland.lock" 2>/dev/null || true)" = "$WAYLAND_DISPLAY" ] || continue
            export HYPRLAND_INSTANCE_SIGNATURE="''${dir##*/}"
            return 0
          done
          return 1
        }

        have_virtual_monitor() {
          find_hypr_instance || return 1
          ${hyprlandPkg}/bin/hyprctl -j monitors 2>/dev/null \
            | ${pkgs.jq}/bin/jq -e '.[] | select(.name == "Virtual-1" and .disabled == false)' >/dev/null
        }

        for i in $(seq 30); do
          [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && have_virtual_monitor && break
          sleep 1
        done
        if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] || ! have_virtual_monitor; then
          echo "Hyprland Wayland socket or Virtual-1 monitor not ready after 30s, aborting" >&2
          exit 1
        fi

        # RUNTIME_DIRECTORY is /run/wayvnc, tmpfs, 0700, owned by user.
        cat > "$RUNTIME_DIRECTORY/config" <<EOF
        address=127.0.0.1
        port=5900
        enable_auth=false
        EOF
        chmod 600 "$RUNTIME_DIRECTORY/config"
      '';

      # -r: render cursor in framebuffer so it shows over VNC.
      # -f 60: cap framerate; matches max_frame_rate from old kasmvnc.
      # -o Virtual-1: capture the Proxmox virtual KMS display explicitly.
      # -C: config file path with auth + bind address.
      #
      # Do not pass -g here. On clematis, wayvnc's GPU path tries to allocate
      # KMS dumb buffers on client connect and crashes after
      # DRM_IOCTL_MODE_CREATE_DUMB returns EPERM. The software path is less
      # fancy, but keeps the browser desktop stable.
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc -r -f 60 -o Virtual-1 -C %t/wayvnc/config";
    };

  };

  # ── websockify: TLS terminator + noVNC bundle on :443 ───────────────
  # The single public-facing process. Serves noVNC's HTML/JS to the
  # browser AND bridges the wss:// connection to wayvnc's raw RFB on
  # 127.0.0.1:5900. The custom web root makes / redirect into noVNC with
  # same-origin websocket settings, avoiding stale browser-local host/port
  # values from earlier tests. Basic auth protects the static web UI. The
  # websocket itself uses a per-service-start token because browsers do not
  # reliably carry Basic Auth headers into WebSocket upgrades. CAP_NET_BIND_SERVICE
  # lets it bind <1024 as a non-root user.
  systemd.services.websockify = {
    description = "websockify — TLS + noVNC bridge to wayvnc on :443";
    wantedBy = [ "multi-user.target" ];
    after    = [ "wayvnc.service" "acme-${hostname}.service" ];

    environment = {
      PYTHONPATH = websockifyAuthPlugin;
    };

    serviceConfig = {
      Type      = "simple";
      User      = user;
      Group     = userGroup;
      Restart   = "on-failure";
      RestartSec = 5;
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      RuntimeDirectory     = "websockify";
      RuntimeDirectoryMode = "0700";

      ExecStartPre = pkgs.writeShellScript "websockify-prestart" ''
        set -eu

        webroot="$RUNTIME_DIRECTORY/webroot"
        rm -rf "$webroot"
        mkdir -p "$webroot"

        for path in ${pkgs.novnc}/share/webapps/novnc/*; do
          ln -s "$path" "$webroot/$(${pkgs.coreutils}/bin/basename "$path")"
        done

        password=$(cat ${config.sops.secrets.wayvnc_password.path})
        token="$(${pkgs.openssl}/bin/openssl rand -hex 24)"

        printf '%s:%s\n' '${user}' "$password" > "$RUNTIME_DIRECTORY/credentials"
        chmod 600 "$RUNTIME_DIRECTORY/credentials"

        printf '%s: 127.0.0.1:5900\n' "$token" > "$RUNTIME_DIRECTORY/tokens"
        chmod 600 "$RUNTIME_DIRECTORY/tokens"

        cat > "$webroot/index.html" <<EOF
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="refresh" content="0; url=/vnc.html?autoconnect=1&amp;reconnect=1&amp;reconnect_delay=1000&amp;resize=scale&amp;path=websockify%3Ftoken%3D$token&amp;host=&amp;port=">
            <title>clematis</title>
          </head>
          <body>
            <script>
              const params = new URLSearchParams({
                autoconnect: "1",
                reconnect: "1",
                reconnect_delay: "1000",
                resize: "scale",
                path: "websockify?token=$token",
                host: "",
                port: ""
              });
              window.location.replace("/vnc.html?" + params.toString());
            </script>
            <a href="/vnc.html?autoconnect=1&amp;reconnect=1&amp;reconnect_delay=1000&amp;resize=scale&amp;path=websockify%3Ftoken%3D$token&amp;host=&amp;port=">Open noVNC</a>
          </body>
        </html>
        EOF

        cat > "$webroot/defaults.json" <<EOF
        {
          "autoconnect": true,
          "reconnect": true,
          "reconnect_delay": 1000,
          "resize": "scale",
          "path": "websockify?token=$token",
          "host": "",
          "port": ""
        }
        EOF

        cat > "$webroot/mandatory.json" <<EOF
        {
          "path": "websockify?token=$token",
          "host": "",
          "port": ""
        }
        EOF
      '';

      ExecStart = lib.concatStringsSep " " [
        "${pkgs.python3Packages.websockify}/bin/websockify"
        "--cert=${certDir}/fullchain.pem"
        "--key=${certDir}/key.pem"
        "--web=%t/websockify/webroot"
        "--web-auth"
        "--auth-plugin=websockify_file_auth.ClematisHTTPAuth"
        "--auth-source=%t/websockify/credentials"
        "--token-plugin=TokenFile"
        "--token-source=%t/websockify/tokens"
        "--file-only"
        "--ssl-only"
        "443"
      ];
    };

    restartTriggers = [
      config.sops.secrets.wayvnc_password.path
    ];
  };
}
