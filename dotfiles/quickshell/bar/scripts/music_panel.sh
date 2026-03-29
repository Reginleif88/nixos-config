#!/usr/bin/env bash
# Music/MPRIS panel backend for Quickshell bar
# Returns current player state as JSON via playerctl
set -euo pipefail

build_status() {
    local status player title artist album position length

    # Check if any player is available
    if ! player=$(playerctl -l 2>/dev/null | head -1) || [[ -z "$player" ]]; then
        jq -n '{available:false,status:"Stopped",title:"",artist:"",album:"",position:0,length:0,player:""}'
        return
    fi

    status=$(playerctl status 2>/dev/null || echo "Stopped")
    title=$(playerctl metadata --format '{{title}}' 2>/dev/null || echo "")
    artist=$(playerctl metadata --format '{{artist}}' 2>/dev/null || echo "")
    album=$(playerctl metadata --format '{{album}}' 2>/dev/null || echo "")

    # Position and length in seconds (playerctl returns microseconds for length)
    position=$(playerctl position 2>/dev/null | awk '{printf "%d", $1}' || echo "0")
    length=$(playerctl metadata --format '{{mpris:length}}' 2>/dev/null | awk '{printf "%d", $1/1000000}' || echo "0")

    jq -n \
        --arg status "$status" \
        --arg title "$title" \
        --arg artist "$artist" \
        --arg album "$album" \
        --argjson position "${position:-0}" \
        --argjson length "${length:-0}" \
        --arg player "$player" \
        '{available:true,status:$status,title:$title,artist:$artist,album:$album,position:$position,length:$length,player:$player}'
}

case "${1:---status}" in
    --status)       build_status ;;
    --play-pause)   playerctl play-pause 2>/dev/null; sleep 0.1; build_status ;;
    --next)         playerctl next 2>/dev/null;       sleep 0.1; build_status ;;
    --previous)     playerctl previous 2>/dev/null;   sleep 0.1; build_status ;;
    *)              echo '{"error":"Unknown command"}' ;;
esac
