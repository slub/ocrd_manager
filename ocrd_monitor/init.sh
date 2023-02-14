#!/usr/bin/env bash

mkdir -p ~/.ssh
cat /id_rsa >> ~/.ssh/id_rsa
chmod go-rw ~/.ssh/id_rsa

# Add ocrd controller as global and  known_hosts if env exist
if [ -n "$CONTROLLER" ]; then
  CONTROLLER_HOST=${CONTROLLER%:*}
  CONTROLLER_PORT=${CONTROLLER#*:}
  CONTROLLER_IP=$(nslookup $CONTROLLER_HOST | grep 'Address\:' | awk 'NR==2 {print $2}')

  if test -e /etc/ssh/ssh_known_hosts; then
    ssh-keygen -R $CONTROLLER_HOST -f /etc/ssh/ssh_known_hosts
    ssh-keygen -R $CONTROLLER_IP -f /etc/ssh/ssh_known_hosts
  fi
  ssh-keyscan -H -p ${CONTROLLER_PORT:-22} $CONTROLLER_HOST,$CONTROLLER_IP >>/etc/ssh/ssh_known_hosts
fi

export OCRD_BROWSER__MODE=native
export OCRD_BROWSER__WORKSPACE_DIR=/data
export OCRD_BROWSER__PORT_RANGE="[9000,9100]"
export OCRD_LOGVIEW__PORT=$MONITOR_LOG_PORT
export OCRD_CONTROLLER__JOB_DIR=/run/lock/ocrd.jobs
export OCRD_CONTROLLER__HOST=$CONTROLLER_HOST
export OCRD_CONTROLLER__PORT=$CONTROLLER_PORT
export OCRD_CONTROLLER__USER=ocrd
export OCRD_CONTROLLER__KEYFILE=~/.ssh/id_rsa

cd /usr/local/ocrd-monitor
uvicorn --host 0.0.0.0 --port 5000 "ocrdmonitor.main:app"
