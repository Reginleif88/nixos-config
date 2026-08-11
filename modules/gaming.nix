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

  environment.systemPackages = with pkgs; [
    # Bolt: native Linux Jagex Launcher (CEF-based, no Wine) that handles
    # Jagex account OAuth and launches RuneLite natively.
    bolt-launcher

    # Minecraft, official (Microsoft account) + NeoForge. Prism replaces the old
    # `pkgs.minecraft`, which nixpkgs removed on 2025-09-06 as broken (it is now a
    # throw in aliases.nix recommending exactly this). Prism also does modloader
    # setup in-app, so NeoForge 1.21.1 needs no config here.
    #
    # Must be the WRAPPED attr, never prismlauncher-unwrapped: the wrapper is what
    # supplies LD_LIBRARY_PATH (so Mojang's vendored LWJGL natives can resolve
    # libX11/libGL on a host with no /usr/lib) and PRISMLAUNCHER_JAVA_PATHS (so the
    # launcher can find jdk21 for 1.21.1). Instances live in Prism's own data dir,
    # NOT ~/.minecraft — the sklauncher/neoforge-install pair in home/apps.nix owns
    # that tree, and the two never share state.
    prismlauncher
  ];
}
