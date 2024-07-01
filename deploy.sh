#!/bin/bash

if [ -z "$1" ]; then
    echo 'please provide the Jupyter Password as argument !'
    exit 1
else
    JUP_PASSWORD=$1
fi

# Install dependencies
apt-get install -y jq bc

# Copy Script
R=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # ROOT
mkdir -p /opt/vm-auto-shutdown
cp $R/main.sh /opt/vm-auto-shutdown/main.sh
chmod +x /opt/vm-auto-shutdown/main.sh # Should not be necessary

# Setup Service
cat > /lib/systemd/system/vm-auto-shutdown.service << EOF
[Unit]
Description=Checks whether to shutdown the instance.

[Service]
Type=oneshot
PIDFile=/run/vm-auto-shutdown.pid
ExecStart=/opt/vm-auto-shutdown/main.sh "$JUP_PASSWORD"
User=root
Group=root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.targetf
EOF

# Setup Service Timer
cat > /lib/systemd/system/vm-auto-shutdown.timer << EOF
[Unit]
Description=Run vm-auto-shutdown service every 5 minutes

[Timer]
OnActiveSec=5min
OnUnitActiveSec=5min
Unit=vm-auto-shutdown

[Install]
WantedBy=timers.target
EOF

# Start the service
systemctl daemon-reload
systemctl start vm-auto-shutdown.timer
