{ pkgs, ... }:

let
  # Route Stremio playback to the tuned standalone mpv (home/mpv.nix) instead of
  # Stremio's embedded libmpv, which crashes the display on this Pascal/NVIDIA-580
  # box via a client-side explicit-sync fence failure. The script body lives in
  # scripts/stremio-to-mpv.sh; writeShellApplication adds the shebang + strict mode
  # and runs shellcheck at build time.
  #
  # Wired up in two places (gated to hyacinth by this module's import):
  #   - dotfiles/hypr/autostart.lua : `wl-paste --watch stremio-to-mpv --filter`
  #     auto-opens mpv when you click Stremio's "Copy Stream Link".
  #   - dotfiles/hypr/binds.lua     : SUPER+P runs `stremio-to-mpv` on demand.
  stremio-to-mpv = pkgs.writeShellApplication {
    name = "stremio-to-mpv";
    runtimeInputs = with pkgs; [
      mpv          # the player (reads ~/.config/mpv/mpv.conf from home/mpv.nix)
      wl-clipboard # wl-paste (clipboard read)
      libnotify    # notify-send on failure
      playerctl    # best-effort pause of Stremio (no-op if no MPRIS player)
      util-linux   # setsid (detach mpv from the keybind/watcher)
      coreutils    # cat, date
    ];
    text = builtins.readFile ../scripts/stremio-to-mpv.sh;
  };
in
{
  home.packages = [ stremio-to-mpv ];
}
