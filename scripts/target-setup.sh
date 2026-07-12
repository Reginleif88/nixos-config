#!/usr/bin/env bash
# Target machine setup — run ONCE after first NixOS install
# Handles items that can't be done before deployment:
#   1. Set up sops-nix age key and encrypt secrets (first-time only)
set -euo pipefail
umask 077

HOSTNAME="${1:-hyacinth}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOPS_KEY_DIR="$HOME/.config/sops/age"
SOPS_KEY_FILE="$SOPS_KEY_DIR/keys.txt"
SOPS_YAML="$REPO_DIR/secrets/.sops.yaml"
SECRETS_FILE="$REPO_DIR/secrets/secrets.yaml"

case "$HOSTNAME" in
  hyacinth|ignis) ;;
  *)
    echo "Unknown host '$HOSTNAME'. Expected one of: hyacinth, ignis" >&2
    exit 1
    ;;
esac

echo "=== NixOS Target Machine Setup ==="
echo ""

# ── Step 1: Ensure age key exists ─────────────────────────────────────
echo "[1/2] Checking age key..."

ENCRYPTED_KEY="$REPO_DIR/secrets/keys.txt.age"

if [ ! -f "$SOPS_KEY_FILE" ]; then
  if [ -L "$SOPS_KEY_FILE" ]; then
    echo "Refusing to use a symlink as the SOPS age key: $SOPS_KEY_FILE" >&2
    exit 1
  fi
  mkdir -p "$SOPS_KEY_DIR"
  chmod 700 "$SOPS_KEY_DIR"

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

if [ -L "$SOPS_KEY_FILE" ]; then
  echo "Refusing to use a symlink as the SOPS age key: $SOPS_KEY_FILE" >&2
  exit 1
fi
chmod 600 "$SOPS_KEY_FILE"
chmod 700 "$SOPS_KEY_DIR"
KEY_MODE=$(stat -c '%a' "$SOPS_KEY_FILE")
if [ "$KEY_MODE" != "600" ]; then
  echo "SOPS age key must be mode 600, found $KEY_MODE" >&2
  exit 1
fi

FRESH_SETUP="${FRESH_SETUP:-false}"
AGE_PUB_KEY=$(grep "public key:" "$SOPS_KEY_FILE" | awk '{print $NF}')

# ── Step 2: Set up secrets ────────────────────────────────────────────
echo "[2/2] Setting up secrets..."

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

  # Prompt for the secrets used by the current host. Blank values are accepted
  # because sops-nix only needs the keys to be present in the decrypted YAML;
  # fill in missing values later with: sops edit secrets/secrets.yaml
  echo ""
  echo "  Enter values for declared secrets (press Enter to leave blank)."
  echo ""

  read -rsp "  github_token (GitHub PAT, hidden): " GITHUB_TOKEN
  echo ""
  read -rp  "  github_repos (space-separated, e.g. 'Repo1 Repo2'): " GITHUB_REPOS
  read -rsp "  zlm_api_key (hidden): " ZLM_API_KEY
  echo ""
  read -rsp "  gtasks_client_id (hidden): " GTASKS_CLIENT_ID
  echo ""
  read -rsp "  gtasks_client_secret (hidden): " GTASKS_CLIENT_SECRET
  echo ""
  read -rsp "  keyring_password (hidden): " KEYRING_PASSWORD
  echo ""
  CLOUDFLARED_TUNNEL_TOKEN=""
  if [ "$HOSTNAME" = "ignis" ]; then
    read -rsp "  cloudflared_tunnel_token (hidden): " CLOUDFLARED_TUNNEL_TOKEN
    echo ""
  fi

  IGNIS_PASSWORD_HASH=""
  if [ "$HOSTNAME" = "ignis" ]; then
    read -rsp "  ignis_password_hash (SHA-512 hash for OVH console, hidden): " IGNIS_PASSWORD_HASH
    echo ""
  fi

  cat > "$SECRETS_FILE" << EOF
github_token: $GITHUB_TOKEN
github_repos: $GITHUB_REPOS
zlm_api_key: $ZLM_API_KEY
gtasks_client_id: $GTASKS_CLIENT_ID
gtasks_client_secret: $GTASKS_CLIENT_SECRET
keyring_password: $KEYRING_PASSWORD
cloudflared_tunnel_token: $CLOUDFLARED_TUNNEL_TOKEN
EOF

  if [ "$HOSTNAME" = "ignis" ]; then
    printf 'ignis_password_hash: %s\n' "$IGNIS_PASSWORD_HASH" >> "$SECRETS_FILE"
  fi

  sops --config "$SOPS_YAML" --encrypt --in-place "$SECRETS_FILE"
  echo "  ✓ Secrets encrypted at $SECRETS_FILE"
fi

# ── Done ─────────────────────────────────────────────────────────────
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Build system:    sudo nixos-rebuild switch --flake $REPO_DIR#$HOSTNAME"
if [ "$FRESH_SETUP" = true ]; then
  echo "  2. Commit secrets:  git add secrets/ && git commit -m 'Add encrypted secrets'"
  echo "  3. Save keys.txt:   Back up $SOPS_KEY_FILE somewhere safe"
fi
