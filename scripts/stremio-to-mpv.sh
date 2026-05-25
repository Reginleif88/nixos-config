# stremio-to-mpv — play a Stremio stream URL in the tuned host mpv.
#
# Why this exists: Stremio's embedded libmpv intermittently crashes the display on
# this Pascal/NVIDIA-580 box via a client-side explicit-sync fence failure
# (`nv_drm_semsurf_fence_wait_ioctl ... invalid sync FD`). The standalone player in
# home/mpv.nix doesn't, and is tuned for judder-free 24fps. This routes actual
# watching to that player. mpv reads ~/.config/mpv/mpv.conf on its own; we add
# window/audio flags + a best-effort resume position here.
#
# Triggers (all funnel into the same play worker):
#   --filter         read a clipboard value on stdin (wl-paste --watch mode) and
#                    launch if it's a stream URL — auto-open on "Copy Stream Link".
#   <none>           read the current clipboard and play it (SUPER+P hotkey).
#   <url>            play this URL.
# Internal / utility:
#   --play <url>     worker: mute Stremio, run mpv (foreground), unmute on exit.
#                    Spawned detached so triggers return immediately.
#   --selftest       run the URL-matching assertions and exit.

# Strict: watchers must only fire on something clearly playable, so ordinary copied
# text/links and addon/manifest URLs never launch mpv.
strict_re='^(http://(127\.0\.0\.1|localhost):11470/|https?://[^[:space:]]+\.(mkv|mp4|avi|m4v|webm|m3u8|ts)([?#].*)?$|https?://[^[:space:]]*real-debrid\.com/)'
# Lenient: a deliberate hotkey/arg only needs to be some http(s) URL.
lenient_re='^https?://[^[:space:]"]+$'

leveldb_dir="$HOME/.var/app/com.stremio.Stremio/data/Smart Code ltd/Stremio/QtWebEngine/Default/Local Storage/leveldb"

# Mute/unmute Stremio's PipeWire stream(s). Stremio exposes no MPRIS and Hyprland's
# key-send is unavailable under Lua config, so muting the audio stream is the only
# reliable way to stop double audio. $1: 1=mute, 0=unmute.
set_stremio_mute() {
  local val=$1 id
  pactl list sink-inputs 2>/dev/null \
    | awk 'BEGIN { RS = "Sink Input #" } NR > 1 && /application\.name = "Stremio"/ { print $1 }' \
    | while read -r id; do
        [[ -n $id ]] && pactl set-sink-input-mute "$id" "$val" 2>/dev/null || true
      done
  return 0
}

# Best-effort resume: Stremio writes the current item's "timeOffset" (ms) into leveldb.
# Grab the most recent value; only resume if past 30s so a fresh start gets no bogus
# seek. Heuristic — often inert (the live position isn't always there); self-disables.
stremio_resume_secs() {
  local newest ms s
  # shellcheck disable=SC2012
  newest=$(ls -t "$leveldb_dir"/*.log "$leveldb_dir"/*.ldb 2>/dev/null | head -1) || return 0
  [[ -n ${newest:-} ]] || return 0
  ms=$(grep -aoE 'timeOffset":[0-9]+' "$newest" 2>/dev/null | tail -1 | grep -oE '[0-9]+$') || return 0
  [[ -n ${ms:-} ]] || return 0
  s=$((ms / 1000))
  if ((s > 30)); then printf '%s' "$s"; fi
  return 0
}

fail() {
  notify-send "Stremio → mpv" "$1" 2>/dev/null || true
  exit 1
}

# Always launch (explicit user action): spawn the play worker detached.
play_now() { setsid --fork "$0" --play "$1" >/dev/null 2>&1 </dev/null || true; }

# Watcher launch: change-detection against the last URL we launched, shared across the
# storage + clipboard watchers. Skips relaunch while the same stream keeps being
# rewritten to leveldb (progress saves) and de-dupes the two watchers; a genuinely new
# stream URL launches immediately. The hotkey/arg paths bypass this (always launch).
launch_guarded() {
  local url=$1 state
  state=${XDG_RUNTIME_DIR:-/tmp}/stremio-to-mpv.lasturl
  if [[ -f $state && "$(cat "$state" 2>/dev/null)" == "$url" ]]; then return 0; fi
  printf '%s' "$url" >"$state"
  play_now "$url"
}

case ${1:-} in
  --play)
    url=${2:-}
    [[ -n $url ]] || exit 0
    secs=$(stremio_resume_secs) || secs=""
    # Subtitles: dual-audio anime embeds English ASS subs not flagged "default", so mpv
    # shows none without an explicit --slang, and skips them when audio matches. --slang
    # + subs-with-matching-audio=yes force English subs on; --subs-fallback-forced=no
    # makes mpv pick the FULL dialogue track instead of the forced Signs/Songs one under
    # the English dub (switch tracks live with `j`).
    mpv_args=(--fullscreen --force-window=immediate "--alang=eng,en" "--slang=eng,en"
      --subs-with-matching-audio=yes --subs-fallback-forced=no)
    [[ -n ${secs:-} ]] && mpv_args+=(--start="$secs")
    set_stremio_mute 1
    trap 'set_stremio_mute 0' EXIT
    mpv "${mpv_args[@]}" -- "$url" >/dev/null 2>&1 </dev/null || true
    ;;
  --filter)
    IFS=$'\n' read -r url <<<"$(cat)" || true   # first line of the new clipboard value
    [[ ${url:-} =~ $strict_re ]] || exit 0       # ignore non-stream clipboard quietly
    launch_guarded "$url"
    ;;
  --selftest)
    rc=0
    should_match=(
      "http://127.0.0.1:11470/abc123/0"
      "http://localhost:11470/stream.mkv"
      "https://x.download.real-debrid.com/d/CODE/Show.S01E01.1080p.mkv"
      "https://host/path/Movie.2160p.mp4?token=1"
      "https://cdn.example/clip.webm"
      "https://torrentio.strem.fun/resolve/realdebrid/CODE/HASH/null/19/S01E20-Advent%20of%20the%20Demon.mkv"
    )
    should_not=(
      "hello world"
      "https://www.youtube.com/watch?v=abc"
      "http://example.com/page.html"
      ""
      "ftp://host/file.mkv"
      "https://torrentio.strem.fun/manifest.json"
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
    play_now "$url"
    ;;
  *)
    url=$1
    [[ $url =~ $lenient_re ]] || fail "Not a URL: $url"
    play_now "$url"
    ;;
esac
