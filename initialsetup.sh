#! /bin/bash
cat /root/id_rsa >> /root/.ssh/id_rsa

chmod 700 /root/.ssh/id_rsa

ssh-keyscan -H ocrd-controller >> ~/.ssh/known_hosts  

"$@"