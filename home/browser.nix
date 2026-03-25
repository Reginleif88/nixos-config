{ config, pkgs, inputs, lib, ... }:

let
  system = "x86_64-linux";
in
{
  # Zen Browser via flake
  home.packages = [
    inputs.zen-browser.packages.${system}.default
  ];

  # Deploy user.js and policies to Zen profile directory
  # Profile name is random — activation script finds it
  home.activation.zenUserJs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ZEN_DIR="${config.home.homeDirectory}/.config/zen"
    PROFILE_DIR=$(find "$ZEN_DIR" -maxdepth 1 -name "*.Default*" -type d 2>/dev/null | head -1 || true)
    if [ -z "$PROFILE_DIR" ]; then
      PROFILE_DIR=$(find "$ZEN_DIR" -maxdepth 1 -name "*.default*" -type d 2>/dev/null | head -1 || true)
    fi
    if [ -n "$PROFILE_DIR" ]; then
      install -m 644 ${../dotfiles/zen-browser/user.js} "$PROFILE_DIR/user.js"
    fi

    # Deploy enterprise policies for auto-installing extensions
    mkdir -p "$ZEN_DIR/distribution"
    install -m 644 ${../dotfiles/zen-browser/policies.json} "$ZEN_DIR/distribution/policies.json"
  '';
}
