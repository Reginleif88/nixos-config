{ pkgs, ... }:

let
  # Route Stremio playback to the tuned standalone mpv (home/mpv.nix) instead of
  # Stremio's embedded libmpv, which crashes the display on this Pascal/NVIDIA-580
  # box via a client-side explicit-sync fence failure. The script body lives in
  # scripts/stremio-to-mpv.sh; writeShellApplication adds the shebang + strict mode
  # and runs shellcheck at build time.
  #
  # Wired up (gated to hyacinth by this module's import):
  #   - dotfiles/hypr/autostart.lua : `stremio-to-mpv --watch-storage` auto-opens mpv
  #     when you click Play in Stremio (watches leveldb for the resolved stream URL);
  #     `wl-paste --watch stremio-to-mpv --filter` does the same on "Copy Stream Link".
  #   - dotfiles/hypr/binds.lua     : SUPER+P runs `stremio-to-mpv` on demand.
  stremio-to-mpv = pkgs.writeShellApplication {
    name = "stremio-to-mpv";
    runtimeInputs = with pkgs; [
      mpv          # the player (reads ~/.config/mpv/mpv.conf from home/mpv.nix)
      wl-clipboard # wl-paste (clipboard read)
      libnotify    # notify-send on failure
      pulseaudio   # pactl — mute/unmute Stremio's stream (no MPRIS to pause it)
      gawk         # parse pactl sink-inputs for Stremio's stream id
      gnugrep      # grep -a over leveldb for the stream URL + resume timeOffset
      inotify-tools # inotifywait — watch leveldb so Play auto-opens mpv
      util-linux   # setsid (detach the play worker from the keybind/watcher)
      coreutils    # cat, date, ls, head
    ];
    text = builtins.readFile ../scripts/stremio-to-mpv.sh;
  };
in
{
  home.packages = [ stremio-to-mpv ];
}
