# stremio-to-mpv — play a Stremio "Copy Stream Link" URL in the tuned host mpv.
#
# Why this exists: Stremio's embedded libmpv intermittently crashes the display on
# this Pascal/NVIDIA-580 box via a client-side explicit-sync fence failure
# (`nv_drm_semsurf_fence_wait_ioctl ... invalid sync FD`). The standalone player in
# home/mpv.nix doesn't, and is tuned for judder-free 24fps. This routes actual
# watching to that player. mpv reads ~/.config/mpv/mpv.conf on its own; we only add
# window flags here.
#
# Modes:
#   stremio-to-mpv            read the current clipboard and play it (lenient match).
#   stremio-to-mpv <url>      play <url> (lenient match).
#   stremio-to-mpv --filter   read a clipboard value on stdin (wl-paste --watch mode);
#                             play it ONLY if it looks like a stream URL (strict),
#                             debounced. Always exits 0 so the watcher never dies.
#   stremio-to-mpv --selftest run the URL-matching assertions and exit.

# Strict: the auto-watcher must only fire on something clearly playable, so ordinary
# copied text/links never launch mpv. Anchored at start; the media-extension branch is
# anchored at end so query/fragment is allowed but trailing junk is not.
strict_re='^(http://(127\.0\.0\.1|localhost):11470/|https?://[^[:space:]]+\.(mkv|mp4|avi|m4v|webm|m3u8|ts)([?#].*)?$|https?://[^[:space:]]*real-debrid\.com/)'
# Lenient: a deliberate hotkey/arg only needs to be some http(s) URL.
lenient_re='^https?://[^[:space:]]+$'

play() {
  local url=$1
  # Best-effort: hush Stremio if it exposes an MPRIS player (it usually doesn't).
  playerctl pause 2>/dev/null || true
  # Detach so the keybind / watcher returns immediately and mpv outlives them.
  setsid --fork mpv --fullscreen --force-window=immediate -- "$url" \
    >/dev/null 2>&1 </dev/null || true
}

fail() {
  notify-send "Stremio → mpv" "$1" 2>/dev/null || true
  exit 1
}

case ${1:-} in
  --filter)
    IFS=$'\n' read -r url <<<"$(cat)" || true   # first line of the new clipboard value
    [[ ${url:-} =~ $strict_re ]] || exit 0       # ignore non-stream clipboard quietly
    # Debounce: skip an identical URL seen within the last 10s (duplicate events).
    state=${XDG_RUNTIME_DIR:-/tmp}/stremio-to-mpv.last
    now=$(date +%s)
    if [[ -f $state ]]; then
      IFS='|' read -r last_t last_u <"$state" || true
      if [[ ${last_u:-} == "$url" && $((now - ${last_t:-0})) -lt 10 ]]; then
        exit 0
      fi
    fi
    printf '%s|%s\n' "$now" "$url" >"$state"
    play "$url"
    ;;
  --selftest)
    rc=0
    should_match=(
      "http://127.0.0.1:11470/abc123/0"
      "http://localhost:11470/stream.mkv"
      "https://x.download.real-debrid.com/d/CODE/Show.S01E01.1080p.mkv"
      "https://host/path/Movie.2160p.mp4?token=1"
      "https://cdn.example/clip.webm"
    )
    should_not=(
      "hello world"
      "https://www.youtube.com/watch?v=abc"
      "http://example.com/page.html"
      ""
      "ftp://host/file.mkv"
    )
    for u in "${should_match[@]}"; do
      if [[ ! $u =~ $strict_re ]]; then echo "FAIL (should match): $u"; rc=1; fi
    done
    for u in "${should_not[@]}"; do
      if [[ $u =~ $strict_re ]]; then echo "FAIL (should NOT match): $u"; rc=1; fi
    done
    if [[ $rc -eq 0 ]]; then echo "stremio-to-mpv selftest: OK"; fi
    exit $rc
    ;;
  "")
    url=$(wl-paste --no-newline 2>/dev/null || true)
    [[ ${url:-} =~ $lenient_re ]] || fail "No stream URL on the clipboard. Use Stremio's \"Copy Stream Link\" first."
    play "$url"
    ;;
  *)
    url=$1
    [[ $url =~ $lenient_re ]] || fail "Not a URL: $url"
    play "$url"
    ;;
esac
