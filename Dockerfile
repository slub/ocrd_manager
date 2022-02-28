# github.com/OCR-D/core
# https://hub.docker.com/r/ocrd/core/dockerfile
# ocrd/core # ubuntu:18.04
FROM ocrd/core:latest

MAINTAINER markus.weigelt@slub-dresden.de

# make apt system functional
RUN apt-get update && \
    apt-get install -y \
	apt-utils \
	nano \
	dos2unix \
	openssh-server \
	openssh-client && \
    apt-get clean

# run OpenSSH server
RUN ssh-keygen -A
RUN mkdir /run/sshd /.ssh
RUN echo Banner none >> /etc/ssh/sshd_config
RUN echo PrintMotd no >> /etc/ssh/sshd_config
RUN echo PermitUserEnvironment yes >> /etc/ssh/sshd_config
RUN echo PermitUserRC yes >> /etc/ssh/sshd_config
RUN echo X11Forwarding no >> /etc/ssh/sshd_config
RUN echo AllowUsers ocrd >> /etc/ssh/sshd_config
RUN /usr/sbin/sshd -t # check the validity of the configuration file and sanity of the keys
COPY start-sshd.sh /usr/bin
RUN dos2unix /usr/bin/start-sshd.sh
CMD ["/usr/bin/start-sshd.sh"]
EXPOSE 22