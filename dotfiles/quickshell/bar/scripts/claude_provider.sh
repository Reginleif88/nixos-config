#!/usr/bin/env bash
# claude_provider.sh — Toggle Claude Code between Anthropic and ZLM 5 (z.ai).
#
# Usage:
#   claude_provider.sh --status   # JSON status for Quickshell bar
#   claude_provider.sh --toggle   # Flip provider, return new status
#   claude_provider.sh --env      # Print export/unset statements for eval

set -euo pipefail

STATE_DIR="$HOME/.config/claude-provider"
STATE_FILE="$STATE_DIR/active"
KEY_FILE="/run/secrets/zlm_api_key"

mkdir -p "$STATE_DIR"

get_provider() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "anthropic"
    fi
}

status_json() {
    local p="$1"
    if [[ "$p" == "zlm" ]]; then
        echo '{"provider":"zlm","label":"ZLM"}'
    else
        echo '{"provider":"anthropic","label":"API"}'
    fi
}

case "${1:---status}" in
    --status)
        status_json "$(get_provider)"
        ;;

    --toggle)
        p=$(get_provider)
        if [[ "$p" == "zlm" ]]; then
            echo "anthropic" > "$STATE_FILE"
            status_json "anthropic"
        else
            echo "zlm" > "$STATE_FILE"
            status_json "zlm"
        fi
        ;;

    --env)
        p=$(get_provider)
        if [[ "$p" == "zlm" ]] && [[ -f "$KEY_FILE" ]]; then
            echo "export ANTHROPIC_AUTH_TOKEN=\"$(cat "$KEY_FILE")\""
            echo 'export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"'
            echo 'export API_TIMEOUT_MS="3000000"'
            echo 'export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-5.1"'
            echo 'export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-5-turbo"'
            echo 'export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.7"'
        else
            echo 'unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL API_TIMEOUT_MS ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL 2>/dev/null || true'
        fi
        ;;

    *)
        echo "Usage: $0 {--status|--toggle|--env}" >&2
        exit 1
        ;;
esac
