{ pkgs, ... }:

{
  # Firewall: web UI + WebRTC UDP ports
  networking.firewall = {
    allowedTCPPorts = [ 8080 ];
    allowedUDPPortRanges = [{ from = 40000; to = 40100; }];
  };

  # Moonlight Web Stream — WebRTC bridge for Sunshine
  systemd.services.moonlight-web-stream = {
    description = "Moonlight Web Stream - WebRTC bridge for Sunshine";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.moonlight-web-stream}/bin/web-server";
      WorkingDirectory = "/var/lib/moonlight-web-stream";
      StateDirectory = "moonlight-web-stream";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = 5;
    };

    # Symlink immutable assets from the Nix store into the writable state dir.
    # The binary resolves ./static/ and ./streamer relative to its cwd.
    preStart = ''
      ln -sfn ${pkgs.moonlight-web-stream}/share/moonlight-web-stream/static static
      ln -sfn ${pkgs.moonlight-web-stream}/bin/streamer streamer
    '';
  };
}
