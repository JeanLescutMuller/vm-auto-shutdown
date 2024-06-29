#!/bin/bash

# Init to create 120 log files, for manual Rotating logs via Bash (See main.sh)
# an "if" here to NOT TOUCH if directory already exist. we want to keep modification time intact.
if [ ! -d ./log/01_record_activity/rotating/ ]; then
    mkdir -p ./log/01_record_activity/rotating/
    touch ./log/01_record_activity/rotating/{0..120}.log
fi
if [ ! -d ./log/02_shutdown_decision/rotating/ ]; then
    mkdir -p./log/02_shutdown_decision/rotating/
    touch ./log/02_shutdown_decision/rotating/{0..120}.log
fi
mkdir -p ./data

# Updating .py files
/opt/anaconda3/bin/jupyter nbconvert --to script '01_record_activity.ipynb'
/opt/anaconda3/bin/jupyter nbconvert --to script '02_shutdown_decision.ipynb'
