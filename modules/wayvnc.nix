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
  # Aquamarine's GBM allocator needs an open /dev/dri/card0 fd, even on
  # headless outputs. card0 requires seat-mediated access; seatd is the
  # only thing on a headless VM that can provide it (logind would too,
  # but only for an "active" session on a real VT, which we don't have).
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

  # ── Headless Hyprland session ───────────────────────────────────────
  # Hyprland 0.55+ uses Aquamarine, which requests the HEADLESS backend
  # as MANDATORY (Compositor.cpp:316) but also probes DRM as
  # REQUEST_IF_AVAILABLE — and the GBM allocator backing the headless
  # backend needs a real DRM device fd, so DRM has to succeed for the
  # whole thing to come up. seatd (above, in VT-less mode) provides
  # that fd; the user is added to the `seat` group to reach the socket.
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
      ExecStart = "${hyprlandPkg}/bin/Hyprland";
    };
  };

  # ── wayvnc: Wayland VNC server, localhost-only ──────────────────────
  # Captures via wlr-screencopy from the headless Hyprland session,
  # encodes via VAAPI on /dev/dri/renderD128 (Barcelo iGPU, provided
  # by modules/amdgpu.nix). Auth config is rendered into a tmpfs
  # file at preStart so the password from sops never lands on disk.
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

        # Wait for Hyprland's Wayland socket to appear. If Hyprland
        # crashed at startup we want wayvnc to fail fast, not loop
        # forever — 30 s ceiling is enough for a healthy boot.
        for i in $(seq 30); do
          [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && break
          sleep 1
        done
        if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
          echo "Hyprland Wayland socket not present after 30s, aborting" >&2
          exit 1
        fi

        # Render the wayvnc config file with the password from sops.
        # RUNTIME_DIRECTORY is /run/wayvnc, tmpfs, 0700, owned by user.
        password=$(cat ${config.sops.secrets.wayvnc_password.path})
        cat > "$RUNTIME_DIRECTORY/config" <<EOF
        address=127.0.0.1
        port=5900
        enable_auth=true
        username=${user}
        password=$password
        EOF
        chmod 600 "$RUNTIME_DIRECTORY/config"
      '';

      # -g: prefer GPU-accelerated encoder (VAAPI H.264 on Barcelo).
      # -r: render cursor in framebuffer so it shows over VNC.
      # -f 60: cap framerate; matches max_frame_rate from old kasmvnc.
      # -C: config file path with auth + bind address.
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc -g -r -f 60 -C %t/wayvnc/config";
    };

    restartTriggers = [
      config.sops.secrets.wayvnc_password.path
    ];
  };

  # ── websockify: TLS terminator + noVNC bundle on :443 ───────────────
  # The single public-facing process. Serves noVNC's HTML/JS to the
  # browser AND bridges the wss:// connection to wayvnc's raw RFB on
  # 127.0.0.1:5900. CAP_NET_BIND_SERVICE lets it bind <1024 as a
  # non-root user.
  systemd.services.websockify = {
    description = "websockify — TLS + noVNC bridge to wayvnc on :443";
    wantedBy = [ "multi-user.target" ];
    after    = [ "wayvnc.service" "acme-${hostname}.service" ];

    serviceConfig = {
      Type      = "simple";
      User      = user;
      Group     = userGroup;
      Restart   = "on-failure";
      RestartSec = 5;
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];

      ExecStart = lib.concatStringsSep " " [
        "${pkgs.python3Packages.websockify}/bin/websockify"
        "--cert=${certDir}/fullchain.pem"
        "--key=${certDir}/key.pem"
        "--web=${pkgs.novnc}/share/webapps/novnc"
        "--ssl-only"
        "443"
        "127.0.0.1:5900"
      ];
    };
  };
}
