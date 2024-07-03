# Auto_Shutdown
a script to Automatically shut-doen (time-out) a VM after inactivity

## Version 1

Implemented in Bash script. Very simple

## Version 2

Implemented in Python.

- Activity signals taken into account :
  - CPU load
  - UpTime
  - Recently created/modified .ipynb or .py files in /home/
  - Activity of Jupyter kernels
- Logic to cumulate :
  - If activity, increment a counter by a value that depends on the hour of the day (faster incrementation during the night)
  
## Version 3

Implemented in Python.

- Activity signals taken into account :
  - Same as version 2
- All signals are logged into a file (we keep last 10,000 rows)
- Decision logic looks at the last X rows and take a decision

This change allows for :
- Easier Monitoring & Troubleshooting a posteriori (since we can look at all the timeline of signals) 
- More complex logics which aggregate signals during the last N minutes
  - Example: "Only consider active if Jupyter kernel were active for the last N consecutive minutes..."
 
### Deployment : 
`./deploy.sh`
Add in /etc/crontab :
```*  *    * * *   root    /home/enrices/auto_shutdown/main.sh **PASSOWRD**```
 
## Version 4

- Implemented in pure Bash
- Same Exact logic as Version 3
- Now scheduled by a SystemD service, rather than cron

This change allows for :
- Easier Monitoring & Troubleshooting a posteriori (since we can look at all the timeline of signals) 
- More complex logics which aggregate signals during the last N minutes
  - Example: "Only consider active if Jupyter kernel were active for the last N consecutive minutes..."
  
### Deployment :
`sudo ./deploy.sh **PASSWORD**`
