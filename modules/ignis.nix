{
  config,
  pkgs,
  lib,
  ...
}:

# Ignis — browser-based Obsidian server for the Yggdrasil vault, fronted by a
# Cloudflare Tunnel at notes.reginleif.xyz. The tunnel is now declared here too
# (see the ── Cloudflare Tunnel ── section at the bottom): a remotely-managed
# (token-auth) tunnel whose ingress routes live in the Cloudflare dashboard, run
# as a systemd unit — the declarative equivalent of `cloudflared service install
# <token>`. It dials OUTBOUND only, so it needs no inbound firewall port.
#
# The app runs from the working tree inside the vault, as the login user. NixOS
# owns the service definition; source refreshes and npm builds are explicit
# deployment services rather than side effects of `nixos-rebuild`.

let
  user = "reginleif88";
  group = "users";
  vault = "/home/reginleif88/Documents/Yggdrasil";
  checkout = "${vault}/_System/.ignis";

  # Tools needed to `npm ci` / `npm run build` / one-time `npm run setup`.
  buildPath = lib.makeBinPath [
    pkgs.nodejs_24 # node, npm, npx
    pkgs.git
    pkgs.gh # `git pull` auth: gh acts as the HTTPS credential helper
    pkgs.curl # setup.sh fetches the Obsidian .asar
    pkgs.gzip # gunzip
    pkgs.gnutar
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.bash
  ];

  # Pull the Yggdrasil vault before (re)building so a rebuild always serves the
  # latest notes. The remote is a PRIVATE HTTPS repo
  # (github.com/Reginleif88/Yggdrasil), authenticated by the `gh` CLI acting as a
  # git credential helper — it hands git the PAT stored in
  # ~/.config/gh/hosts.yml. We pin that helper explicitly (rather than leaning on
  # the user's mutable ~/.config/git/config) so the pull keeps working regardless
  # of personal git config; it only needs `gh` to stay logged in. HOME must point
  # at the user so gh finds hosts.yml, SSL_CERT_FILE supplies TLS trust, and
  # GIT_TERMINAL_PROMPT=0 makes an expired/absent token fail fast instead of
  # hanging the rebuild on an unanswerable prompt. Fast-forward only: the vault is
  # served read-write, so if the working tree is dirty or has diverged the pull
  # aborts cleanly and we keep local state rather than clobbering unsynced edits.
  # A missing upstream or auth failure is a warning, never a hard failure.
  pullScript = pkgs.writeShellScript "ignis-pull" ''
    set -euo pipefail
    export HOME=/home/${user}
    export PATH=${buildPath}:$PATH
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export GIT_TERMINAL_PROMPT=0

    cd ${vault}
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "[ignis] ${vault} is not a git repo — skipping pull"
      exit 0
    fi
    echo "[ignis] pulling Yggdrasil vault (ff-only)"
    git -c credential.helper= \
        -c credential.helper="${pkgs.gh}/bin/gh auth git-credential" \
        pull --ff-only
  '';

  # Build the current checkout as the user. npm ci follows the committed lockfile
  # on every explicit deployment, while Obsidian's downloaded assets remain a
  # one-time application artifact. Chromium comes from pkgs.chromium.
  buildScript = pkgs.writeShellScript "ignis-build" ''
    set -euo pipefail
    cd ${checkout}
    export HOME=/home/${user}
    export PATH=${buildPath}:$PATH
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    echo "[ignis] installing deps from package-lock.json"
    npm ci --no-audit --no-fund

    if [ ! -f obsidian-app/index.html ]; then
      echo "[ignis] fetching Obsidian assets (one-time)"
      npm run setup -- --no-chromium
    fi

    echo "[ignis] building bundles"
    npm run build
  '';
