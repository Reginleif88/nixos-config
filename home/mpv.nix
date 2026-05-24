{ ... }:

{
  # Go-to video player for actually *watching* (Stremio stays for discovery).
  # Tuned to defeat the 23.976fps-on-144Hz judder that Stremio's bundled,
  # unconfigurable Flatpak mpv can't avoid.
  programs.mpv = {
    enable = true;
    config = {
      # ── The actual fix for the "weird refresh, sometimes" judder ─────────
      # 23.976 fps does not divide evenly into 143.999 Hz (ratio 6.006), so a
      # naive player shows each frame for 6 refreshes and inserts a 7-refresh
      # "catch-up" frame roughly every ~7 s — a periodic visible hitch. With
      # display-resample, mpv instead stretches the audio ~0.1% (inaudible,
      # pitch-corrected) to lock onto the real display clock, so every video
      # frame gets an exactly-even number of refreshes. interpolation +
      # oversample further smooth the stepping with minimal motion blur.
      # Prefer the pure 24fps film look? Set interpolation = false.
      video-sync = "display-resample";
      interpolation = true;
      tscale = "oversample";

      # ── Output: NVIDIA Pascal (GTX 1080) + 580.x on Wayland/Hyprland ─────
      # gpu-next has the best Wayland presentation timing; gpu-hq pulls in the
      # high-quality scaler/dither defaults. (If you ever see artifacts, try
      # gpu-api = "vulkan" or fall back to vo = "gpu".)
      vo = "gpu-next";
      profile = "gpu-hq";

      # Real NVDEC works in standalone mpv (the Flatpak's mpv never engaged it).
      # auto-safe only enables hwdec methods known not to break rendering;
      # it falls back to software if interop isn't safe.
      hwdec = "auto-safe";

      # ── Streaming cache (you'll feed it debrid/HTTP URLs) ────────────────
      # A few seconds of read-ahead absorbs the bursty Real-Debrid delivery.
      cache = true;
      demuxer-max-bytes = "150MiB";
      demuxer-readahead-secs = 20;

      # ── Quality-of-life ──────────────────────────────────────────────────
      keep-open = true;            # don't close at end-of-file
      save-position-on-quit = true; # resume episodes where you left off
      sub-auto = "fuzzy";          # pick up loosely-named sidecar subtitles
    };
  };

  # Make mpv the default handler for local video files. Merges with the
  # text/http associations defined in apps.nix (xdg.mimeApps is enabled there).
  xdg.mimeApps.defaultApplications = {
    "video/mp4"        = "mpv.desktop";
    "video/x-matroska" = "mpv.desktop";
    "video/webm"       = "mpv.desktop";
    "video/quicktime"  = "mpv.desktop";
    "video/x-msvideo"  = "mpv.desktop";
    "video/mpeg"       = "mpv.desktop";
  };
}
