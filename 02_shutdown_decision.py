#!/usr/bin/env python
# coding: utf-8

# In[3]:


import sys
from pathlib import Path 
import logging
import pandas as pd
from datetime import datetime
import shutil


# In[4]:


# Define ROOT for absolute path (much safer)
if sys.argv[0].split('/')[-1] == 'ipykernel_launcher.py' :
    R = Path.cwd()
else :
    R = Path(__file__).parent


# In[5]:


log = logging.getLogger(__name__)
logFormatter = logging.Formatter('%(asctime)s [%(levelname)8s] %(message)s', '%Y-%m-%d %H:%M:%S') # 8s because 8 chars for CRITICAL # Only log the day for the date
log.setLevel(logging.DEBUG)
if 'StreamHandler' not in [ type(h).__name__ for h in log.handlers] :
    ch = logging.StreamHandler()
    ch.setFormatter(logFormatter)
    log.addHandler(ch)
try : 
    if 'FileHandler' not in [ type(h).__name__ for h in log.handlers] :
        fh = logging.FileHandler('/tmp/current_shutdown_decision.log', mode='w') # Overwrite
        fh.setFormatter(logFormatter)
        log.addHandler(fh)
except PermissionError as e :
    log.warning('Cannot write log to /tmp/current_shutdown_decision.log due to permission error (are we developing using Enrices user ?)')

log.debug('logger start')


# ---

# In[6]:


##########################################
log.info('# 2. Deciding on Shutdown...')
##########################################


# In[7]:


l_cols = ['time_run', 'seconds_uptime', 'cpu_last_1min', 'cpu_last_5min', 'cpu_last_15min', 'time_most_recent_python_file', 'time_most_recent_kernel_activity']
df = pd.read_csv(R.joinpath('./data/activity_signals.csv'), names=l_cols, header=None, na_values=['None'])


# In[42]:


PERIOD_EXECUTION = 5 # Signals are recorded every 10 minutes.

# We increment a counted "inactivty_points", by a rate which depends on the hour of the day
# At 60 points, we shutdown the machine
inactivity_points = 0

# These are the timeout_duration "x" = "At this rate, it would take x hours to shutdown the machine"
# We will cumulate by the INVERT (1/x) of this duration. We keep duration here for easier interpretation.
# Time in Switzerland :  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 0,  1
# Time in UTC         :  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23
L_TIMEOUT_BY_UTC_HOUR = [1,  1,  1,  1,  1,  1,  3,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  5,  4,  3,  2,  2, 1]

for _, r in df.sort_values('time_run', ascending=False).iterrows() :
    
    # If active, then break
    if (
        r['seconds_uptime'] < 2*60
        or r['time_run']-r['time_most_recent_python_file'] < 2*60
        or r['time_run']-r['time_most_recent_kernel_activity'] < 2*60
        # or r['cpu_last_1min'] > .50
        or r['cpu_last_5min'] > .25
        # or r['cpu_last_15min'] > .20
    ) :
        break
        
    # Else, cumulate :
    inactivity_points += PERIOD_EXECUTION * 1 / L_TIMEOUT_BY_UTC_HOUR[datetime.fromtimestamp(r['time_run']).hour]
    
    if inactivity_points > 60 :
        # Safeguard: do not shutdown if the system has been running for less than 1 hour
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
        if uptime_seconds < 3600. :
            log.warning(f'inactivity_points={inactivity_points}>= 60., but uptime_seconds={uptime_seconds}<3600. Keeping the machine running...')
        else :
            log.info(f'inactivity_points={inactivity_points}>= 60., shuting down the machine immediately.')
            # Additionally, persist this log
            shutil.copyfile(
                '/tmp/current_shutdown_decision.log', 
                R.joinpath('./log/02_shutdown_decision/last_shutdown.log') 
            )
            os.system('shutdown -h now')

log.info(f'total inactivity_points = {inactivity_points} < 60.. Just silently exiting this process.')


# In[ ]:




