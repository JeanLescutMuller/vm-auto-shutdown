#!/bin/bash
set -e

#################################################################
echo '0. Parsing arguments and Initializing constants'
#################################################################

USAGE_HINT="(Usage: JUP_PASSWORD=... $0)"
if [ -z "$JUP_PASSWORD" ]; then
    echo 'JUP_PASSWORD is missing. '$USAGE_HINT
    exit 1
fi

R=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # ROOT
JUP_URL_API='http://127.0.0.1/jupyter'
JUP_URL_LOGIN="$JUP_URL_API/login?next=%2F"
JUP_URL_SESS="$JUP_URL_API/api/sessions"
JUP_URL_TERM="$JUP_URL_API/api/terminals"
JUP_COOKIES_PATH="$R/data/jupyter_cookies.txt"
PATH_JSON_ALL="$R/data/activity_signals_all.json"
PATH_JSON_LATEST="$R/data/activity_signals_latest.json"


#################################################################
echo '1. Capturing current signals'
#################################################################
time_run=$(date +'%s')

# ------------
# System & Files :
# ------------
echo '  Uptime signals...'
seconds_uptime=$(cat /proc/uptime | cut -d ' ' -f1)
cpu_last_5min=$(uptime | awk -F', ' '{print $5}')

echo '  tmra_files...'
# "tmra" = "(Unix) Time of Most Recent Activity"
# The most recent modification timestamp for all files in home (Ignoring hidden folders)
# Or via Regex ? find . -type f -regextype posix-extended -regex '.*\.(sh|ipynb|py|md)$' -printf '%T@ %p\n'
tmra_files=$(find /home/enrices/ -type f -not -path '*/.*' -printf '%T@\n' | sort -n | tail -1)

#----------------
# Jupyter signals :
#----------------
echo '  Jupyter API...'

