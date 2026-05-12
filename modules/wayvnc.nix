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
  users.users.${user}.extraGroups = [ certGroup ];

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
  # WLR_BACKENDS=headless makes wlroots create no real outputs; the
  # virtual HEADLESS-1 monitor is spawned in dotfiles/hypr/hosts/
  # clematis/monitors.lua via `hyprctl output create headless`.
  #
  # PAMName=login is the systemd trick that gets logind to provision
  # /run/user/${uid} with the right ownership and XDG_RUNTIME_DIR,
  # without needing user-mode systemd / lingering.
  systemd.services.hyprland-headless = {
    description = "Headless Hyprland session for wayvnc capture";
    wantedBy = [ "multi-user.target" ];
    after    = [ "network.target" "pipewire.service" ];

    environment = {
      WLR_BACKENDS            = "headless";
      WLR_LIBINPUT_NO_DEVICES = "1";
      XDG_SESSION_TYPE        = "wayland";
      XDG_RUNTIME_DIR         = "/run/user/${toString uid}";
      WAYLAND_DISPLAY         = "wayland-1";
      XDG_CURRENT_DESKTOP     = "Hyprland";
      HOME                    = homeDir;
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
