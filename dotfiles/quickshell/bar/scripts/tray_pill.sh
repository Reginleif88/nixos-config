#!/usr/bin/env bash
# tray_pill.sh — Generic status & toggle for tray-app pills in Quickshell bar.
#
# Usage:
#   tray_pill.sh --status  --class <class>  [--title <title>]
#   tray_pill.sh --toggle  --class <class>  [--title <title>]  --launch <cmd>
#
# Matches windows by class (exact, case-insensitive) or title (substring, case-insensitive).
# Returns JSON status; toggle shows/hides/launches the app.

set -euo pipefail

action="" match_class="" match_title="" launch_cmd=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --status|--toggle) action="$1"; shift ;;
        --class)  match_class="$2"; shift 2 ;;
        --title)  match_title="$2"; shift 2 ;;
        --launch) launch_cmd="$2"; shift 2 ;;
        *) shift ;;
    esac
done

find_window() {
    local filter=""
    if [ -n "$match_class" ] && [ -n "$match_title" ]; then
        filter="select((.class | test(\"$match_class\"; \"i\")) or (.title | test(\"$match_title\"; \"i\")))"
    elif [ -n "$match_class" ]; then
        filter="select(.class | test(\"$match_class\"; \"i\"))"
    elif [ -n "$match_title" ]; then
        filter="select(.title | test(\"$match_title\"; \"i\"))"
    else
        echo "" && return
    fi
    hyprctl clients -j | jq -c ".[] | $filter" | head -1
}

case "$action" in
    --status)
        client=$(find_window || true)
        if [ -z "$client" ]; then
            echo '{"running":false,"title":"","address":"","workspace":""}'
            exit 0
        fi

        title=$(echo "$client" | jq -r '.title')
        address=$(echo "$client" | jq -r '.address')
        workspace=$(echo "$client" | jq -r '.workspace.name')

        printf '{"running":true,"title":"%s","address":"%s","workspace":"%s"}\n' \
            "$title" "$address" "$workspace"
        ;;

    --toggle)
        client=$(find_window || true)
        if [ -z "$client" ]; then
            if [ -n "$launch_cmd" ]; then
                $launch_cmd &
                disown
            fi
            exit 0
        fi

        address=$(echo "$client" | jq -r '.address')
        workspace=$(echo "$client" | jq -r '.workspace.name')
        focused=$(hyprctl activewindow -j | jq -r '.address')

        if [ "$workspace" = "special:minimized" ]; then
            hyprctl dispatch movetoworkspace "e+0,address:$address"
            hyprctl dispatch focuswindow "address:$address"
        elif [ "$address" = "$focused" ]; then
            hyprctl dispatch movetoworkspacesilent "special:minimized,address:$address"
        else
            hyprctl dispatch focuswindow "address:$address"
        fi
        ;;

    *)
        echo "Usage: $0 {--status|--toggle} --class <class> [--title <title>] [--launch <cmd>]" >&2
        exit 1
        ;;
esac
