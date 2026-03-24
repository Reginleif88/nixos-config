#!/usr/bin/env bash
# Target machine setup — run ONCE after first NixOS install
# Handles items that can't be done before deployment:
#   1. Generate hardware-configuration.nix for actual hardware
#   2. Set up sops-nix age key and encrypt secrets (first-time only)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HARDWARE_CONF="$REPO_DIR/hosts/desktop/hardware-configuration.nix"
SOPS_KEY_DIR="$HOME/.config/sops/age"
SOPS_KEY_FILE="$SOPS_KEY_DIR/keys.txt"
SOPS_YAML="$REPO_DIR/secrets/.sops.yaml"
SECRETS_FILE="$REPO_DIR/secrets/secrets.yaml"

echo "=== NixOS Target Machine Setup ==="
echo ""

# ── Step 1: Generate hardware-configuration.nix ──────────────────────
echo "[1/3] Generating hardware-configuration.nix..."

if grep -q "Placeholder" "$HARDWARE_CONF" 2>/dev/null; then
  sudo nixos-generate-config --show-hardware-config > "$HARDWARE_CONF"
  echo "  ✓ Hardware config written to $HARDWARE_CONF"
else
  echo "  → Already generated (not a placeholder), skipping"
fi

# ── Step 2: Ensure age key exists ─────────────────────────────────────
echo "[2/3] Checking age key..."

ENCRYPTED_KEY="$REPO_DIR/secrets/keys.txt.age"

if [ ! -f "$SOPS_KEY_FILE" ]; then
  mkdir -p "$SOPS_KEY_DIR"

  if [ -f "$ENCRYPTED_KEY" ]; then
    # Decrypt the age key from the repo (passphrase-protected)
    echo "  → Decrypting age key from repo..."
    age -d -o "$SOPS_KEY_FILE" "$ENCRYPTED_KEY"
    echo "  ✓ Age key decrypted to $SOPS_KEY_FILE"
  else
    # First-ever setup — generate a new key
    age-keygen -o "$SOPS_KEY_FILE"
    echo "  ✓ Age key generated at $SOPS_KEY_FILE"
    echo ""
    echo "  Next: encrypt it into the repo with:"
    echo "    age -p -o $ENCRYPTED_KEY $SOPS_KEY_FILE"
    FRESH_SETUP=true
  fi
else
  echo "  → Age key already exists at $SOPS_KEY_FILE"
fi

FRESH_SETUP="${FRESH_SETUP:-false}"
AGE_PUB_KEY=$(grep "public key:" "$SOPS_KEY_FILE" | awk '{print $NF}')

# ── Step 3: Set up secrets ────────────────────────────────────────────
echo "[3/3] Setting up secrets..."

# Check if secrets.yaml is already encrypted (not a placeholder)
if sops --config "$SOPS_YAML" -d "$SECRETS_FILE" > /dev/null 2>&1; then
  echo "  → Encrypted secrets found and decryptable. Nothing to do."
else
  echo "  → No valid encrypted secrets found. Running first-time setup..."

  # Update .sops.yaml with the real public key
  cat > "$SOPS_YAML" << EOF
keys:
  - &primary $AGE_PUB_KEY
creation_rules:
  - path_regex: secrets\.yaml\$
    key_groups:
      - age:
          - *primary
EOF
  echo "  ✓ Updated $SOPS_YAML with your public key"

  # Prompt for secrets
  echo ""
  echo "  You'll need your GitHub Personal Access Token (PAT)"
  echo "  and the names of your private repos to clone."
  echo ""
  read -rsp "  Enter your GitHub PAT (input hidden): " GITHUB_TOKEN
  echo ""
  read -rp "  Enter GitHub repos (space-separated, e.g. 'Repo1 Repo2'): " GITHUB_REPOS

  # Write plaintext, then encrypt in place with sops
  cat > "$SECRETS_FILE" << EOF
github_token: $GITHUB_TOKEN
github_repos: $GITHUB_REPOS
EOF

  sops --config "$SOPS_YAML" --encrypt --in-place "$SECRETS_FILE"
  echo "  ✓ Secrets encrypted at $SECRETS_FILE"
fi

# ── Done ─────────────────────────────────────────────────────────────
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Build system:    sudo nixos-rebuild switch --flake $REPO_DIR#desktop"
if [ "$FRESH_SETUP" = true ]; then
  echo "  2. Commit secrets:  git add secrets/ && git commit -m 'Add encrypted secrets'"
  echo "  3. Save keys.txt:   Back up $SOPS_KEY_FILE somewhere safe"
fi