in
{
  # Deployment is explicit and observable. A normal NixOS switch never reaches
  # into the user's checkout, pulls network state, or runs npm.
  systemd.services.ignis-build = {
    description = "Build Ignis from the checked-out Yggdrasil source";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = group;
      ExecStart = buildScript;
    };
  };

  systemd.services.ignis-refresh = {
    description = "Pull and build the Ignis Yggdrasil checkout";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ignis-refresh" ''
        set -euo pipefail
        ${pkgs.util-linux}/bin/runuser -u ${user} -- ${pullScript}
        ${pkgs.util-linux}/bin/runuser -u ${user} -- ${buildScript}
        ${pkgs.systemd}/bin/systemctl restart ignis.service
      '';
    };
  };

  # ── The service ─────────────────────────────────────────────────────────────
  systemd.services.ignis = {
    description = "Ignis - browser-based Obsidian server (Yggdrasil)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # All app config lives in the vault's .env (${vault}/.env), loaded by the server
    # at startup (apps/ignis-server/server/load-env.js) — it is the single source of
    # truth. Only Nix-derived values remain here: they can't live in a static file.
    #   - PUPPETEER_EXECUTABLE_PATH is a per-build Nix store path (chromium updates).
    #   - HOME is the service account's home, needed by systemd/node.
    # config.js already defaults PORT/VAULT_ROOT/DATA_ROOT/OBSIDIAN_ASSETS_PATH to the
    # same values this block used to set, so they simply drop out. WS_ORIGINS and
    # VAULT_IGNORE_DIRS now come from the .env — set them there before rebuilding.
    environment = {
      PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
      HOME = "/home/${user}";
    };

    # Host spawns requested by bare name (the Terminal plugin's `python3` PTY
    # bootstrap; obsidian-git's `git`) resolve against THIS unit's PATH: the server
    # forces its own PATH onto every child it spawns for a plugin
    # (packages/server-core/src/host-bridge/providers/child-process.js, buildEnv).
    # systemd's default service PATH is only coreutils/findutils/gnugrep/gnused/
    # systemd and excludes /run/current-system/sw/bin, so a system-installed python3
    # is invisible here. Pin what plugins spawn, store-path exact — don't lean on the
    # mutable system profile. (node + Chromium avoid this by using absolute paths.)
    path = [
      pkgs.python3
      pkgs.git
    ];

    # VAULT_ROOT is a directory of vault subdirs; a single symlink exposes ONLY
    # Yggdrasil (never its ~/Documents siblings) and names the vault "Yggdrasil".
    preStart = ''
      mkdir -p ${checkout}/vaults ${checkout}/data
      ln -sfn ${vault} ${checkout}/vaults/Yggdrasil
    '';

    serviceConfig = {
      Type = "simple";
      User = user;
      Group = group;
      WorkingDirectory = checkout;
      ExecStart = "${pkgs.nodejs_24}/bin/node ${checkout}/apps/ignis-server/server/index.js";
      Restart = "on-failure";
      RestartSec = 5;

      # Sandbox, relaxed for a $HOME checkout: home stays read-only with a single
      # write hole for the vault (served read-write) — which also covers data/ and
      # vaults/ since they live inside it.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ vault ];
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
    };
  };

  # Let the login user run an explicit deployment or restart the already-built
  # service without granting general systemd control.
  security.sudo.extraRules = [
    {
      users = [ user ];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl restart ignis";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl start ignis";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop ignis";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl start ignis-build";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl start ignis-refresh";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # ── Cloudflare Tunnel ───────────────────────────────────────────────────────
  # Fronts this box's internal services (ignis :8080, code-server :8081) at their
  # public hostnames. This is a REMOTELY-managed tunnel: the ingress rules
  # (hostname → localhost:port) live in the Cloudflare Zero Trust dashboard, and
  # the box authenticates with a single connector token — the exact model of
  # `cloudflared service install <token>`. NixOS's services.cloudflared module is
  # for LOCALLY-managed tunnels (a credentials JSON + Nix-declared ingress) and
  # cannot consume a token, so we run the unit ourselves.
  #
  # The token is a live credential, so it never enters the Nix store: it lives in
  # secrets.yaml (key `cloudflared_tunnel_token`) and sops-nix renders it into a
  # root-owned 0400 EnvironmentFile at activation. systemd reads that file as root
  # (PID 1) before dropping to the DynamicUser, so the unprivileged process gets
  # $TUNNEL_TOKEN in its env without ever being able to read the file itself.
  # `cloudflared tunnel run` with no positional tunnel picks the tunnel up from
  # $TUNNEL_TOKEN.
  sops.secrets.cloudflared_tunnel_token = { };

  sops.templates."cloudflared-tunnel.env".content = ''
    TUNNEL_TOKEN=${config.sops.placeholder.cloudflared_tunnel_token}
  '';

  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel (notes.reginleif.xyz — token auth)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      EnvironmentFile = config.sops.templates."cloudflared-tunnel.env".path;
      # --no-autoupdate is mandatory on NixOS: the binary is a read-only store
      # path, so cloudflared's self-updater can only fail. Updates come from
      # bumping pkgs.cloudflared and rebuilding.
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate --loglevel info run";
      Restart = "on-failure";
      RestartSec = 5;

      # Pure outbound dialer: no privileges, no persistent state, no filesystem
      # writes needed. Runs as a throwaway DynamicUser and is boxed in tightly.
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      RestrictNamespaces = true;
      LockPersonality = true;
    };
  };
}
