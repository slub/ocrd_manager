#! /bin/bash
cat /authorized_keys >> /.ssh/authorized_keys
cat /id_rsa >> /.ssh/id_rsa

ssh-keyscan -H ${CONTROLLER%:*} >> /.ssh/known_hosts

# turn off the login banner
touch /.hushlogin

set | fgrep -ve BASH > /.ssh/environment

# /.ssh/rc autorun script when account is accessed by ssh
echo "cd /data" >> /.ssh/rc 

# create user specific umask
echo "umask $UMASK" >> /.ssh/rc

# removes read/write/execute permissions from group and others, but preserves whatever permissions the owner had
chmod go-rwx /.ssh/*

# set owner and group
chown $UID:$GID /.ssh/*

# set login information for SSH user
echo ocrd:x:$UID:$GID:SSH user:/:/bin/bash >> /etc/passwd

# save password informations
echo ocrd:*:19020:0:99999:7::: >> /etc/shadow

# start ssh as daemon and send output to standard error
#/usr/sbin/sshd -D -e
service ssh start

service rsyslog start

sleep 1
tail -f /var/log/syslog
