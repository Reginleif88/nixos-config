{ pkgs, ... }:

# Browser-accessible VS Code (code-server) for editing the Yggdrasil vault.
# The Cloudflare Tunnel runs on this same OVH VPS and connects to the local
# origin over loopback, so code-server never needs a public bind address.
#
# SECURITY — READ BEFORE CHANGING: code-server runs with `--auth none` because
# Cloudflare Access is the authentication gate, exactly as Ignis relies on it.
# The integrated terminal is a full shell as ${user}, and the editor can
# read/write anything ${user} can — so the firewall rule restricting :8081 to the
# loopback bind is load-bearing. Never widen it to the LAN, and never expose
# :8081 without Access in front. For defense-in-depth you can instead set
# `auth = "password"` here with a sops-managed `hashedPassword`.

let
  user = "reginleif88";
  vault = "/home/${user}/Documents/Yggdrasil";
in
{
  services.code-server = {
    enable = true;

    # Run as the login user so the editor and its integrated terminal touch the
    # vault (and use the user's git/gh credentials) with the right ownership —
    # the same account Ignis runs as. The module only auto-creates a user when
    # `user` is left at its default, so naming an existing user just merges into
    # that account rather than clashing with it.
    user = user;
    group = "users";

    host = "127.0.0.1";
    port = 8081;

    auth = "none"; # Cloudflare Access is the gate — see header.
    disableTelemetry = true;
    disableUpdateCheck = true;
    disableWorkspaceTrust = true; # it's our own vault; skip the trust prompt.

    # Open the vault by default (the positional path is appended last to the
    # code-server CLI).
    extraArguments = [ vault ];
  };

  # code-server's built-in Source Control shells out to `git`, resolved against
  # THIS unit's PATH — and systemd's default service PATH excludes git (the same
  # trap that hid python3 from Ignis's terminal, see modules/ignis.nix). Pin
  # git + gh (gh is the git credential helper for the private vault repo) onto
  # the service PATH so the SCM panel and pushes work. The integrated terminal,
  # being a login shell, already inherits the user's full profile.
  systemd.services.code-server.path = [
    pkgs.git
    pkgs.gh
  ];
}
