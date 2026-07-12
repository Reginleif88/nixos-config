{ pkgs, inputs, ... }:

let
  system = "x86_64-linux";
in
{
  # Steam with Proton support
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  # DawnProton custom Proton build
  programs.steam.extraCompatPackages = [
    inputs.dwproton.packages.${system}."dw-proton"
  ];

  # 32-bit graphics support (required by Steam)
  hardware.graphics.enable32Bit = true;

  # Bolt: native Linux Jagex Launcher (CEF-based, no Wine) that handles
  # Jagex account OAuth and launches RuneLite natively.
  environment.systemPackages = with pkgs; [ bolt-launcher ];
}
