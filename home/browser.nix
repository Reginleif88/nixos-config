{ config, pkgs, inputs, lib, ... }:

let
  system = "x86_64-linux";
in
{
  # Zen Browser via flake
  home.packages = [
    inputs.zen-browser.packages.${system}.default
  ];

  # Deploy user.js to Zen profile directory
  # Profile name is random — activation script finds it
  home.activation.zenUserJs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PROFILE_DIR=$(find ${config.home.homeDirectory}/.zen -maxdepth 1 -name "*.default-release" -type d 2>/dev/null | head -1 || true)
    if [ -z "$PROFILE_DIR" ]; then
      PROFILE_DIR=$(find ${config.home.homeDirectory}/.zen -maxdepth 1 -name "*.default" -type d 2>/dev/null | head -1 || true)
    fi
    if [ -z "$PROFILE_DIR" ]; then
      echo "No Zen profile found, launching headless to generate one..."
      zen-browser --headless &
      ZEN_PID=$!
      sleep 10
      kill "$ZEN_PID" 2>/dev/null || true
      PROFILE_DIR=$(find ${config.home.homeDirectory}/.zen -maxdepth 1 -name "*.default-release" -type d 2>/dev/null | head -1 || true)
      if [ -z "$PROFILE_DIR" ]; then
        PROFILE_DIR=$(find ${config.home.homeDirectory}/.zen -maxdepth 1 -name "*.default" -type d 2>/dev/null | head -1 || true)
      fi
    fi
    if [ -n "$PROFILE_DIR" ]; then
      cp ${../dotfiles/zen-browser/user.js} "$PROFILE_DIR/user.js"
    fi
  '';
}
