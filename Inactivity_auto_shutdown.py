#!/usr/bin/env python
# coding: utf-8

# In[ ]:


# Init to create N (in this case N=30) log files, for manual Rotating logs via Bash (See cron below)

# ! mkdir -p ./rotating_logs
# ! mkdir -p ./shutdown_logs
# ! touch ./rotating_logs/{10..40}.log


# In[ ]:


# Please add 2 lines in CRON : 
# 1 to delete /tmp/ at reboot, just in case
# 1 to run the script every minute, log in rotating log files, and redirect stderr to stdout (to log everything, including exceptions)

# # Example of job definition:
# # .---------------- minute (0 - 59)
# # |  .------------- hour (0 - 23)
# # |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# # |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# # |  |  |  |  |
# # *  *  *  *  * user-name command to be executed

# @reboot         root    rm -f /tmp/auto_shutdown_data.json # JustInCase /tmp/ is not flushed at reboot

# Prefer option 2 here below (PREFER OPTION 2)
# With option 1, In case of reboot, we could overwrite the MOST recent file (same minute than before reboot)
# *  *    * * *   root    cd /home/enrices/Auto_Shutdown && /opt/anaconda3/bin/python3 Inactivity_auto_shutdown.py > ./rotating_logs/minute=`date +\%M`.log 2>&1
# *  *    * * *   root    cd /home/enrices/Auto_Shutdown && /opt/anaconda3/bin/python3 Inactivity_auto_shutdown.py> ./rotating_logs/$(ls -tr ./rotating_logs/ | head -n 1) 2>&1


# In[ ]:


import os
import subprocess
import re
from datetime import datetime, timedelta
import logging
import json
import shutil

# For querying Jupyter API :
import requests
from bs4 import BeautifulSoup


# In[ ]:


log = logging.getLogger(__name__)
logFormatter = logging.Formatter('%(asctime)s [%(levelname)8s] %(message)s', '%Y-%m-%d %H:%M:%S') # 8s because 8 chars for CRITICAL # Only log the day for the date
log.setLevel(logging.DEBUG)
if 'StreamHandler' not in [ type(h).__name__ for h in log.handlers] :
    ch = logging.StreamHandler()
    ch.setFormatter(logFormatter)
    log.addHandler(ch)
try : 
    if 'FileHandler' not in [ type(h).__name__ for h in log.handlers] :
        fh = logging.FileHandler('/tmp/latest_auto_shutdown.log', mode='w') # Overwrite
        fh.setFormatter(logFormatter)
        log.addHandler(fh)
except PermissionError as e :
    log.warning('Cannot write log to /tmp/latest_auto_shutdown.log due to permission error (are we developing using Enrices user ?)')

log.debug('logger start')


# ---

# In[ ]:


##########################################
log.info('# 1. Activity signals :')
##########################################


# In[ ]:


now = datetime.now() # Note that time is UTC

