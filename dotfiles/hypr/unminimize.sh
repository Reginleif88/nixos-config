#!/usr/bin/env bash
set -euo pipefail

# Map app class names to Nerd Font icons
icon_for() {
    local class="${1,,}" # lowercase
    case "$class" in
        firefox*)                echo "󰈹";;
        google-chrome*|chromium*)echo "";;
        code|code-oss|vscodium)  echo "󰨞";;
        kitty)                   echo "";;
        thunar)                  echo "󰝰";;
        spotify*)                echo "";;
        steam*)                  echo "󰓓";;
        vlc*)                    echo "󰕼";;
        okular)                  echo "";;
        swayimg)                 echo "󰋩";;
        pavucontrol*)            echo "󰕾";;
        nm-*|network*)           echo "󰤥";;
        obsidian*)               echo "󱓧";;
        *)                       echo "";;
    esac
}

# Get minimized windows from special:minimized workspace
minimized=$(hyprctl clients -j | jq -c '.[] | select(.workspace.name == "special:minimized")')

# Build display lines: "address|icon  class: title"
display=""

while IFS= read -r win; do
    [[ -z "$win" ]] && continue
    class=$(echo "$win" | jq -r '.class')
    title=$(echo "$win" | jq -r '.title')
    addr=$(echo "$win" | jq -r '.address')

    # Electron apps share a generic class — resolve display name from title
    display_class="$class"
    if [[ "$class" == "electron" ]]; then
        case "$title" in
            *Obsidian*)     display_class="obsidian" ;;
            *Proton\ Mail*) display_class="proton-mail" ;;
        esac
    fi

    icon=$(icon_for "$display_class")

    if [[ -n "$display" ]]; then
        display+=$'\n'
    fi
    display+="$addr|$icon  $display_class: $title"
done <<< "$minimized"

# Show picker — fuzzel returns the selected line text
selected=$(echo "$display" | fuzzel -d -p "Restore: ") || true

if [[ -z "$selected" ]]; then
    exit 0
fi

# Extract address from the selected line
addr="${selected%%|*}"

# Get current workspace and move the window there
ws=$(hyprctl activeworkspace -j | jq -r '.id')
hyprctl dispatch "hl.dsp.window.move({ workspace = $ws, window = \"address:$addr\" })"
