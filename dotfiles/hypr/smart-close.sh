#!/usr/bin/env bash
# smart-close.sh — Close active window, but minimize tray-apps instead of killing them.
# Used by gruvbar close button instead of raw `hyprctl dispatch killactive`.

active=$(hyprctl activewindow -j)
class=$(echo "$active" | jq -r '.class // ""')
title=$(echo "$active" | jq -r '.title // ""')

# Apps that should minimize-to-tray instead of closing.
# Match on class first (reliable), fall back to title for generic classes like "electron".
should_tray=false

case "$class" in
    protonvpn-app|Proton\ VPN)  should_tray=true ;;
    spotify|Spotify)             should_tray=true ;;
    obsidian)                    should_tray=true ;;
esac

# Electron apps share the generic "electron" class — match by title
if [ "$should_tray" = false ]; then
    case "$title" in
        *Proton\ Mail*)  should_tray=true ;;
    esac
fi

if [ "$should_tray" = true ]; then
    hyprctl dispatch movetoworkspacesilent "special:minimized"
else
    hyprctl dispatch killactive
fi
