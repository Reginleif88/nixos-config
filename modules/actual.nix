_:

# Actual Budget — self-hosted, local-first personal finance app, fronted by the
# same Cloudflare Tunnel as the rest of this box. Like ignis (:8080) and
# code-server (:8081), it binds to loopback ONLY and is never exposed on the
# public firewall; the tunnel dials the local origin outbound, and Cloudflare
# Access is the authentication gate. Add the ingress route
# (e.g. budget.reginleif.xyz → http://localhost:8082) in the Cloudflare Zero
# Trust dashboard out-of-band, exactly as the notes/code-server routes were set
# up (see the ── Cloudflare Tunnel ── section in modules/ignis.nix).
#
# SECURITY — READ BEFORE CHANGING: Actual's own login is a single shared
# password, so the loopback bind is load-bearing. Never set openFirewall = true
# and never widen `hostname` off 127.0.0.1 — that would put the app on the public
# internet behind only its own password, bypassing Access.

{
  services.actual = {
    enable = true;

    # Leave user/group at their null defaults so the upstream module runs Actual
    # under a hardened systemd DynamicUser. Unlike ignis/code-server, this service
    # touches nothing the login user owns — no vault, no gh credentials — so it has
    # no reason to run as reginleif88. Its state (account.sqlite + budget blobs)
    # lives under the module's StateDirectory at /var/lib/actual and persists
    # across rebuilds and reboots on its own.

    settings = {
      # Loopback only. The upstream default is "::" (all interfaces); binding
      # 127.0.0.1 keeps the app off every public interface so the Cloudflare
      # Tunnel is the sole path in. openFirewall stays at its `false` default, so
      # nothing is punched through the public firewall either.
      hostname = "127.0.0.1";

      # 8080 = ignis, 8081 = code-server, so Actual takes 8082. Point the
      # Cloudflare ingress route at http://localhost:8082.
      port = 8082;
    };
  };
}
