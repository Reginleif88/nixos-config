#!/usr/bin/env bash
# mail_panel.sh — Proton Mail status with unread count for Quickshell bar pill.
# Wraps tray_pill.sh and adds unread count parsing from window title.
# Proton Mail desktop (Electron) shows "(N) Proton Mail" when there are unread emails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
    --status)
        base=$("$SCRIPT_DIR/tray_pill.sh" --status --title "Proton Mail")
        title=$(echo "$base" | jq -r '.title // ""')

        # Parse "(N) Proton Mail" or "Proton Mail (N)" pattern
        unread=0
        if [[ "$title" =~ \(([0-9]+)\) ]]; then
            unread="${BASH_REMATCH[1]}"
        fi

        # Inject unread count into the base JSON
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
