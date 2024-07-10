#!/bin/bash
set -e

function log() { >&2 echo `date +"%Y-%m-%d %H:%M:%S.%N "`"$1" ; }

#################################################################
log '## 0. Parsing arguments and Initializing constants ##'

if [ -z "$JUP_PASSWORD" ]; then
    log "JUP_PASSWORD is missing. (Usage: sudo JUP_PASSWORD=... $0)"
    exit 1
fi

R=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # ROOT
PATH_JUP_COOKIES="$R/data/jupyter_cookies.txt"
PATH_HISTORY_CSV="$R/data/variable_history.csv"
URL_JUP_API='http://127.0.0.1/jupyter'
URL_JUP_LOGIN="$URL_JUP_API/login?next=%2F"
URL_JUP_SESS="$URL_JUP_API/api/sessions"
URL_JUP_TERM="$URL_JUP_API/api/terminals"

time_run=$(date +'%s')

#################################################################
log '## 1. Capturing System signals ##'

log ' uptime signals...'
s_uptime=$(cat /proc/uptime | cut -d ' ' -f1) # "seconds of uptime"
cpu_l5min=$(uptime | awk -F', ' '{print $5}') # _l5min = "last 5 minutes"

log ' tmra_files...' # tmra_ = (Unix) Time of Most Recent Activity
# The most recent modification epoch for all files in /home/enrices/
# - Avoid : Hidden folders, 'data' folders, 'log' folders
# - Include only : files with extensions 'sh', 'ipynb', 'py' and 'md'
# Note: we COULD include data folder and allow more extensins (maybe alls) to capture scraping activity as well. But the command will take longer.
tmra_files=$(find /home/enrices/ -path '*/.*' -prune , -path '*/data*' -prune , -path '*/log*' -prune , -regextype posix-extended -iregex '.*\.(sh|ipynb|py|md)$' -printf '%T@\n' | sort -n | tail -1)
# log "  tmra_files = $tmra_files"

#################################################################
log '## 2. Capturing Jupyter signals ##'
function jupyter_auth() { # () -> bool: Success
    # Authentication to Jupyter using password
    rm -f $PATH_JUP_COOKIES
    resp=$(curl --cookie-jar $PATH_JUP_COOKIES -s $URL_JUP_LOGIN)
    regex='name="_xsrf" value="([0-9a-f|]+)"'
    if [[ $resp =~ $regex ]]; then 
        _xsrf="${BASH_REMATCH[1]}"
        _xsrf_escaped=${_xsrf//|/%7C} # Replace "|" by "%7C" in url
        url="$URL_JUP_LOGIN&_xsrf=$_xsrf_escaped&password=$JUP_PASSWORD"
        http_code=$(curl --cookie $PATH_JUP_COOKIES --cookie-jar $PATH_JUP_COOKIES -X POST -o /dev/null -I -w "%{http_code}" -s $url)
        [ "$http_code" == "302" ] && return $(true)
    fi
    false
}
function jup_tmra() { # (url, jq_path) -> opt[stdout]: Unix Epoch
    resp=$(curl --cookie $PATH_JUP_COOKIES -s $1)
    [ -z "$resp" ] && log "   Warning: Empty response" && return
    [ "$resp" == '[]' ] && log "   (No elements in JSON)" && return
    [ ! jq -e . >/dev/null 2>&1 <<<"$resp" ] && log "   Warning: invalid json [$resp]" && return
    date --utc +%s -d $(echo "$resp" | jq -r "[ .[] | $2] | max")
}
if jupyter_auth; then
    tmra_sess=$(jup_tmra $URL_JUP_SESS '.kernel.last_activity') && log "  tmra_sess=$tmra_sess"
    tmra_term=$(jup_tmra $URL_JUP_TERM '.last_activity') && log "  tmra_term=$tmra_term"
else
    log ' Warning: Jupyter Authenciation failed'
fi


#################################################################
log '## 3. Compute new inactivity counter (+ I/O to disk) ##'

function cond() { (( $(echo $1 | bc -l) )) ; } # Shortcut "Mathematical condition" (maths) -> bool
function is_jup_active() { # (curr, prv) -> bool
    [ -z "$2" ] && return $(false)  # Previous empty -> no reason to think we're active...
    cond "( $1>$2 && ($1-$2)<12*60 ) || ($1-$2)>60*60" && return $(true) # "new HTTP" AND "Not a 15min beacon"
    false
}
function is_active() { # () -> bool
    log "is_active()..."
    cond "$s_uptime < $time_run - $p_time_run" && log 'Machine rebooted' && return $(true) # p_ = previous_
    cond "$cpu_l5min > .25" && log 'CPU high' && return $(true)
    cond "$tmra_files > $p_tmra_files" && log 'Modified file' && return $(true)
    is_jup_active "$tmra_sess" "$p_tmra_sess" && log 'New Jup Sess Activity' && return $(true)
    is_jup_active "$tmra_term" "$p_tmra_term" && log 'New Jup Term Activity' && return $(true)
    false # Else, not active 
}

if [ ! -f $PATH_HISTORY_CSV ]; then
    counter=0
else 
    # p_ = previous_
    IFS=',' read -r p_time_run p_s_uptime p_cpu_l5min p_tmra_files p_tmra_sess p_tmra_term p_counter <<< $(tail -1 $PATH_HISTORY_CSV)
    [ -z "$tmra_sess" ] && tmra_sess=$p_tmra_sess && log "  tmra_sess=$tmra_sess" # Fallback on PRV
    [ -z "$tmra_term" ] && tmra_term=$p_tmra_term && log "  tmra_term=$tmra_term" # Fallback on PRV
    if is_active ; then
        counter=0
    else
        # These are the timeout_duration "x" = "At this rate, it would take x hours to shutdown the machine"
        # Time in Switzerland: 2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 0  1
        # Time in UTC        : 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
        L_TIMEOUT_BY_UTC_HOUR=(1  1  1  1  1  1  5  5  4  4  4  4  4  4  4  4  4  4  4  4  3  2  2 1)
        h=$(date -d @$time_run +%H)
        maths_slope="100 / ${L_TIMEOUT_BY_UTC_HOUR[$h]} / 60 / 60"
        counter=$(echo "$p_counter + $maths_slope * ($time_run - $p_time_run)" | bc -l)
    fi    
fi

# Log to disk + Keeping the last 10,000 rows of signals :
# Warning: tmra_sessions and tmra_terminals could be EMPTY strings
mkdir -p $(dirname $PATH_HISTORY_CSV)
echo "$time_run,$s_uptime,$cpu_l5min,$tmra_files,$tmra_sess,$tmra_term,$counter" >> $PATH_HISTORY_CSV
echo "$(tail -n 10000 $PATH_HISTORY_CSV)" > $PATH_HISTORY_CSV # (never do "tail f > f" directly). Maybe add a if wc -l here...


#################################################################
log '## 4. Shutdown if counter above 100 counter ##'
cond "$counter > 100" && log 'We have been idle for too long. Shutting down now.' && shutdown -h now
log "Keep waiting for activity... (counter=$counter)"