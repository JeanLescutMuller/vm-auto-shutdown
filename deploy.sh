#!/bin/bash

mkdir -p ./log/01_monitor_activity/rotating/
mkdir -p ./log/02_shutdown_decision/rotating/
mkdir -p ./data

# Init to create 120 log files, for manual Rotating logs via Bash (See main.sh)
touch ./log/01_monitor_activity/rotating/{0..120}.log
touch ./log/02_shutdown_decision/rotating/{0..120}.log

/opt/anaconda3/bin/jupyter nbconvert --to script '01_monitor_activity.ipynb'
/opt/anaconda3/bin/jupyter nbconvert --to script '02_shutdown_decision.ipynb'