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
    if [ -z "$match_class" ] && [ -z "$match_title" ]; then
        echo "" && return
    fi

    hyprctl clients -j | jq -c \
        --arg class "$match_class" \
        --arg title "$match_title" '
        .[]
        | select(
            (($class != "") and (((.class // "") | ascii_downcase) == ($class | ascii_downcase)))
            or
            (($title != "") and (((.title // "") | ascii_downcase) | contains($title | ascii_downcase)))
        )
    ' | head -1
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

        jq -nc \
            --arg title "$title" \
            --arg address "$address" \
            --arg workspace "$workspace" \
            '{running:true,title:$title,address:$address,workspace:$workspace}'
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
            hyprctl dispatch "hl.dsp.window.move({ workspace = \"e+0\", window = \"address:$address\" })"
            hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })"
        elif [ "$address" = "$focused" ]; then
            hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:minimized\", window = \"address:$address\", silent = true })"
        else
            hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })"
        fi
        ;;

    *)
        echo "Usage: $0 {--status|--toggle} --class <class> [--title <title>] [--launch <cmd>]" >&2
        exit 1
        ;;
esac
