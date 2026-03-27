#!/usr/bin/env bash
# ProtonVPN panel backend for Quickshell bar
# Uses nmcli to detect VPN connections and produce JSON for the QML popup
set -euo pipefail

CACHE_DIR="/tmp/quickshell_vpn_cache"
mkdir -p "$CACHE_DIR"

# ── Country code → flag emoji ──────────────────────────────────────
country_flag() {
    local cc="${1:-}"
    [[ ${#cc} -ne 2 ]] && return
    cc="${cc^^}"
    local a=$((0x1F1E6 + $(printf '%d' "'${cc:0:1}") - 65))
    local b=$((0x1F1E6 + $(printf '%d' "'${cc:1:1}") - 65))
    printf "\\U$(printf '%X' $a)\\U$(printf '%X' $b)"
}

# ── Parse ProtonVPN server name (e.g. "CH-ZH#1" → country=CH, city=ZH) ──
parse_server_name() {
    local name="$1"
    local country="" city="" number=""

    if [[ "$name" =~ ^([A-Z]{2})-([A-Z]+)#([0-9]+)$ ]]; then
        country="${BASH_REMATCH[1]}"
        city="${BASH_REMATCH[2]}"
        number="${BASH_REMATCH[3]}"
    elif [[ "$name" =~ ^([A-Z]{2})#([0-9]+)$ ]]; then
        country="${BASH_REMATCH[1]}"
        number="${BASH_REMATCH[2]}"
    elif [[ "$name" =~ ^([A-Z]{2}) ]]; then
        country="${BASH_REMATCH[1]}"
    fi

    jq -n --arg country "$country" --arg city "$city" --arg number "$number" \
        '{"country":$country,"city":$city,"number":$number}'
}

# ── Find active VPN connection ─────────────────────────────────────
get_active_vpn() {
    # Look for active wireguard or vpn (openvpn) connections
    # Filter out ProtonVPN's leak protection connections
    nmcli -t -f NAME,TYPE,DEVICE con show --active 2>/dev/null \
        | grep -E ':(wireguard|vpn):' \
        | grep -iv 'ipv6leak\|killswitch' \
        | head -1
}

# ── Get connected VPN info ─────────────────────────────────────────
get_connected() {
    local active
    active=$(get_active_vpn)

    if [[ -z "$active" ]]; then
        echo "null"
        return
    fi

    local name type device
    name=$(echo "$active" | cut -d: -f1)
    type=$(echo "$active" | cut -d: -f2)
    device=$(echo "$active" | cut -d: -f3)

    # Determine protocol
    local protocol="OpenVPN"
    [[ "$type" == "wireguard" ]] && protocol="WireGuard"

    # Get VPN IP (cached 15s)
    local ip_cache="$CACHE_DIR/vpn_ip"
    local ip=""
    if [[ -f "$ip_cache" ]] && [[ $(( $(date +%s) - $(stat -c %Y "$ip_cache" 2>/dev/null || echo 0) )) -lt 15 ]]; then
        ip=$(cat "$ip_cache")
    else
        if [[ -n "$device" ]]; then
            ip=$(nmcli -t -f IP4.ADDRESS dev show "$device" 2>/dev/null \
                | grep "IP4.ADDRESS" | head -1 | cut -d: -f2 | cut -d/ -f1)
        fi
        ip="${ip:-}"
        [[ -n "$ip" ]] && echo "$ip" > "$ip_cache"
    fi

    # Parse server info from connection name
    local server_info
    server_info=$(parse_server_name "$name")

    local country city
    country=$(echo "$server_info" | jq -r '.country')
    city=$(echo "$server_info" | jq -r '.city')

    local flag=""
    [[ -n "$country" ]] && flag=$(country_flag "$country")

    jq -n \
        --arg name "$name" \
        --arg country "$country" \
        --arg city "$city" \
        --arg flag "$flag" \
        --arg ip "$ip" \
        --arg protocol "$protocol" \
        '{"name":$name,"country":$country,"city":$city,"flag":$flag,"ip":$ip,"protocol":$protocol}'
}

# ── List saved VPN profiles ───────────────────────────────────────
get_profiles() {
    local profiles="[]"

    while IFS=: read -r name type _; do
        [[ -z "$name" ]] && continue
        # Skip leak protection / killswitch connections
        echo "$name" | grep -qiE 'ipv6leak|killswitch' && continue

        local protocol="OpenVPN"
        [[ "$type" == "wireguard" ]] && protocol="WireGuard"

        profiles=$(echo "$profiles" | jq \
            --arg name "$name" \
            --arg protocol "$protocol" \
            '. + [{"name":$name,"protocol":$protocol}]')
    done < <(nmcli -t -f NAME,TYPE con show 2>/dev/null \
        | grep -E ':(wireguard|vpn)$')

    echo "$profiles"
}

# ── Build full status JSON ────────────────────────────────────────
build_status() {
    local connected
    connected=$(get_connected)

    local profiles
    profiles=$(get_profiles)

    jq -n \
        --argjson connected "$connected" \
        --argjson profiles "$profiles" \
        '{"connected":$connected,"profiles":$profiles}'
}

# ── Quick connect ─────────────────────────────────────────────────
quick_connect() {
    # Bring up the most recent VPN profile via nmcli
    local profile
    profile=$(nmcli -t -f NAME,TYPE con show 2>/dev/null \
        | grep -E ':(wireguard|vpn)$' \
        | grep -iv 'ipv6leak\|killswitch' \
        | head -1 | cut -d: -f1)

    if [[ -n "$profile" ]]; then
        nmcli con up "$profile" 2>/dev/null || true
        sleep 2
    fi

    # Invalidate IP cache
    rm -f "$CACHE_DIR/vpn_ip" 2>/dev/null || true
    build_status
}

# ── Connect to specific profile ───────────────────────────────────
connect_profile() {
    local name="$1"
    nmcli con up "$name" 2>/dev/null || true
    sleep 2
    rm -f "$CACHE_DIR/vpn_ip" 2>/dev/null || true
    build_status
}

# ── Disconnect ────────────────────────────────────────────────────
disconnect_vpn() {
    local active
    active=$(get_active_vpn)

    if [[ -n "$active" ]]; then
        local name
        name=$(echo "$active" | cut -d: -f1)
        nmcli con down "$name" 2>/dev/null || true
        sleep 1
    fi

    rm -f "$CACHE_DIR/vpn_ip" 2>/dev/null || true
    build_status
}

# ── Main dispatch ─────────────────────────────────────────────────
case "${1:---status}" in
    --status)       build_status ;;
    --connect)      connect_profile "${2:?Profile name required}" ;;
    --quick)        quick_connect ;;
    --disconnect)   disconnect_vpn ;;
    *)              echo '{"error":"Unknown command"}' ;;
esac
