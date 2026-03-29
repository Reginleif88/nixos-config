#!/usr/bin/env bash
# Claude Code status line — Gruvbox theme
# Receives JSON on stdin from Claude Code

input=$(cat)

# ── Parse fields ────────────────────────────────────────────────────────────
MODEL=$(echo "$input"    | jq -r '.model.display_name // "Claude"')
CWD=$(echo "$input"      | jq -r '.workspace.current_dir // ""')
PCT=$(echo "$input"      | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
OUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
API_MS=$(echo "$input"   | jq -r '.cost.total_api_duration_ms // 0')
USAGE_5H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
RESETS_5H=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
USAGE_7D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)
RESETS_7D=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# ── Colors (Gruvbox-inspired ANSI) ──────────────────────────────────────────
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# ── Directory (basename) ────────────────────────────────────────────────────
DIR="${CWD/#$HOME/\~}"
DIR_SHORT="${DIR##*/}"
[ -z "$DIR_SHORT" ] && DIR_SHORT="$DIR"

# ── Git info ────────────────────────────────────────────────────────────────
BRANCH=""
GIT_COUNTS=""
if git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    STAGED=$(git -C "$CWD" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git -C "$CWD" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    [ "$STAGED" -gt 0 ]   && GIT_COUNTS+="${GREEN}+${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ] && GIT_COUNTS+="${YELLOW}~${MODIFIED}${RESET}"
fi

# ── Context bar ─────────────────────────────────────────────────────────────
if   [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else                          BAR_COLOR="$GREEN"
fi

FILLED=$(( PCT / 10 ))
EMPTY=$(( 10 - FILLED ))
BAR=""
for (( i=0; i<FILLED; i++ )); do BAR+="█"; done
for (( i=0; i<EMPTY;  i++ )); do BAR+="░"; done

# ── Usage bar helper ────────────────────────────────────────────────────────
make_usage() {
    local pct=$1 resets=$2 label=$3
    [ -z "$pct" ] && return
    local color
    if   [ "$pct" -ge 90 ]; then color="$RED"
    elif [ "$pct" -ge 70 ]; then color="$YELLOW"
    else                          color="$GREEN"
    fi
    local filled=$(( pct / 10 )) empty=$(( 10 - pct / 10 ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    local result="${color}${bar}${RESET} ${pct}% ${label}"
    if [ -n "$resets" ]; then
        local now remaining
        now=$(date +%s)
        remaining=$(( resets - now ))
        if [ "$remaining" -gt 0 ]; then
            local h=$(( remaining / 3600 )) m=$(( (remaining % 3600) / 60 ))
            result+=" (${CYAN}${h}h${m}m${RESET})"
        fi
    fi
    echo "$result"
}

USAGE_5H_STR=$(make_usage "$USAGE_5H" "$RESETS_5H" "5h")
USAGE_7D_STR=$(make_usage "$USAGE_7D" "" "7d")

# ── Token speed ─────────────────────────────────────────────────────────────
SPEED_STR=""
if [ "$API_MS" -gt 0 ] && [ "$OUT_TOKENS" -gt 0 ]; then
    TPS=$(( OUT_TOKENS * 1000 / API_MS ))
    SPEED_STR="${CYAN}${TPS} t/s${RESET}"
fi

# ── Pomodoro timer ─────────────────────────────────────────────────────────
# State file: ~/.claude/pomodoro (contains epoch timestamp of session start)
# Usage: echo $(date +%s) > ~/.claude/pomodoro   — start
#        rm ~/.claude/pomodoro                    — stop
POMO_FILE="$HOME/.claude/pomodoro"
POMO_STR=""
WORK_MIN=25
BREAK_MIN=5
CYCLE_MIN=$(( WORK_MIN + BREAK_MIN ))
[ ! -f "$POMO_FILE" ] && date +%s > "$POMO_FILE"
if [ -f "$POMO_FILE" ]; then
    POMO_START=$(cat "$POMO_FILE" 2>/dev/null)
    if [ -n "$POMO_START" ]; then
        NOW=$(date +%s)
        ELAPSED_S=$(( NOW - POMO_START ))
        ELAPSED_M=$(( ELAPSED_S / 60 ))
        PHASE_M=$(( ELAPSED_M % CYCLE_MIN ))
        if [ "$PHASE_M" -lt "$WORK_MIN" ]; then
            REMAINING=$(( WORK_MIN - PHASE_M ))
            POMO_STR="${RED}${REMAINING}m${RESET}"
        else
            REMAINING=$(( CYCLE_MIN - PHASE_M ))
            POMO_STR="${GREEN}${REMAINING}m${RESET}"
        fi
    fi
fi

# ── Output ───────────────────────────────────────────────────────────────────
LINE1="${CYAN}[${MODEL}]${RESET} ${DIR_SHORT}"
if [ -n "$BRANCH" ]; then
    LINE1+="  ${GREEN}${BRANCH}${RESET}"
    [ -n "$GIT_COUNTS" ] && LINE1+=" ${GIT_COUNTS}"
fi
[ -n "$SPEED_STR" ] && LINE1+="  ${SPEED_STR}"
[ -n "$POMO_STR" ]  && LINE1+="  ${POMO_STR}"

LINE2="${BAR_COLOR}${BAR}${RESET} ${PCT}% ctx"
[ -n "$USAGE_5H_STR" ] && LINE2+=" | ${USAGE_5H_STR}"
[ -n "$USAGE_7D_STR" ] && LINE2+=" | ${USAGE_7D_STR}"

echo -e "$LINE1"
echo -e "$LINE2"
