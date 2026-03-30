#!/usr/bin/env bash
# mail_panel.sh — Proton Mail status with unread count for Quickshell bar pill.
# Wraps tray_pill.sh for window status, and mail_unread.py for the actual
# unread count via Chrome DevTools Protocol into the Electron renderer.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
    --status)
        base=$("$SCRIPT_DIR/tray_pill.sh" --status --title "Proton Mail")
        running=$(echo "$base" | jq -r '.running')

        unread=0
        if [ "$running" = "true" ]; then
            unread=$(python3 "$SCRIPT_DIR/mail_unread.py" 2>/dev/null || echo 0)
        fi

        echo "$base" | jq --argjson u "$unread" '. + {unread: $u}'
        ;;

    --toggle)
        exec "$SCRIPT_DIR/tray_pill.sh" --toggle --title "Proton Mail" --launch proton-mail
        ;;

    *)
        echo "Usage: $0 {--status|--toggle}" >&2
        exit 1
        ;;
esac
