#!/bin/bash

USAGE_HINT="(Usage: sudo JUP_PASSWORD=... ./deploy_systemd.sh.)"
if [ -z "$JUP_PASSWORD" ]; then
    echo 'JUP_PASSWORD is missing. '$USAGE_HINT
    exit 1
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
ExecStart=/opt/vm-auto-shutdown/main.sh
Environment="JUP_PASSWORD=$JUP_PASSWORD"
User=root
Group=root
WorkingDirectory=/opt/vm-auto-shutdown

[Install]
WantedBy=multi-user.targetf
EOF

# Setup Service Timer
cat > /lib/systemd/system/vm-auto-shutdown.timer << EOF
[Unit]
Description=Run vm-auto-shutdown service every 5 minutes

[Timer]
OnCalendar=*:0/2
Unit=vm-auto-shutdown.service

[Install]
WantedBy=timers.target
EOF

# Start the service
systemctl daemon-reload
systemctl start vm-auto-shutdown.timer

# Checks
systemd-analyze verify vm-auto-shutdown.service
systemd-analyze verify vm-auto-shutdown.timer