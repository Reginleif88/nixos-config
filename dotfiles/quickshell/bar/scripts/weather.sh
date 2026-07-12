#!/usr/bin/env bash
# Weather data provider for Quickshell bar.
# Open-Meteo is queried for fixed coordinates so the bar does not leak the
# workstation's IP address to a second geolocation service.
set -euo pipefail
umask 077

CACHE_DIR="${HOME}/.cache/quickshell/weather"
FORECAST_CACHE="${CACHE_DIR}/forecast.json"
CACHE_MAX_AGE=1800

# Massy, France. Change these deliberately if the workstation moves.
LATITUDE="48.7306"
LONGITUDE="2.2719"

mkdir -p "$CACHE_DIR"

fetch_forecast() {
    local url raw cache_tmp
    url="https://api.open-meteo.com/v1/forecast?latitude=${LATITUDE}&longitude=${LONGITUDE}"
    url+="&current=temperature_2m,apparent_temperature,is_day,weather_code"
    url+="&daily=weather_code,temperature_2m_max,temperature_2m_min,wind_speed_10m_max,relative_humidity_2m_mean,precipitation_probability_max"
    url+="&hourly=temperature_2m,weather_code,precipitation_probability"
    url+="&timezone=auto&forecast_days=5"

    raw=$(curl -fsS --max-time 15 "$url") || {
        echo "Open-Meteo request failed" >&2
        return 1
    }

    cache_tmp="${FORECAST_CACHE}.tmp.$$"
    jq -c '
        def icon($code; $is_day):
            if $code == 0 then (if $is_day == 1 then "\uE302" else "\uE32B" end)
            elif $code == 1 or $code == 2 then (if $is_day == 1 then "\uE303" else "\uE379" end)
            elif $code == 3 then "\uE312"
            elif $code == 45 or $code == 48 then "\uE311"
            elif ($code >= 51 and $code <= 67) or ($code >= 80 and $code <= 82) then "\uE318"
            elif ($code >= 71 and $code <= 77) or ($code == 85) or ($code == 86) then "\uE31A"
            elif $code >= 95 then "\uE334"
            else "\uE302" end;
        def hex($code; $is_day):
            if $code == 0 then (if $is_day == 1 then "#fabd2f" else "#d3869b" end)
            elif $code == 1 or $code == 2 then "#83a598"
            elif $code == 3 or $code == 45 or $code == 48 then "#a89984"
            elif ($code >= 51 and $code <= 67) or ($code >= 80 and $code <= 82) then "#83a598"
            elif ($code >= 71 and $code <= 77) or ($code == 85) or ($code == 86) then "#ebdbb2"
            elif $code >= 95 then "#fb4934"
            else "#8ec07c" end;
        def description($code):
            if $code == 0 then "Clear sky"
            elif $code == 1 then "Mainly clear"
            elif $code == 2 then "Partly cloudy"
            elif $code == 3 then "Overcast"
            elif $code == 45 or $code == 48 then "Fog"
            elif $code == 51 then "Light drizzle"
            elif $code == 53 then "Drizzle"
            elif $code == 55 then "Dense drizzle"
            elif $code == 56 or $code == 57 then "Freezing drizzle"
            elif $code == 61 then "Light rain"
            elif $code == 63 then "Rain"
            elif $code == 65 then "Heavy rain"
            elif $code == 66 or $code == 67 then "Freezing rain"
            elif $code == 71 then "Light snow"
            elif $code == 73 then "Snow"
            elif $code == 75 then "Heavy snow"
            elif $code == 77 then "Snow grains"
            elif $code == 80 then "Light showers"
            elif $code == 81 then "Showers"
            elif $code == 82 then "Heavy showers"
            elif $code == 85 or $code == 86 then "Snow showers"
            elif $code == 95 then "Thunderstorm"
            elif $code == 96 or $code == 99 then "Thunderstorm with hail"
            else "Unknown" end;
        {
            current: {
                icon: icon(.current.weather_code; .current.is_day),
                temp: (.current.temperature_2m // 0),
                feels_like: (.current.apparent_temperature // 0),
                hex: hex(.current.weather_code; .current.is_day),
                desc: description(.current.weather_code),
                is_day: (.current.is_day // 1)
            },
            forecast: [
                range(0; (.daily.time | length)) as $day
                | {
                    day: (.daily.time[$day] | strptime("%Y-%m-%d") | mktime | strftime("%a")),
                    date: .daily.time[$day],
                    icon: icon(.daily.weather_code[$day]; 1),
                    hex: hex(.daily.weather_code[$day]; 1),
                    max: (.daily.temperature_2m_max[$day] // 0),
                    min: (.daily.temperature_2m_min[$day] // 0),
                    wind: (.daily.wind_speed_10m_max[$day] // 0),
                    humidity: (.daily.relative_humidity_2m_mean[$day] // 0),
                    pop: (.daily.precipitation_probability_max[$day] // 0),
                    hourly: [
                        range(($day * 24); (($day + 1) * 24); 3) as $hour
                        | select($hour < (.hourly.time | length))
                        | {
                            time: (.hourly.time[$hour] | split("T")[1] | .[0:5]),
                            icon: icon(.hourly.weather_code[$hour]; 1),
                            hex: hex(.hourly.weather_code[$hour]; 1),
                            temp: (.hourly.temperature_2m[$hour] // 0),
                            pop: (.hourly.precipitation_probability[$hour] // 0)
                        }
                    ]
                }
            ],
            ready: true
        }
    ' <<<"$raw" > "$cache_tmp"
    mv -f "$cache_tmp" "$FORECAST_CACHE"
}

is_cache_fresh() {
    [[ -f "$FORECAST_CACHE" ]] || return 1
    local age=$(( $(date +%s) - $(stat -c %Y "$FORECAST_CACHE") ))
    [[ $age -lt $CACHE_MAX_AGE ]]
}

ensure_data() {
    is_cache_fresh || fetch_forecast
}

case "${1:---bar}" in
    --bar)
        refresh_ok=1
        ensure_data || refresh_ok=0
        if [[ -f "$FORECAST_CACHE" ]]; then
            if [[ $refresh_ok -eq 1 ]]; then
                jq -c '.current + {ready: .ready}' "$FORECAST_CACHE"
            else
                jq -c '.current + {ready: true, stale: true, error: "refresh failed"}' "$FORECAST_CACHE"
            fi
        else
            echo '{"ready":false,"error":"refresh failed"}'
        fi
        ;;
    --json)
        refresh_ok=1
        ensure_data || refresh_ok=0
        if [[ -f "$FORECAST_CACHE" ]]; then
            if [[ $refresh_ok -eq 1 ]]; then
                cat "$FORECAST_CACHE"
            else
                jq -c '. + {ready: true, stale: true, error: "refresh failed"}' "$FORECAST_CACHE"
            fi
        else
            echo '{"ready":false,"forecast":[],"error":"refresh failed"}'
        fi
        ;;
    --update)
        fetch_forecast
        echo "Cache updated: $FORECAST_CACHE"
        ;;
    *)
        echo "Usage: $0 [--bar|--json|--update]" >&2
        exit 1
        ;;
esac
