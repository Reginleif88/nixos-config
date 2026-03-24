{ pkgs, inputs, ... }:

let
  system = "x86_64-linux";
in
{
  # Steam with Proton support
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    gamescopeSession.enable = true;
  };

  # DawnProton custom Proton build
  programs.steam.extraCompatPackages = [
    inputs.dwproton.packages.${system}."dw-proton"
  ];

  # 32-bit graphics support (required by Steam)
  hardware.graphics.enable32Bit = true;
}
