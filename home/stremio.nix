{ pkgs, config, lib, ... }:

let
  # Compile the LD_PRELOAD shim from tracked source. It references only
  # GLIBC_2.34 symbols, so this nixpkgs build is ABI-compatible with the Stremio
  # Flatpak runtime (org.kde.Platform//5.15-24.08, glibc 2.39).
  shim = pkgs.runCommandCC "stremio-mpv-shim" { } ''
    mkdir -p "$out/lib"
    $CC -shared -fPIC -O2 -o "$out/lib/shim.so" ${./stremio-mpv-shim.c} -ldl
  '';

  # Stable, real (non-symlink) path the Flatpak sandbox can read via --filesystem.
  # Must not be a /nix/store symlink, or the sandbox couldn't follow it.
  shimDir = "${config.home.homeDirectory}/.local/share/stremio-mpv-shim";
in
{
  # Force display-synced presentation into Stremio's embedded, otherwise
  # unconfigurable libmpv -- fixes the 23.976fps-on-144Hz cadence judder while
  # keeping Stremio's normal click-and-play flow. See stremio-mpv-shim.c.
  #
  # Re-asserted on every rebuild (idempotent). To disable:
  #   flatpak override --user --reset com.stremio.Stremio
  # Stremio must be fully restarted to pick up changes:
  #   flatpak kill com.stremio.Stremio && flatpak run com.stremio.Stremio
  home.activation.stremioMpvShim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm0644 ${shim}/lib/shim.so "${shimDir}/shim.so"
    fp="$(command -v flatpak || true)"
    [ -x "$fp" ] || fp=/run/current-system/sw/bin/flatpak
    if [ -x "$fp" ]; then
      "$fp" override --user com.stremio.Stremio \
        --filesystem="${shimDir}:ro" \
        --env=LD_PRELOAD="${shimDir}/shim.so" || true
    fi
  '';
}
