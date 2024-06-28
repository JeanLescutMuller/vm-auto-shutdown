{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": 1,
   "id": "0aa5796b-283f-43da-9477-11c5f24d93d7",
   "metadata": {},
   "outputs": [],
   "source": [
    "import logging\n",
    "import sys\n",
    "import getpass\n",
    "import subprocess\n",
    "import re\n",
    "\n",
    "# For querying Jupyter API :\n",
    "import requests\n",
    "from bs4 import BeautifulSoup\n",
    "import json\n",
    "from datetime import datetime\n",
    "\n",
    "import time"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 25,
   "id": "a27d3568-28d1-4042-a1d1-d630a6924972",
   "metadata": {
    "tags": []
   },
   "outputs": [
    {
     "name": "stderr",
     "output_type": "stream",
     "text": [
      "2024-06-28 11:20:47 [   DEBUG] logger start\n"
     ]
    }
   ],
   "source": [
    "log = logging.getLogger(__name__)\n",
    "logFormatter = logging.Formatter('%(asctime)s [%(levelname)8s] %(message)s', '%Y-%m-%d %H:%M:%S') # 8s because 8 chars for CRITICAL # Only log the day for the date\n",
    "log.setLevel(logging.DEBUG)\n",
    "if 'StreamHandler' not in [ type(h).__name__ for h in log.handlers] :\n",
    "    ch = logging.StreamHandler()\n",
    "    ch.setFormatter(logFormatter)\n",
    "    log.addHandler(ch)\n",
    "log.debug('logger start')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 3,
   "id": "a5cab156-c920-4a9a-85b3-95c0513538fd",
   "metadata": {
    "tags": []
   },
   "outputs": [
    {
     "name": "stdin",
     "output_type": "stream",
     "text": [
      "jupyter_password = ········\n"
     ]
    }
   ],
   "source": [
    "# Getting password to authenticate to jupyter API :\n",
    "if sys.argv[0].split('/')[-1] == 'ipykernel_launcher.py' :\n",
    "    jupyter_password = getpass.getpass('jupyter_password =')\n",
    "else :\n",
    "    assert len(sys.argv) > 1, 'You must pass the jupyter password as argument of this script !'\n",
    "    jupyter_password = sys.argv[1]"
   ]
  },
  {
   "cell_type": "markdown",
   "id": "d89a8849-e7d5-4989-905d-ae7bd39f9169",
   "metadata": {},
   "source": [
    "---"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 4,
   "id": "3970da3d-0697-42da-a058-79ec0acd01ba",
   "metadata": {
    "tags": []
   },
   "outputs": [
    {
     "name": "stderr",
     "output_type": "stream",
     "text": [
      "2024-06-28 11:14:56 [    INFO] # 1. Activity signals :\n"
     ]
    }
   ],
   "source": [
    "##########################################\n",
    "log.info('# 1. Activity signals :')\n",
    "##########################################"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 7,
   "id": "285b70c9-e343-4cf3-9048-c369f8d27d65",
   "metadata": {
    "tags": []
   },
   "outputs": [
    {
     "name": "stderr",
     "output_type": "stream",
     "text": [
      "2024-06-28 11:15:07 [    INFO]   ## Signal 0 : Uptime\n",
      "2024-06-28 11:15:07 [   DEBUG]     uptime_seconds: 7468\n"
     ]
    }
   ],
   "source": [
    "##########################################\n",
    "log.info('  ## Signal 0 : Uptime')\n",
    "##########################################\n",
    "with open('/proc/uptime', 'r') as f:\n",
    "    seconds_uptime = int(float(f.readline().split()[0]))\n",
    "    log.debug(f'    seconds_uptime: {seconds_uptime}')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 8,
   "id": "b27c481a-f357-4d65-851a-8294fce088b5",
   "metadata": {
    "tags": []
   },
   "outputs": [
    {
     "name": "stderr",
     "output_type": "stream",
     "text": [
      "2024-06-28 11:15:09 [    INFO]   ## Signal 1 : Total CPU load for the last 60 seconds\n",
      "2024-06-28 11:15:09 [   DEBUG]     Raw output of \"uptime\": 11:15:09 up  2:04,  0 users,  load average: 0.34, 0.21, 0.13\n"
     ]
    }
   ],
   "source": [
    "##########################################\n",
    "log.info('  ## Signal 1 : Total CPU load for the last 60 seconds')\n",
    "##########################################\n",
    "raw = subprocess.check_output('uptime').decode(\"utf8\")\n",
    "log.debug(f'    Raw output of \"uptime\": {raw.strip()}')\n",
    "m = re.search('load average: ([0-9\\.]+?), ([0-9\\.]+?), ([0-9\\.]+?)\\n', raw)\n",
    "if m : \n",
    "    cpu_last_1min  = float(m.group(1))\n",
    "    cpu_last_5min  = float(m.group(2))\n",
    "    cpu_last_15min = float(m.group(3))\n",
    "else : # Just in case\n",
    "    cpu_last_1min, cpu_last_5min, cpu_last_15min = None, None, None"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 9,
   "id": "e4a0db3b-50fa-4d42-afe0-b0d767ad5ffd",
   "metadata": {
    "tags": []
   },
   "outputs": [
    {
     "name": "stderr",
     "output_type": "stream",
     "text": [
      "2024-06-28 11:15:10 [    INFO]   ## Signal 2 : Recently saved .ipynb files in /home/enrices/\n",
      "2024-06-28 11:15:19 [   DEBUG]     time_most_recent_python_file: 1719568451\n"
     ]
    }
   ],
   "source": [
    "##########################################\n",
    "log.info('  ## Signal 2 : Recently saved .ipynb files in /home/enrices/')\n",
    "##########################################\n",
    "cmd = \"find /home/enrices/ -type f -iname '*.ipynb' -o -iname '*.py' -exec stat --format '%Y' '{}' \\; | sort -nr | head -1\"\n",
    "time_most_recent_python_file = int(subprocess.check_output(cmd, shell=True).decode(\"utf8\").strip('\\n'))\n",
    "log.debug(f'    time_most_recent_python_file: {time_most_recent_python_file}')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 10,
   "id": "ad5ce6c0-3e57-4801-a3b5-444dca527311",
   "metadata": {
    "tags": []
   },
   "outputs": [
    {
     "name": "stderr",
     "output_type": "stream",
     "text": [
      "2024-06-28 11:15:19 [    INFO]   ## Signal 3 : Jupyter Kernel Activities\n",
      "2024-06-28 11:15:19 [   DEBUG]     Succesfully authenticated.\n",
      "2024-06-28 11:15:19 [   DEBUG]     time_most_recent_kernel_activity: 1719573319\n"
     ]
    }
   ],
   "source": [
    "##########################################\n",
    "log.info('  ## Signal 3 : Jupyter Kernel Activities')\n",
    "##########################################\n",
    "jupyter_api_url = 'http://127.0.0.1/jupyter' # protocol://ip:port/prefix (pay attention: all of them can change !)\n",
    "\n",
    "def authenticated_session() :\n",
    "    # Note : this will authenticate ONLY for the given jupyter_api_url.\n",
    "    # I.E : if using localhost, the session will only be allowed to query API towards localhost... etc...\n",
    "    s = requests.Session()\n",
    "    url = f'{jupyter_api_url}/login?next=%2F'\n",
    "    r = s.get(url)\n",
    "    # print(r.status_code)\n",
    "    parsed_html = BeautifulSoup(r.content.decode('utf8'), features=\"lxml\")\n",
    "    _xsrf = parsed_html.body.find('input', attrs={'name':'_xsrf'}).get('value')\n",
    "    r = s.post(url,params = {'_xsrf': _xsrf, 'password': jupyter_password})\n",
    "    # print(r.status_code)\n",
    "    return s\n",
    "# For other mode of authentication (if you're not using passwords for example) please see token\n",
    "# https://jupyterhub.readthedocs.io/en/stable/howto/rest.htmlhttps://jupyterhub.readthedocs.io/en/stable/howto/rest.html\n",
    "\n",
    "s = authenticated_session()\n",
    "log.debug('    Succesfully authenticated.')\n",
    "\n",
    "resp = s.get(f'{jupyter_api_url}/api/sessions')\n",
    "l_sessions = json.loads(resp.content)\n",
    "if len(l_sessions) > 0 :\n",
    "    most_recent_kernel_activity = max([ d_session['kernel']['last_activity'] for d_session in l_sessions ])\n",
    "    time_most_recent_kernel_activity = int(datetime.fromisoformat(most_recent_kernel_activity.rstrip('Z')).timestamp())\n",
    "else :\n",
    "    time_most_recent_kernel_activity = None\n",
    "log.debug(f'    time_most_recent_kernel_activity: {time_most_recent_kernel_activity}')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 11,
   "id": "e09cd1ff-66e0-4793-8ec8-49a6b0720fa4",
   "metadata": {
    "tags": []
   },
   "outputs": [
    {
     "name": "stderr",
     "output_type": "stream",
     "text": [
      "2024-06-28 11:15:19 [    INFO] # 2. Saving on disk :\n"
     ]
    }
   ],
   "source": [
    "##########################################\n",
    "log.info('# 2. Saving on disk :')\n",
    "##########################################"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 17,
   "id": "b4ec3b82-26f8-45fc-92f8-ae830b3f6790",
   "metadata": {
    "tags": []
   },
   "outputs": [],
   "source": [
    "l_vals = [int(time.time()), seconds_uptime, cpu_last_1min, cpu_last_5min, cpu_last_15min, time_most_recent_python_file, time_most_recent_kernel_activity]\n",
    "with open('./data/activity_signals.csv', 'a') as file :\n",
    "    file.write(','.join([str(v) for v in l_vals]) + '\\n')\n",
    "log.info('Done. (Success)')"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3 (ipykernel)",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.10.9"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 5
}