function jupyter_auth() {
    # Authentication to Jupyter using password
    rm -f $JUP_COOKIES_PATH
    resp=$(curl --cookie-jar $JUP_COOKIES_PATH -s $JUP_URL_LOGIN)
    # echo "$resp"
    regex='name="_xsrf" value="([0-9a-f|]+)"'
    if [[ $resp =~ $regex ]]; then 
        _xsrf="${BASH_REMATCH[1]}"
        # echo "$_xsrf"
        _xsrf_escaped=${_xsrf//|/%7C} # Replace "|" by "%7C" in url
        url="$JUP_URL_LOGIN&_xsrf=$_xsrf_escaped&password=$JUP_PASSWORD"
        http_code=$(curl --cookie $JUP_COOKIES_PATH --cookie-jar $JUP_COOKIES_PATH -X POST -o /dev/null -I -w "%{http_code}" -s $url)
        [ "$http_code" == "302" ] && return 
    fi
    false
}

# Function (json_path) -> Previous value, from .json (or empty if no .json exist)
function prv() {
    >&2 echo "   prv($1)..."
    [ -f $PATH_JSON_ALL ] && jq -r '.[-1].'$1 $PATH_JSON_ALL ; 
} 
function api_json_call() { # (url,name) -> JSON valid resp
    >&2 echo "  api_json_call($1, $2)"
    resp=$(curl --cookie $JUP_COOKIES_PATH -s $1)
    if ! jq -e . >/dev/null 2>&1 <<<"$resp"; then
        >&2 echo "WARNING: $2 is not a valid json"
        # >&2 echo "$resp"
        resp=''
    fi
    [ -z "$resp" ] && prv "$2" || echo "$resp"
}

# Note : Even after Fallbacks, jup_sess & jup_term COULD STILL be empty variables (if the authentication fails + no .json on disk)
if jupyter_auth; then
    jup_sess=$(api_json_call $JUP_URL_SESS 'jup_sess')
    jup_term=$(api_json_call $JUP_URL_TERM 'jup_term')
fi


#################################################################
echo '2. Shutdown Decision'
#################################################################

function if_maths() { # (maths_expression, text) -> Boolean, and echo text if true
    echo "   if_maths($1, $2)..."
    (( $(echo $1 | bc -l) )) && echo "$2 ($1)" && return
    false
}

#----------------
# Library "is active" :
#----------------
# jq helpers :
function len() { echo "$1" | jq 'length' ; } 
function tmra() { # (val, json_path)->TMRA=Time Most Recent Activity
    echo "$1" | jq "[ .[] | $2] | max | values"
} 
# Jupyter json logic :
function if_json_has_changed() { # (val, name, json_path) -> Boolean
    echo "  if_json_has_changed($1, $2, $3)..."
    if [ ! -z "$1" ] && [ "$1" != "[]" ]; then
        prv_val=$(prv $2)
        if [ ! -z "$prv_val" ] && [ "$prv_val" != "[]" ]; then
            [ $(len $1) != $(len $prv)] && echo "Length of $2 has changed" && return
            d="$(tmra $1 $3) - $(tmra $prv_val $3)"
            if_maths "$d>60*60 || ( $d>0 && $d<12*60 )" "$2 activity, not a 15min-HTTP-beacon" && return
        else
             echo "First $2" && return
        fi
    fi
    false
}
function is_active() {
    echo "is_active()..."
    [ ! -f $PATH_JSON_ALL ] && echo "$PATH_JSON_ALL does not exist yet" && return
    if_maths "$seconds_uptime < $time_run - $(prv 'time_run')" 'Machine rebooted' && return
    if_maths "$cpu_last_5min > .25" 'CPU high' && return
    if_maths "$tmra_files > "$(prv 'tmra_files') 'Modified file' && return
    if_json_has_changed "$jup_sess" 'jup_sess' '.kernel.last_activity' && return
    if_json_has_changed "$jup_term" 'jup_term' '.last_activity' && return
    # Else, not active 
    false
}

#----------------
# Library "save" :
#----------------
function save_on_disk() {
    echo '  Saving on disk...'
    mkdir -p $(dirname $PATH_JSON_ALL)
    echo "[{
        \"time_run\":\"$time_run\",
        \"seconds_uptime\":\"$seconds_uptime\",
        \"cpu_last_5min\":\"$cpu_last_5min\",
        \"tmra_files\":\"$tmra_files\",
        \"jup_sess\":$jup_sess,
        \"jup_term\":$jup_term,
        \"inactivity_points\":\"$inactivity_points\"
    }]" > $PATH_JSON_LATEST
    if [ -f $PATH_JSON_ALL ]; then
        # Keeping the last 10_000 lines of signals : (7 days if run every minute, 14 days if every 2 minutes... etc...)
        wc $PATH_JSON_ALL
        jq  '.[-10000:] + inputs' $PATH_JSON_ALL $PATH_JSON_LATEST | sponge $PATH_JSON_ALL
        wc $PATH_JSON_ALL
    else
        cp $PATH_JSON_LATEST $PATH_JSON_ALL
        wc $PATH_JSON_ALL
    fi
}


#----------------
# Logic
#----------------

if is_active; then
    echo 'We are active ! Reseting counter...'
    inactivity_points=0
    save_on_disk
    
else 
    echo 'We are idle ! Increment counter...'
    # These are the timeout_duration "x" = "At this rate, it would take x hours to shutdown the machine"
    # We will cumulate by the INVERT (1/x) of this duration. We keep duration here for easier interpretation.
    # Time in Switzerland: 2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 0  1
    # Time in UTC        : 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
    L_TIMEOUT_BY_UTC_HOUR=(1  1  1  1  1  1  3  6  6  6  6  6  6  6  6  6  6  6  5  4  3  2  2 1)
    hour_run=$(date -d @$time_run +%H)
    inactivity_points=$(echo ="$inactivity_points + 100 * ($time_run - $prv_time_run) / ${L_TIMEOUT_BY_UTC_HOUR[$hour_run]} / 60 / 60" | bc -l)
    save_on_disk
    
    # ------ If counter reach threshold, shutdown the machine
    if_maths "$inactivity_points > 100" 'We are idle for too long. Shutting down...' && shutdown -h now
    echo "Keep waiting for activity... (inactivity_points=$inactivity_points)"

fi
echo "Done (Success)"
exit 0