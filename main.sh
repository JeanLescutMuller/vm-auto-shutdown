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
PATH_PRV="$R/data/prv.sh"
# PATH_JSON_ALL="$R/data/activity_signals_all.json"
# PATH_JSON_LATEST="$R/data/activity_signals_latest.json"

URL_JUP_API='http://127.0.0.1/jupyter'
URL_JUP_LOGIN="$URL_JUP_API/login?next=%2F"
URL_JUP_SESS="$URL_JUP_API/api/sessions"
URL_JUP_TERM="$URL_JUP_API/api/terminals"

declare -A c # current run
declare -A p
[ -f $PATH_PRV ] && source $PATH_PRV
c['time_run']=$(date +'%s')

#################################################################
log '## 1. Capturing System signals ##'

log ' uptime signals...'
seconds_uptime=$(cat /proc/uptime | cut -d ' ' -f1)
cpu_last_5min=$(uptime | awk -F', ' '{print $5}')

log ' tmra_files...' # "tmra" = "(Unix) Time of Most Recent Activity"
# The most recent modification timestamp for all files in /home/
# Let's avoid hidden folders ? Let's avoid data (.csv, json) too ?
c['tmra_files']=$(find /home/enrices/ -regextype posix-extended -iregex '.*\.(sh|ipynb|py|md)$' -not -path '*/.*' -printf '%T@\n' | sort -n | tail -1)
# log "  tmra_files = ${c['tmra_files']}"

#################################################################
log '## 2. Capturing Jupyter signals ##'
function jupyter_auth() { # () -> bool
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
function jup_tmra() { # (url, jq_path, fallback) -> Opt[stdout]: JSON valid resp
    resp=$(curl --cookie $PATH_JUP_COOKIES -s $1)
    [ -z "$resp" ] && log "   Warning: Empty response" && return
    [ "$resp" == '[]' ] && log "   (No elements in JSON)" && return
    [ ! jq -e . >/dev/null 2>&1 <<<"$resp" ] && log "   Warning: invalid json [$resp]" && return
    date --utc +%s -d $(echo "$resp" | jq -r "[ .[] | $2] | max")
}
if jupyter_auth; then
    c['tmra_jup_sess']=$(jup_tmra $URL_JUP_SESS '.kernel.last_activity')
    c['tmra_jup_term']=$(jup_tmra $URL_JUP_TERM '.last_activity')
else
    log ' Warning: Jupyter Authenciation failed'
fi

# Fallbacks to last values, if needed
function fallback() { [ -z "${c[$1]}" ] && echo ${p[$1]} || echo ${c[$1]} ; }
c['tmra_jup_sess']=$(fallback 'tmra_jup_sess')
c['tmra_jup_term']=$(fallback 'tmra_jup_term')


#################################################################
log '## 3. Is Currently Active ? + Compute new inactivity points (counter) ##'

function cond() { (( $(echo $1 | bc -l) )) ; } # Mathematical CONDition (shortcut) -> bool
function is_jup_active() { # (curr, prv) -> bool
    [ -z "$1" ] && return $(false)  # Current emtpy => previous empty -> no reason to think we're active...
    cond "( $1>$2 && ($1-$2)<12*60 ) || ($1-$2)>60*60" && return $(true) # new HTTP AND Not a 15min beacon
    false
}
function is_active() { # () -> bool
    log "is_active()..."
    [ ! -f $PATH_PRV ] && return $(false)
    cond "$seconds_uptime < ${c['time_run']} - ${p['time_run']}" && log 'Machine rebooted' && return $(true)
    cond "$cpu_last_5min > .25" && log 'CPU high' && return $(true)
    cond "${c['tmra_files']} > ${p['tmra_files']}" && log 'Modified file' && return $(true)
    is_jup_active "${c['tmra_jup_sess']}" "${p['tmra_jup_sess']}" && log 'New Jup Sess Activity' && return $(true)
    is_jup_active "${c['tmra_jup_term']}" "${p['tmra_jup_term']}" && log 'New Jup Term Activity' && return $(true)
    false # Else, not active 
}

if is_active; then
    c['points']=0
else
    # These are the timeout_duration "x" = "At this rate, it would take x hours to shutdown the machine"
    # Time in Switzerland: 2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 0  1
    # Time in UTC        : 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
    L_TIMEOUT_BY_UTC_HOUR=(1  1  1  1  1  1  3  6  6  6  6  6  6  6  6  6  6  6  5  4  3  2  2 1)
    slope="100 / ${L_TIMEOUT_BY_UTC_HOUR[$(date -d @$time_run +%H)]} / 60 / 60"
    c['points']=$(echo "${p['points']} + $slope * (${c['time_run']} - ${p['time_run']})" | bc -l)
fi

#################################################################
log '## 4. Write to disk + Shutdown if counter above 100 points ##'
> $PATH_PRV # flush content
for x in "${!c[@]}"; do 
    log "   Writing $x='${c[$x]}'"
    printf "p[%q]=%q\n" "$x" "${c[$x]}" >> $PATH_PRV # quoted
done

cond "${c['points']} > 100" && log 'We have been idle for too long. Shutting down now.' && shutdown -h now
log "Keep waiting for activity... (points=${c['points']})"

#################################################################
log "Done (Success)"
exit 0