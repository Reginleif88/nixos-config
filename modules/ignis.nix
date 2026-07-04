{ pkgs, lib, ... }:

# Ignis — browser-based Obsidian server for the Yggdrasil vault, fronted by a
# Cloudflare Tunnel at notes.reginleif.xyz (the tunnel is managed out-of-band and
# is intentionally NOT declared here).
#
# The app runs straight from the working tree inside the vault, as the login
# user. The shipped apps/ignis-server/scripts/deploy-install.sh can't be used on
# NixOS — it does `sudo tee /etc/systemd/system/ignis.service`, and that path is
# a symlink into the read-only Nix store. This module is the declarative
# equivalent of that script's unit + env + sudoers steps, plus a rebuild-time
# refresh so `nixos-rebuild switch` always serves the latest source.

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

  # Build the current checkout as the user. Deps are reinstalled only when the
  # lockfile changed (mtime vs a stamp), so ordinary rebuilds just re-bundle.
  # Obsidian's assets are fetched once (skipped forever after). Chromium comes
  # from pkgs.chromium (see the unit env), so setup runs with --no-chromium.
  buildScript = pkgs.writeShellScript "ignis-build" ''
    set -euo pipefail
    cd ${checkout}
    export HOME=/home/${user}
    export PATH=${buildPath}:$PATH
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    if [ ! -e node_modules/.ignis-stamp ] || [ package-lock.json -nt node_modules/.ignis-stamp ]; then
      echo "[ignis] installing deps (npm ci)"
      npm ci --no-audit --no-fund
      touch node_modules/.ignis-stamp
    fi

    if [ ! -f obsidian-app/index.html ]; then
      echo "[ignis] fetching Obsidian assets (one-time)"
      npm run setup -- --no-chromium
    fi

    echo "[ignis] building bundles"
    npm run build
  '';
in
{
  # ── Rebuild-time refresh ────────────────────────────────────────────────────
  # Runs on every `nixos-rebuild switch` (and boot): rebuild the bundles from the
  # vault, then restart the unit so the new build is served. On a failed build we
  # keep the running instance up rather than restarting into a broken tree.
  # NOTE: this shells out to npm during activation, so a rebuild that changes the
  # lockfile (or the very first one) needs network. Plain rebuilds only re-bundle
  # (offline, a few seconds).
  # `etc` is a dep so the new unit file is symlinked under /etc/systemd/system
  # before we touch it; activation scripts otherwise run before switch-to-
  # configuration writes /etc.
  system.activationScripts.ignis = {
    deps = [ "users" "groups" "etc" ];
    text = ''
      echo "[ignis] refreshing from ${checkout}"
      if ! ${pkgs.util-linux}/bin/runuser -u ${user} -- ${pullScript}; then
        echo "[ignis] vault pull failed — building from the current checkout" >&2
      fi
      if ${pkgs.util-linux}/bin/runuser -u ${user} -- ${buildScript}; then
        # Activation scripts run BEFORE switch-to-configuration's own
        # daemon-reload, so systemd still has the previous generation's unit
        # cached here. Reload first, otherwise this restart re-execs ignis
        # against the OLD unit — the exact race that left a python3-less
        # process running after python3 was first added to `path` below.
        ${pkgs.systemd}/bin/systemctl daemon-reload
        ${pkgs.systemd}/bin/systemctl restart ignis.service || true
      else
        echo "[ignis] build failed — keeping the current instance running" >&2
      fi
    '';
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
    path = [ pkgs.python3 pkgs.git ];

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

  # `npm run deploy` (= sudo systemctl restart ignis) for quick iteration between
  # full rebuilds: let the login user manage only this unit without a password.
  security.sudo.extraRules = [{
    users = [ user ];
    commands = [
      { command = "/run/current-system/sw/bin/systemctl restart ignis"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/systemctl start ignis"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/systemctl stop ignis"; options = [ "NOPASSWD" ]; }
    ];
  }];
}
