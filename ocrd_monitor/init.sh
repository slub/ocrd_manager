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

broadwayd :5 &

flask --app /usr/local/ocrd-monitor/app --debug run 