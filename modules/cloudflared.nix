{ config, pkgs, ... }:

{
  sops.secrets."cloudflared_token" = {};

  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "cloudflared-tunnel" ''
        exec ${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run \
          --token "$(cat "$CREDENTIALS_DIRECTORY/token")"
      '';
      LoadCredential = "token:${config.sops.secrets."cloudflared_token".path}";
      Restart = "always";
      RestartSec = 5;
      DynamicUser = true;
    };
  };
}
