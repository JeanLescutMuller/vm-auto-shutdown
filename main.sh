#!/bin/bash
set -e

#################################################################
echo '0. Parsing arguments and Initializing constants'
#################################################################

if [ -z "$1" ]; then
    echo 'please provide the Jupyter Password as argument !'
    exit 1
else
    JUP_PASSWORD=$1
fi

R=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # ROOT

JUP_URL_API='http://127.0.0.1/jupyter'
JUP_URL_LOGIN="$JUP_URL_API/login?next=%2F"
JUP_URL_SESSIONS="$JUP_URL_API/api/sessions"
JUP_URL_TERMINALS="$JUP_URL_API/api/terminals"
JUP_COOKIES_PATH="$R/data/jupyter_cookies.txt"
ACTIVITY_SIGNALS_PATH="$R/data/activity_signals.csv"

# Execution Frequency of this script. Should match the scheduler (cron or systemD)
PERIOD_EXECUTION=5




#################################################################
echo '1. Recoding signals'
#################################################################

# ------------
# 1.1 Capturing Activity Signals :
# ------------
echo '  Uptime signals...'
seconds_uptime=$(cat /proc/uptime | cut -d ' ' -f1)
cpu_last_5min=$(uptime | awk -F', ' '{print $5}')

echo '  tmra_files...'
# "tmra" = "(Unix) Time of Most Recent Activity"
# Can ignore the broken pipe proble (sort -> Head -n1 where head break pipe before sort return)
# Or we could do it in 2 lines
tmra_files=$(find /home/enrices/ -type f \( -iname '*.ipynb' -o -iname '*.py' \) -printf '%T@\n' | sort -nr | head -1)

echo '  tmra_jupyter...'
# Authentication to Jupyter using password
rm -f $JUP_COOKIES_PATH
resp=$(curl --cookie-jar $JUP_COOKIES_PATH -s $JUP_URL_LOGIN)
regex='name="_xsrf" value="([0-9a-f|]+)"'
if [[ $resp =~ $regex ]]; then 
    _xsrf="${BASH_REMATCH[1]}"
    _xsrf_escaped=${_xsrf//|/%7C} # Replace "|" by "%7C" in url
    url="$JUP_URL_LOGIN&_xsrf=$_xsrf_escaped&password=$JUP_PASSWORD"
    curl --cookie $JUP_COOKIES_PATH --cookie-jar $JUP_COOKIES_PATH -X POST -s $url

    # Getting time of most recent kernel activity :
    jup_sessions=$(curl --cookie $JUP_COOKIES_PATH -s $JUP_URL_SESSIONS)
    if [ "$jup_sessions" != "[]" ];  then
        tmra_jup_sessions=$( echo "$jup_sessions" | jq '[ .[] | .kernel.last_activity | sub(".[0-9]+Z$"; "Z") | fromdate ] | max | values')
    fi
    
    # Getting time of most recent terminal activity :
    jup_terminals=$(curl --cookie $JUP_COOKIES_PATH -s $JUP_URL_TERMINALS)
    if [ "$jup_terminals" != "[]" ]; then
        tmra_jup_terminals=$( echo "$jup_terminals" | jq '[ .[] | .last_activity | sub(".[0-9]+Z$"; "Z") | fromdate ] | max | values')
    fi
fi

# ------------
# 1.2 Saving all on disk :
# ------------
echo '  Saving on disk...'
time_now=$(date +'%s')
mkdir -p $(dirname $ACTIVITY_SIGNALS_PATH)
# Warning: tmra_jup_sessions and tmra_jup_terminals could be EMPTY strings
echo "$time_now,$seconds_uptime,$cpu_last_5min,$tmra_files,$tmra_jup_sessions,$tmra_jup_terminals" >> $ACTIVITY_SIGNALS_PATH
# Keeping the last 30 days of signals :
echo "$(tail -n $(( 30*24*60/$PERIOD_EXECUTION )) $ACTIVITY_SIGNALS_PATH)" > $ACTIVITY_SIGNALS_PATH



#################################################################
echo '2. Shutdown Decision'
#################################################################
# These are the timeout_duration "x" = "At this rate, it would take x hours to shutdown the machine"
# We will cumulate by the INVERT (1/x) of this duration. We keep duration here for easier interpretation.
# Time in Switzerland: 2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 0  1
# Time in UTC        : 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
L_TIMEOUT_BY_UTC_HOUR=(1  1  1  1  1  1  3  6  6  6  6  6  6  6  6  6  6  6  5  4  3  2  2 1)

# We increment a counted "inactivty_points", by a rate which depends on the hour of the day
# At 60 points, we shutdown the machine
inactivity_points=0
while read line; do 

    echo "  Reading line $line ..."

    time_run=$(echo $line | cut -d',' -f1)
    seconds_uptime=$(echo $line | cut -d',' -f2)
    cpu_last_5min=$(echo $line | cut -d',' -f3)
    tmra_files=$(echo $line | cut -d',' -f4)
    tmra_jup_sessions=$(echo $line | cut -d',' -f5)
    tmra_jup_terminals=$(echo $line | cut -d',' -f6)
    
    # ------ If was active : break
    if (( $(echo "$seconds_uptime       < 120" | bc -l) )) ||\
       (( $(echo "$cpu_last_5min        > .25" | bc -l) )) ||\
       (( $(echo "$time_run-$tmra_files < 120" | bc -l) )) ||\
       ( [ ! -z "$tmra_jup_sessions"  ] && (( $(echo "$time_run-$tmra_jup_sessions  < 120" | bc -l) )) ) ||\
       ( [ ! -z "$tmra_jup_terminals" ] && (( $(echo "$time_run-$tmra_jup_terminals < 120" | bc -l) )) )
    then
        echo '    Was active ! Break'
        break
    fi
    
    # ------ Othewise : Increment counter
    echo '    Was inactive ! Increment counter...'
    hour_run=$(date -d @$time_run +%H)
    inactivity_points=$(( inactivity_points + 1/${L_TIMEOUT_BY_UTC_HOUR[$hour_run]} ))
    
    # ------ If counter reach threshold, shutdown the machine
    if (( $(echo "$inactivity_points > 60" | bc -l) )); then
        echo '    Shutdown !'
        shutdown -h now
    fi
    
done < <(tac "$ACTIVITY_SIGNALS_PATH") # Read BACKWARD from Bottom to Top !

echo "Final inactivity_points is $inactivity_points. Exiting (Success)"
