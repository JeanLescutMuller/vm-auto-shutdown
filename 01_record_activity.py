#!/usr/bin/env python
# coding: utf-8

# In[4]:


import sys
from pathlib import Path # We are supposed to use this since Python 3.8
import logging
import getpass
import subprocess
import re

# For querying Jupyter API :
import requests
from bs4 import BeautifulSoup
import json
from datetime import datetime

import time


# In[5]:


# 1) Getting password to authenticate to jupyter API :
# 2) Define ROOT for absolute path (much safer)
if sys.argv[0].split('/')[-1] == 'ipykernel_launcher.py' :
    jupyter_password = getpass.getpass('jupyter_password =')
    R = Path.cwd()
else :
    assert len(sys.argv) > 1, 'You must pass the jupyter password as argument of this script !'
    jupyter_password = sys.argv[1]
    R = Path(__file__).parent


# In[6]:


log = logging.getLogger(__name__)
logFormatter = logging.Formatter('%(asctime)s [%(levelname)8s] %(message)s', '%Y-%m-%d %H:%M:%S') # 8s because 8 chars for CRITICAL # Only log the day for the date
log.setLevel(logging.DEBUG)
if 'StreamHandler' not in [ type(h).__name__ for h in log.handlers] :
    ch = logging.StreamHandler()
    ch.setFormatter(logFormatter)
    log.addHandler(ch)
log.debug('logger start')


# ---

# In[4]:


##########################################
log.info('# 1. Activity signals :')
##########################################


# In[7]:


##########################################
log.info('  ## Signal 0 : Uptime')
##########################################
with open('/proc/uptime', 'r') as f:
    seconds_uptime = int(float(f.readline().split()[0]))
    log.debug(f'    seconds_uptime: {seconds_uptime}')


# In[8]:


##########################################
log.info('  ## Signal 1 : Total CPU load for the last 60 seconds')
##########################################
raw = subprocess.check_output('uptime').decode("utf8")
log.debug(f'    Raw output of "uptime": {raw.strip()}')
m = re.search('load average: ([0-9\.]+?), ([0-9\.]+?), ([0-9\.]+?)\n', raw)
if m : 
    cpu_last_1min  = float(m.group(1))
    cpu_last_5min  = float(m.group(2))
    cpu_last_15min = float(m.group(3))
else : # Just in case
    cpu_last_1min, cpu_last_5min, cpu_last_15min = None, None, None


# In[9]:


##########################################
log.info('  ## Signal 2 : Recently saved .ipynb files in /home/enrices/')
##########################################

# Option 1 : recursively list all .py/.ipynb files and output the "most recent modified timestamp"
#   Source: https://stackoverflow.com/questions/35878134/format-the-timestamp-using-the-find-command
#   Adapted to : find /home/enrices/ -type f \( -iname '*.ipynb' -o -iname '*.py' \) -printf '%T@ %P\n'
#   And the simplified to below :
#   cmd = "find /home/enrices/ -type f \( -iname '*.ipynb' -o -iname '*.py' \) -printf '%T@\n' | sort -nr | head -1"
#   %timeit: 6.57 s ± 836 ms per loop (mean ± std. dev. of 7 runs, 1 loop each)

# Option 2 : Only list files that have been updated recently
#   cmd = "find /home/enrices/ -type f \( -iname '*.ipynb' -o -iname '*.py' \) -newermt '1 minute ago'"
#   %timeit: 6.43 s ± 600 ms per loop (mean ± std. dev. of 7 runs, 1 loop each)
#   cmd = "find /home/enrices/ -type f \( -iname '*.ipynb' -o -iname '*.py' \) -mmin -60"
#   --> Not faster, in the end

cmd = "find /home/enrices/ -type f \( -iname '*.ipynb' -o -iname '*.py' \) -printf '%T@\n' | sort -nr | head -1"
raw_output = subprocess.check_output(cmd, shell=True).decode("utf8").strip('\n')
time_most_recent_python_file = int(float(raw_output))
log.debug(f'    time_most_recent_python_file: {time_most_recent_python_file}')


# In[10]:


##########################################
log.info('  ## Signal 3 : Jupyter Kernel Activities')
##########################################
jupyter_api_url = 'http://127.0.0.1/jupyter' # protocol://ip:port/prefix (pay attention: all of them can change !)

def authenticated_session() :
    # Note : this will authenticate ONLY for the given jupyter_api_url.
    # I.E : if using localhost, the session will only be allowed to query API towards localhost... etc...
    s = requests.Session()
    url = f'{jupyter_api_url}/login?next=%2F'
    r = s.get(url)
    # print(r.status_code)
    parsed_html = BeautifulSoup(r.content.decode('utf8'), features="lxml")
    _xsrf = parsed_html.body.find('input', attrs={'name':'_xsrf'}).get('value')
    r = s.post(url,params = {'_xsrf': _xsrf, 'password': jupyter_password})
    # print(r.status_code)
    return s
# For other mode of authentication (if you're not using passwords for example) please see token
# https://jupyterhub.readthedocs.io/en/stable/howto/rest.htmlhttps://jupyterhub.readthedocs.io/en/stable/howto/rest.html

s = authenticated_session()
log.debug('    Succesfully authenticated.')

resp = s.get(f'{jupyter_api_url}/api/sessions')
l_sessions = json.loads(resp.content)
if len(l_sessions) > 0 :
    most_recent_kernel_activity = max([ d_session['kernel']['last_activity'] for d_session in l_sessions ])
    time_most_recent_kernel_activity = int(datetime.fromisoformat(most_recent_kernel_activity.rstrip('Z')).timestamp())
else :
    time_most_recent_kernel_activity = None
log.debug(f'    time_most_recent_kernel_activity: {time_most_recent_kernel_activity}')


# In[11]:


##########################################
log.info('# 2. Saving on disk :')
##########################################


# In[17]:


l_vals = [int(time.time()), seconds_uptime, cpu_last_1min, cpu_last_5min, cpu_last_15min, time_most_recent_python_file, time_most_recent_kernel_activity]
with open(R.joinpath('./data/activity_signals.csv'), 'a') as file :
    file.write(','.join([str(v) for v in l_vals]) + '\n')
log.info('Done. (Success)')

