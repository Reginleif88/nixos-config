#!/usr/bin/env bash
# System monitor panel backend for Quickshell bar
# Returns top processes by CPU and RAM usage as JSON
set -euo pipefail

# Number of top processes to return
TOP_N="${2:-8}"

build_status() {
    # Top CPU consumers (exclude idle/kernel, group by command name)
    local cpu_procs
    cpu_procs=$(ps axo pid,pcpu,rss,comm --no-headers --sort=-pcpu 2>/dev/null \
        | head -n "$TOP_N" \
        | awk '{printf "{\"pid\":%s,\"cpu\":%.1f,\"ram\":%.1f,\"name\":\"%s\"}\n", $1, $2, $3/1024, $4}' \
        | jq -s '.')

    # Top RAM consumers
    local ram_procs
    ram_procs=$(ps axo pid,pcpu,rss,comm --no-headers --sort=-rss 2>/dev/null \
        | head -n "$TOP_N" \
        | awk '{printf "{\"pid\":%s,\"cpu\":%.1f,\"ram\":%.1f,\"name\":\"%s\"}\n", $1, $2, $3/1024, $4}' \
        | jq -s '.')

    jq -n \
        --argjson cpu "$cpu_procs" \
        --argjson ram "$ram_procs" \
        '{"cpu":$cpu,"ram":$ram}'
}

case "${1:---status}" in
    --status)   build_status ;;
    *)          echo '{"error":"Unknown command"}' ;;
esac
