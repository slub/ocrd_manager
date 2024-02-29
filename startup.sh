#! /bin/bash
# avoid repeating file actions when restarting container:
if ! grep -q ^ocrd: /etc/passwd; then

cat /authorized_keys >>/.ssh/authorized_keys
cat /id_rsa >>/.ssh/id_rsa

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
  # tilde syntax for HOME dir in ssh_config does not work for root for some reason
  cat <<EOF >> /etc/ssh/ssh_config
IdentityFile /.ssh/id_rsa
IdentityFile /.ssh/id_dsa
IdentityFile /.ssh/id_ecdsa
IdentityFile /.ssh/id_ed25519
EOF
fi

# turn off the login banner
> /.hushlogin

set | fgrep -ve BASH >/.ssh/environment

# /.ssh/rc autorun script when account is accessed by ssh
echo "cd /data" >>/.ssh/rc

# create user specific umask
echo "umask $UMASK" >>/.ssh/rc

# removes read/write/execute permissions from group and others, but preserves whatever permissions the owner had
chmod go-rwx /.ssh/*

# set owner and group
chown -R $UID:$GID /.ssh

# set login information for SSH user
echo ocrd:x:$UID:$GID:SSH user:/:/bin/bash >>/etc/passwd

# save password informations
echo ocrd:*:19020:0:99999:7::: >>/etc/shadow

# Replace imklog to prevent starting problems of rsyslog
/bin/sed -i '/imklog/s/^/#/' /etc/rsyslog.conf
# rsyslog upd reception on port 514
/bin/sed -i '/imudp/s/^#//' /etc/rsyslog.conf

fi

# start syslog
service rsyslog start

# start ssh as daemon and send output to standard error
#/usr/sbin/sshd -D -e
service ssh start

# start REST webservice
socat -d -ly TCP-LISTEN:4004,reuseaddr,fork,pf=ip4 exec:sampo.sh &

sleep 2
# connect syslog to container stdout
tail -f /var/log/syslog
