#!/bin/bash
set -e

# Source : https://superuser.com/questions/733232/how-to-read-current-history-of-a-still-logged-in-user
# Source : https://stackoverflow.com/questions/35927760/how-can-i-loop-over-the-output-of-a-shell-command
# Source : https://stackoverflow.com/questions/16854280/a-variable-modified-inside-a-while-loop-is-not-remembered
# Warning : This will not capture sudo statements...
tmra_bash_history=0
pgrep -u enrices -f '/bin/bash -l' | while read -r pid ; do
    ./dump_history.sh "$pid" > /dev/null 2>&1
    time=$(sed -n 'x;$p' "./data/history-dump-"$pid".txt" | tail -c+2)
    if [[ "$time" -gt "$tmra_bash_history" ]]; then
        tmra_bash_history="$time"
        echo "$tmra_bash_history" > ./data/tmra_bash_history
    fi
done

cat ./data/tmra_bash_history