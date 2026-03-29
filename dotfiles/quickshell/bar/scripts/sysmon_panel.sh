#!/usr/bin/env bash
# System monitor panel backend for Quickshell bar
# Returns top processes by CPU and RAM usage as JSON
set -euo pipefail

# Number of top processes to return
TOP_N="${2:-8}"

## Helper: parse ps output (pid, cpu%, rss, full cmdline) into JSON array
## Uses the basename of the first arg instead of comm to avoid kernel truncation
## (e.g. Chromium "isolated" subprocesses now show as "chrome" / "firefox")
parse_procs() {
    awk '{
        pid=$1; cpu=$2; ram=$3/1024
        # $4.. is the full command line — extract basename of first token
        cmd=$4
        n=split(cmd, parts, "/")
        name=parts[n]
        # strip common wrappers like .wrapped, -wrapped
        gsub(/[.-]wrapped$/, "", name)
        if (name == "") name="?"
        printf "{\"pid\":%s,\"cpu\":%.1f,\"ram\":%.1f,\"name\":\"%s\"}\n", pid, cpu, ram, name
    }' | jq -s '.'
}

build_status() {
    # Top CPU consumers
    local cpu_procs
    cpu_procs=$(ps axo pid,pcpu,rss,args --no-headers --sort=-pcpu 2>/dev/null \
        | head -n "$TOP_N" \
        | parse_procs)

    # Top RAM consumers
    local ram_procs
    ram_procs=$(ps axo pid,pcpu,rss,args --no-headers --sort=-rss 2>/dev/null \
        | head -n "$TOP_N" \
        | parse_procs)

    jq -n \
        --argjson cpu "$cpu_procs" \
        --argjson ram "$ram_procs" \
        '{"cpu":$cpu,"ram":$ram}'
}

case "${1:---status}" in
    --status)   build_status ;;
    *)          echo '{"error":"Unknown command"}' ;;
esac
