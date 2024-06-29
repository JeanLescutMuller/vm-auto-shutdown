#!/bin/bash

jupyter_password=$1
R=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # ROOT
P=/opt/anaconda3/bin/python3 # python binary path

# Note : For Rotating logs, dont use the dirty trick  ./rotating_logs/minute=`date +\%M`.log
# Why ? We could overwrite the MOST recent file (same minute than before reboot)
# Rather use the oldest modified file, like this :
oldest_path () {
    echo $1/$(ls -tr $1 | head -n 1)
}

# Always stream the python log to stdout, and write to file bia bash + 2>&1. So we can have Uncaught Exceptions as well
$P $R/01_record_activity.py "$jupyter_password" > $(oldest_path $R/log/01_record_activity/rotating)  2>&1

# Keep last 10,080 lines (= 1 week of data) of the .csv file (Never do "tail file > file")
# Source: https://unix.stackexchange.com/questions/310860/how-do-you-keep-only-the-last-n-lines-of-a-log-file
echo "$(tail -10080 $R/data/activity_signals.csv)" > $R/data/activity_signals.csv

$P $R/02_shutdown_decision.py > $(oldest_path $R/log/02_shutdown_decision/rotating) 2>&1

# Data & Logs look like this :
# data/activity_signals.csv
# log/01_monitor_activity/rotating/*.log
# log/02_shutdown_decision/rotating/*.log
# log/02_shutdown_decision/last_shutdown.log