def analyze_current_activities() :
    
    ##########################################
    log.info('  ## Signal 1 : Total CPU load for the last 60 seconds')
    ##########################################
    d_cpu_thresholds = {'last_minute': .50, 'last_5_minutes': .25, 'last_15_minutes': .15}
    raw = subprocess.check_output('uptime').decode("utf8")
    log.debug(f'    Raw output of "uptime": {raw.strip()}')
    m = re.search('load average: ([0-9\.]+?), ([0-9\.]+?), ([0-9\.]+?)\n', raw)
    if m : 
        for i, (agg_name, threshold) in enumerate(d_cpu_thresholds.items()) :
            value = float(m.group(i+1))
            if value > threshold :
                log.info(f'    CPU agg "{agg_name}" is {value} > {threshold}. We are currently ACTIVE')
                return True
            else :
                log.debug(f'    CPU agg "{agg_name}" is {value} <= {threshold}. Cannot say we are active...')
        
    
    ##########################################
    log.info('  ## Signal 2 : Recently saved .ipynb files in /home/enrices/')
    ##########################################
    cmd = "find /home/enrices/ -type f -name '*.ipynb' -newermt '1 minute ago'"
    output = subprocess.check_output(cmd, shell=True).decode("utf8").strip('\n')
    set_recently_saved_files = set() if len(output)==0 else set(output.split('\n'))
    log.debug(f'    set_recently_saved_files = {set_recently_saved_files}')
    N_recently_saved_files = len(set_recently_saved_files)
    if N_recently_saved_files == 0 :
        log.debug(f'    N_recently_saved_files = 0. Cannot say we are active...')
    else :
        log.info(f'    N_recently_saved_files = {N_recently_saved_files}. We are currently ACTIVE')
        return True


    ##########################################
    log.info('  ## Signal 3 : Jupyter Kernel Activities')
    ##########################################
    jupyter_api_url = 'http://127.0.0.1/jupyter' # protocol://ip:port/prefix (all of them can change !)

    def authenticated_session() :
        # Note : this will authenticate ONLY for the given jupyter_api_url.
        # I.E : if using localhost, the session will only be allowed to query API towards localhost... etc...
        s = requests.Session()
        url = f'{jupyter_api_url}/login?next=%2F'
        r = s.get(url)
        # print(r.status_code)
        parsed_html = BeautifulSoup(r.content.decode('utf8'), features="lxml")
        _xsrf = parsed_html.body.find('input', attrs={'name':'_xsrf'}).get('value')
        r = s.post(url,params = {'_xsrf': _xsrf, 'password': 'jklmjklm34'})
        # print(r.status_code)
        return s
    # For other mode of authentication (if you're not using passwords for example) please see token
    # https://jupyterhub.readthedocs.io/en/stable/howto/rest.htmlhttps://jupyterhub.readthedocs.io/en/stable/howto/rest.html

    s = authenticated_session()
    log.debug('    Succesfully authenticated.')

    resp = s.get(f'{jupyter_api_url}/api/sessions')
    l_sessions = json.loads(resp.content)
    if len(l_sessions) == 0 :
        log.debug(f'    No Jupyter Sessions. Cannot say we are active...')
    else :
        l_kernel_states = [ d_session['kernel']['execution_state']=='busy' for d_session in l_sessions ]
        if any(l_kernel_states) :
            log.info(f'    l_kernel_states={l_kernel_states}. We are currently ACTIVE')
            return True
        else :
            log.debug(f'    l_kernel_states={l_kernel_states}. Cannot say we are active...')
            
        most_recent_kernel_activity = max([ d_session['kernel']['last_activity'] for d_session in l_sessions ])
        most_recent_kernel_activity = datetime.fromisoformat(most_recent_kernel_activity.rstrip('Z'))
        if (now - most_recent_kernel_activity).total_seconds() < 60 :
            log.info(f'    most_recent_kernel_activity={most_recent_kernel_activity} --> Less than 60 seconds ago. We are currently ACTIVE')
            return True
        else :
            log.debug(f'    most_recent_kernel_activity={most_recent_kernel_activity} --> More than 60 seconds ago. Cannot say we are active...')
   
    return False

is_currently_active = analyze_current_activities()
log.debug(f'is_currently_active = {is_currently_active}')


# ----

# In[ ]:


##########################################
log.info('# 2. Preparing persistent data (maybe from the file on-disk)')
##########################################

path = '/tmp/auto_shutdown_data.json' # /tmp/ will be cleaned at restart

if not os.path.exists(path) or is_currently_active is True :
    d_persisted = dict(
        inactivity_points = 0,
        last_activity_datetime_str = now.isoformat()
    )
    
else :
    with open(path, 'r') as file :
        d_persisted = json.load(file)
    
    # "Hour of the day" --> Inactivity points that are gained incrementally
    # At 60 points, we shutdown the machine
    # So 1/x means "At this rate, it would take x hours to shutdown the machine"
    # Reminder : These "hours" are UTC
    d_inactivity_points = {k:1/v for k,v in {
        23:1, 0:1, 1:1, 2:1, 3:1, 4:1, 5:1,
        6:3,
        7:6, 8:6,  9:6, 10:6, 11:6, 12:6, 13:6, 14:6, 15:6, 16:6, 17:6,
        18:5,
        19:4,
        20:3,
        21:2, 22:2,
    }.items() }
    d_persisted['inactivity_points'] += d_inactivity_points[now.hour]


# ----

# In[ ]:


##########################################
log.info('# 3. Writing data back to disk...')
##########################################

with open(path, 'w') as file :
    json.dump(d_persisted, file, indent=3)


# ---

# In[ ]:


##########################################
log.info('# 4. Deciding on Shutdown...')
##########################################

if d_persisted['inactivity_points'] > 60 :
    
    # Last Safeguard: do not shutdown if the system has been running for less than 1 hour
    with open('/proc/uptime', 'r') as f:
        uptime_seconds = float(f.readline().split()[0])
    if uptime_seconds < 3600. :
        log.info(f'inactivity_points={d_persisted["inactivity_points"]}>= 60., but uptime_seconds={uptime_seconds}<3600. Keeping the machine running...')
    else :
        log.info(f'inactivity_points={d_persisted["inactivity_points"]}>= 60., shuting down the machine immediately.')
        # Additionally, persist this log
        shutil.copyfile('/tmp/latest_auto_shutdown.log', f'./shutdown_logs/shutdown_{now.isoformat()}.log')
        os.system('shutdown -h now')
else :
    log.info(f'total inactivity_points = {d_persisted["inactivity_points"]} < 60.. Just silently exiting this process.')

