#!/bin/bash
set -f

# ── Client timezone (authoritative) ────────────────────
# Resolve the client's local timezone from /etc/localtime and export it
# explicitly so all `date` display calls use the client's timezone,
# regardless of any TZ value inherited from the environment (e.g. the AI).
_client_tz=""
if [ -L /etc/localtime ]; then
    _tz_path=$(readlink /etc/localtime 2>/dev/null)
    _client_tz="${_tz_path#*/zoneinfo/}"
fi
if [ -z "$_client_tz" ] && [ -f /etc/timezone ]; then
    _client_tz=$(cat /etc/timezone 2>/dev/null)
fi
[ -n "$_client_tz" ] && export TZ="$_client_tz"

input=$(cat)

if [ -z "$input" ]; then
    printf "\033[38;2;139;92;246m◆\033[0m grwthlab"
    exit 0
fi

# ── Hex → ANSI converter ───────────────────────────────
hex_to_ansi() {
    local hex="${1#\#}"
    printf '\033[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# ── grwthlab Default Colors ────────────────────────────
purple='\033[38;2;139;92;246m'
green='\033[38;2;34;197;94m'
orange='\033[38;2;245;158;11m'
yellow='\033[38;2;234;179;8m'
red='\033[38;2;224;82;82m'
muted='\033[38;2;156;163;175m'
white='\033[38;2;220;220;220m'
cyan='\033[38;2;86;182;194m'
dim='\033[2m'
reset='\033[0m'

# ── Load custom colors from config ─────────────────────
config_file="$HOME/.claude/statusline.config.json"
if [ -f "$config_file" ]; then
    _cfg=$(jq -r '.colors // {} | to_entries[] | "\(.key) \(.value)"' "$config_file" 2>/dev/null)
    while IFS=' ' read -r key val; do
        [ -z "$key" ] || [ -z "$val" ] && continue
        ansi=$(hex_to_ansi "$val")
        case "$key" in
            accent)  purple="$ansi" ;;
            success) green="$ansi" ;;
            warning) orange="$ansi" ;;
            caution) yellow="$ansi" ;;
            error)   red="$ansi" ;;
            muted)   muted="$ansi" ;;
            text)    white="$ansi" ;;
            info)    cyan="$ansi" ;;
        esac
    done <<< "$_cfg"
fi

sep=" ${muted}│${reset} "

# ── Helpers ─────────────────────────────────────────────
color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

format_epoch_time() {
    local epoch=$1
    local style=$2
    [ -z "$epoch" ] || [ "$epoch" = "null" ] || [ "$epoch" = "0" ] && return

    local result=""
    case "$style" in
        time)
            result=$(date -j -r "$epoch" +"%l:%M%p" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%l:%M%P" 2>/dev/null)
            result=$(echo "$result" | sed 's/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            ;;
        datetime)
            result=$(date -j -r "$epoch" +"%b %-d, %l:%M%p" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d, %l:%M%P" 2>/dev/null)
            result=$(echo "$result" | sed 's/  / /g; s/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            ;;
        *)
            result=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d" 2>/dev/null)
            result=$(echo "$result" | tr '[:upper:]' '[:lower:]')
            ;;
    esac
    printf "%s" "$result"
}

iso_to_epoch() {
    local iso_str="$1"

    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(env TZ=UTC date -d "${stripped/T/ }" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(date -d "${stripped/T/ }" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# ── Extract JSON data ────────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')

cwd_raw=$(echo "$input" | jq -r '.cwd // ""')
[ -z "$cwd_raw" ] || [ "$cwd_raw" = "null" ] && cwd_raw=$(pwd)

ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$ctx_size" -eq 0 ] 2>/dev/null && ctx_size=200000

input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

session_start=$(echo "$input" | jq -r '.session.start_time // empty')

stdin_five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
stdin_five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
stdin_seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
stdin_seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

current=$(( input_tokens + cache_create + cache_read ))
if [ "$ctx_size" -gt 0 ]; then
    pct_used=$(( current * 100 / ctx_size ))
else
    pct_used=0
fi

# ── Effort level ────────────────────────────────────────
effort="default"
settings_path="$HOME/.claude/settings.json"
if [ -f "$settings_path" ]; then
    effort=$(jq -r '.effortLevel // "default"' "$settings_path" 2>/dev/null)
fi

# ── Project detection ───────────────────────────────────
project_label=""
dirname_raw=$(basename "$cwd_raw")

# Strategy 1: package.json name field
if [ -f "$cwd_raw/package.json" ]; then
    pkg_name=$(jq -r '.name // ""' "$cwd_raw/package.json" 2>/dev/null)
    if [[ "$pkg_name" == @grwthlab/* ]]; then
        project_label="${pkg_name#@grwthlab/}"
    elif [[ "$pkg_name" == grwth* ]]; then
        project_label="$pkg_name"
    fi
fi

# Strategy 2: directory name pattern (grwth.rbac → grwth/rbac)
if [ -z "$project_label" ]; then
    if [[ "$dirname_raw" == grwth.* ]]; then
        project_label="grwth/${dirname_raw#grwth.}"
    elif [[ "$dirname_raw" == grwthlab* ]]; then
        project_label="$dirname_raw"
    fi
fi

# Strategy 3: fallback to plain dirname
if [ -z "$project_label" ]; then
    project_label="$dirname_raw"
fi

# ── Git info ────────────────────────────────────────────
git_branch=""
git_dirty=""
git_changes=0
git_ahead=0
git_behind=0
git_last_commit=""

if git -C "$cwd_raw" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd_raw" symbolic-ref --short HEAD 2>/dev/null)

    # Uncommitted changes count
    porcelain=$(git -C "$cwd_raw" --no-optional-locks status --porcelain 2>/dev/null)
    if [ -n "$porcelain" ]; then
        git_dirty="*"
        git_changes=$(echo "$porcelain" | wc -l | tr -d ' ')
    fi

    # Ahead/behind remote
    ab=$(git -C "$cwd_raw" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    if [ -n "$ab" ]; then
        git_ahead=$(echo "$ab" | awk '{print $1}')
        git_behind=$(echo "$ab" | awk '{print $2}')
    fi

    # Last commit message (truncated)
    git_last_commit=$(git -C "$cwd_raw" log -1 --format='%s' 2>/dev/null | head -c 40)
fi

# ── Session duration ────────────────────────────────────
session_duration=""
if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
    start_epoch=$(iso_to_epoch "$session_start")
    if [ -n "$start_epoch" ]; then
        now_epoch=$(date +%s)
        elapsed=$(( now_epoch - start_epoch ))
        if [ "$elapsed" -ge 3600 ]; then
            session_duration="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
        elif [ "$elapsed" -ge 60 ]; then
            session_duration="$(( elapsed / 60 ))m"
        else
            session_duration="${elapsed}s"
        fi
    fi
fi

# ── Skip permissions indicator ──────────────────────────
skip_perms=""
parent_cmd=$(ps -o args= -p "$PPID" 2>/dev/null)
if [[ "$parent_cmd" == *"--dangerously-skip-permissions"* ]]; then
    skip_perms="⚡  "
fi

# ── System status ───────────────────────────────────────
# Node version (cached 300s)
node_cache="/tmp/claude/node-version-cache"
mkdir -p /tmp/claude
node_ver=""

if [ -f "$node_cache" ]; then
    cache_mtime=$(stat -c %Y "$node_cache" 2>/dev/null || stat -f %m "$node_cache" 2>/dev/null)
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    if [ "$cache_age" -lt 300 ]; then
        node_ver=$(cat "$node_cache" 2>/dev/null)
    fi
fi
if [ -z "$node_ver" ]; then
    node_ver=$(node -v 2>/dev/null | sed 's/^v//')
    if [ -n "$node_ver" ]; then
        # Trim to major.minor
        node_ver=$(echo "$node_ver" | cut -d. -f1,2)
        echo "$node_ver" > "$node_cache"
    fi
fi

# Package manager detection (from lockfiles)
pkg_manager=""
if [ -f "$cwd_raw/bun.lockb" ] || [ -f "$cwd_raw/bun.lock" ]; then
    pkg_manager="bun"
elif [ -f "$cwd_raw/pnpm-lock.yaml" ]; then
    pkg_manager="pnpm"
elif [ -f "$cwd_raw/yarn.lock" ]; then
    pkg_manager="yarn"
elif [ -f "$cwd_raw/package-lock.json" ]; then
    pkg_manager="npm"
fi

# Running dev servers (check common ports)
running_ports=""
for port in 3000 3001 4173 5173 5174 8080; do
    if lsof -i :"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        if [ -z "$running_ports" ]; then
            running_ports=":${port}"
        else
            running_ports+=", :${port}"
        fi
    fi
done

# ── LINE 1: Brand │ Project │ Model │ Context │ Git │ Session │ Effort ──
pct_color=$(color_for_pct "$pct_used")

line1="${purple}◆${reset} ${purple}${project_label}${reset}"
line1+="${sep}"
line1+="${white}${model_name}${reset}"
line1+="${sep}"
line1+="✍️ ${pct_color}${pct_used}%${reset}"

if [ -n "$git_branch" ]; then
    line1+="${sep}"
    line1+="${skip_perms}${cyan}${git_branch}${reset}"
    if [ "$git_changes" -gt 0 ]; then
        line1+=" ${red}+${git_changes}${reset}"
    fi
    if [ "$git_ahead" -gt 0 ] || [ "$git_behind" -gt 0 ]; then
        line1+=" ${muted}↑${git_ahead}↓${git_behind}${reset}"
    fi
else
    [ -n "$skip_perms" ] && line1+="${sep}${skip_perms}"
fi

if [ -n "$session_duration" ]; then
    line1+="${sep}"
    line1+="${dim}⏱ ${reset}${white}${session_duration}${reset}"
fi

line1+="${sep}"
case "$effort" in
    high)   line1+="${purple}● ${effort}${reset}" ;;
    medium) line1+="${dim}◑ ${effort}${reset}" ;;
    low)    line1+="${dim}◔ ${effort}${reset}" ;;
    *)      line1+="${dim}◑ ${effort}${reset}" ;;
esac

# ── LINE 2: System detail (optional) ───────────────────
line2=""

if [ -n "$node_ver" ]; then
    line2+="${muted}⎔${reset} ${white}node ${node_ver}${reset}"
fi

if [ -n "$pkg_manager" ]; then
    [ -n "$line2" ] && line2+="${sep}"
    line2+="${white}${pkg_manager}${reset}"
fi

if [ -n "$running_ports" ]; then
    [ -n "$line2" ] && line2+="${sep}"
    line2+="${green}● ${running_ports}${reset}"
fi

if [ -n "$git_last_commit" ]; then
    [ -n "$line2" ] && line2+="${sep}"
    line2+="${dim}\"${git_last_commit}\"${reset}"
fi

# ── Rate limits from stdin (primary) ───────────────────
has_stdin_rates=false
five_hour_pct=""
five_hour_reset_epoch=""
seven_day_pct=""
seven_day_reset_epoch=""

if [ -n "$stdin_five_pct" ]; then
    has_stdin_rates=true
    five_hour_pct=$(printf "%.0f" "$stdin_five_pct")
    five_hour_reset_epoch="$stdin_five_reset"
    seven_day_pct=$(echo "$stdin_seven_pct" | awk '{printf "%.0f", $1}')
    seven_day_reset_epoch="$stdin_seven_reset"
fi

# ── Fallback: API call (cached) ────────────────────────
cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=60

usage_data=""
extra_enabled="false"

if ! $has_stdin_rates; then
    needs_refresh=true

    if [ -f "$cache_file" ]; then
        cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
        now=$(date +%s)
        cache_age=$(( now - cache_mtime ))
        if [ "$cache_age" -lt "$cache_max_age" ]; then
            needs_refresh=false
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

    if $needs_refresh; then
        token=""
        if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
            token="$CLAUDE_CODE_OAUTH_TOKEN"
        elif command -v security >/dev/null 2>&1; then
            blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
            if [ -n "$blob" ]; then
                token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            creds_file="${HOME}/.claude/.credentials.json"
            if [ -f "$creds_file" ]; then
                token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            if command -v secret-tool >/dev/null 2>&1; then
                blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
                if [ -n "$blob" ]; then
                    token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
                fi
            fi
        fi

        if [ -n "$token" ] && [ "$token" != "null" ]; then
            response=$(curl -s --max-time 5 \
                -H "Accept: application/json" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $token" \
                -H "anthropic-beta: oauth-2025-04-20" \
                -H "User-Agent: grwthlab-statusline/1.0.0" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
                usage_data="$response"
                echo "$response" > "$cache_file"
            fi
        fi
        if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

    if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
        five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
        five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
        five_hour_reset_epoch=$(iso_to_epoch "$five_hour_reset_iso")
        seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
        seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
        seven_day_reset_epoch=$(iso_to_epoch "$seven_day_reset_iso")

        extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    fi
else
    if [ -f "$cache_file" ]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)
        if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
            extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
        fi
    fi
fi

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
bar_width=10

if [ -n "$five_hour_pct" ]; then
    five_hour_reset=$(format_epoch_time "$five_hour_reset_epoch" "time")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")
    five_hour_pct_color=$(color_for_pct "$five_hour_pct")
    five_hour_pct_fmt=$(printf "%3d" "$five_hour_pct")

    # Time remaining in the 5h window (reset - now), formatted "2h 14m" or "14m".
    five_hour_left=""
    if [[ "$five_hour_reset_epoch" =~ ^[0-9]+$ ]]; then
        rem=$(( five_hour_reset_epoch - $(date +%s) ))
        if [ "$rem" -gt 0 ]; then
            rh=$(( rem / 3600 )); rmin=$(( (rem % 3600) / 60 ))
            if [ "$rh" -gt 0 ]; then five_hour_left="${rh}h ${rmin}m"; else five_hour_left="${rmin}m"; fi
        fi
    fi

    rate_lines+="${white}current${reset} ${five_hour_bar} ${five_hour_pct_color}${five_hour_pct_fmt}%${reset}"
    [ -n "$five_hour_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${five_hour_reset}${reset}"
    [ -n "$five_hour_left" ] && rate_lines+=" ${dim}⏳${reset} ${white}${five_hour_left}${reset}"
fi

if [ -n "$seven_day_pct" ]; then
    seven_day_reset=$(format_epoch_time "$seven_day_reset_epoch" "datetime")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")
    seven_day_pct_color=$(color_for_pct "$seven_day_pct")
    seven_day_pct_fmt=$(printf "%3d" "$seven_day_pct")

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}weekly${reset}  ${seven_day_bar} ${seven_day_pct_color}${seven_day_pct_fmt}%${reset}"
    [ -n "$seven_day_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${seven_day_reset}${reset}"
fi

if [ "$extra_enabled" = "true" ] && [ -n "$usage_data" ]; then
    extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
    extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
    extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
    extra_bar=$(build_bar "$extra_pct" "$bar_width")
    extra_pct_color=$(color_for_pct "$extra_pct")

    extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [ -z "$extra_reset" ]; then
        extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    fi

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}extra${reset}   ${extra_bar} ${extra_pct_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset} ${dim}⟳${reset} ${white}${extra_reset}${reset}"
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$line2" ] && printf "\n%b" "$line2"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

exit 0
