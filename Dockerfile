# github.com/OCR-D/core
# https://hub.docker.com/r/ocrd/core/dockerfile
# ocrd/core # ubuntu:18.04
FROM ocrd/core:latest

MAINTAINER markus.weigelt@slub-dresden.de

# make apt system functional
# get ImageMagick (OCR-D/core#796)
# install SSH server
# install Syslogd
RUN apt-get update && \
    apt-get install -y \
	apt-utils \
        imagemagick \
	rsyslog \
	openssh-server \
	openssh-client && \
    apt-get clean

# configure writing to ocrd.log for profiling
COPY ocrd_logging.conf /etc

# run OpenSSH server
RUN ssh-keygen -A
RUN mkdir /run/sshd /.ssh
RUN echo Banner none >> /etc/ssh/sshd_config
RUN echo PrintMotd no >> /etc/ssh/sshd_config
RUN echo PermitUserEnvironment yes >> /etc/ssh/sshd_config
RUN echo PermitUserRC yes >> /etc/ssh/sshd_config
RUN echo X11Forwarding no >> /etc/ssh/sshd_config
RUN echo AllowUsers ocrd >> /etc/ssh/sshd_config
RUN echo "cd /data" >> /etc/profile
RUN /usr/sbin/sshd -t # check the validity of the configuration file and sanity of the keys
COPY *.sh /usr/bin/
CMD ["/usr/bin/start-sshd.sh"]
EXPOSE 22

WORKDIR /data
VOLUME /data

# simulate a virtual env for the makefile,
# coinciding with the Python system prefix
ENV PREFIX=/usr
ENV VIRTUAL_ENV $PREFIX
ENV HOME /

