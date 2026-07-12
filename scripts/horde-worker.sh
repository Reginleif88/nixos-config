#!/usr/bin/env bash
# Temporary AI Horde image worker (Dreamer) — runs horde-worker-reGen.
#
# All state (cloned repo, Miniconda runtime, model cache) lives under
# $HORDE_DIR (default ~/.cache/horde-worker-reGen). Nothing is added to
# the NixOS configuration; the worker runs inside `steam-run` (FHS env)
# so conda + CUDA wheels behave normally.
#
# This script is pinned to reGen v9.0.7 (the last tag before reGen bumped
# torch past 2.4.x) because hyacinth's GTX 1080 is Pascal (sm_61), which
# PyTorch 2.5+ wheels no longer include kernels for. cu121 + torch 2.3.1
# is the last "supported" stack for Pascal.
#
# Usage:
#   HORDE_API_KEY=xxx ./scripts/horde-worker.sh        # start worker
#   HORDE_API_KEY=xxx ./scripts/horde-worker.sh --update  # refresh runtime
#   HORDE_API_KEY=xxx ./scripts/horde-worker.sh --reset   # wipe conda env, reinstall
#   Ctrl-C to stop. State persists, so the next start is fast.
set -euo pipefail

HORDE_DIR="${HORDE_DIR:-$HOME/.cache/horde-worker-reGen}"
HORDE_REF="${HORDE_REF:-v9.0.7}"
DO_UPDATE=0
DO_RESET=0
for arg in "$@"; do
  case "$arg" in
    --update) DO_UPDATE=1 ;;
    --reset)  DO_RESET=1; DO_UPDATE=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [[ -z "${HORDE_API_KEY:-}" ]]; then
  echo "HORDE_API_KEY is not set. Export it (or paste your key into bridgeData.yaml manually)." >&2
  exit 1
fi

# ── Clone or update the worker repo, then pin to $HORDE_REF ──────────
if [[ ! -d "$HORDE_DIR/.git" ]]; then
  echo "[1/3] Cloning horde-worker-reGen → $HORDE_DIR"
  mkdir -p "$(dirname "$HORDE_DIR")"
  git clone https://github.com/Haidra-Org/horde-worker-reGen.git "$HORDE_DIR"
fi
echo "[1/3] Pinning repo to $HORDE_REF"
git -C "$HORDE_DIR" fetch --tags --quiet origin
git -C "$HORDE_DIR" checkout --quiet "$HORDE_REF"
cd "$HORDE_DIR"

# Reset wipes the conda env so update-runtime.sh rebuilds it cleanly.
# Needed when the pinned torch version changes (e.g. coming from a broken
# 2.9.1 install built off main).
if [[ $DO_RESET -eq 1 && -d "$HORDE_DIR/conda" ]]; then
  echo "    → --reset: removing $HORDE_DIR/conda"
  for path in "$HORDE_DIR/conda" "$HORDE_DIR/bin"; do
    if [[ -e "$path" ]]; then
      rm -rf -- "$path"
    fi
  done
fi

# ── Seed bridgeData.yaml on first run ─────────────────────────────────
if [[ ! -f bridgeData.yaml ]]; then
  echo "[2/3] Seeding bridgeData.yaml from template"
  cp bridgeData_template.yaml bridgeData.yaml
  # Only set api_key automatically — every other field has a sane template
  # default and the user can edit bridgeData.yaml directly if they want to
  # tune worker name, model list, max_threads, etc.
  python3 - "$HORDE_API_KEY" <<'PY'
import re, sys, pathlib
api_key = sys.argv[1]
p = pathlib.Path("bridgeData.yaml")
text = p.read_text()
text = re.sub(r'^#?\s*api_key\s*:.*$', f'api_key: "{api_key}"', text, count=1, flags=re.M)
p.write_text(text)
PY
  echo "    → Edit $HORDE_DIR/bridgeData.yaml to set worker name and tune models."
else
  echo "[2/3] bridgeData.yaml exists, leaving it alone"
fi

# ── Run inside steam-run FHS so conda + CUDA wheels Just Work ─────────
echo "[3/3] Launching worker (Ctrl-C to stop)"

# Re-point TMPDIR to the FHS bubble's own tmpfs /tmp — nix-shell would
# otherwise leak its per-invocation /tmp/nix-shell-* path, which doesn't
# exist inside steam-run's sandbox and crashes micromamba on conda install.
RUN_CMD="export TMPDIR=/tmp TMP=/tmp TEMP=/tmp && cd '$HORDE_DIR' && "
if [[ $DO_UPDATE -eq 1 || ! -d "$HORDE_DIR/conda/envs/linux" ]]; then
  RUN_CMD+="bash update-runtime.sh && "
fi
# Backport transitive-dep pins that main's requirements.txt added after
# v9.0.7 was tagged, plus deps that hordelib/rembg pull in without
# declaring properly:
#   setuptools<81     — pkg_resources removed in 81.x (breaks worker __init__)
#   mediapipe<0.10.30 — newer mediapipe removed `mp.solutions` namespace
#   qrcode<8          — 8.x breaks hordelib's QR generation nodes
#   aiodns<4          — 4.x has an undetermined DNS-resolution regression
#   transformers<5    — 5.x requires torch>=2.4 (our pin is 2.3.1+cu121)
#   onnxruntime       — rembg (BG removal post-processor) imports it but
#                       lists it as an extras-only dep; without it, the
#                       inference subprocess dies silently on import.
RUN_CMD+="./conda/envs/linux/bin/pip install -q "
RUN_CMD+="'setuptools<81' 'mediapipe<0.10.30' 'qrcode<8' 'aiodns<4' "
RUN_CMD+="'transformers<5' 'onnxruntime' && "
RUN_CMD+="bash horde-bridge.sh"

# steam-run transitively references the unfree `steam-unwrapped` derivation,
# so we need NIXPKGS_ALLOW_UNFREE=1 for nix-shell's evaluation pass. The
# FHS env itself is free; this just silences the license check for one call.
exec env NIXPKGS_ALLOW_UNFREE=1 nix-shell -p steam-run --run "steam-run bash -c \"$RUN_CMD\""
