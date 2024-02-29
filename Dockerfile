# github.com/OCR-D/core
# https://hub.docker.com/r/ocrd/core/dockerfile
# ocrd/core # ubuntu:18.04
ARG VERSION=latest
FROM ocrd/core:$VERSION

ARG VCS_REF
ARG BUILD_DATE
LABEL \
    maintainer="https://slub-dresden.de" \
    org.label-schema.vendor="Saxon State and University Library Dresden" \
    org.label-schema.name="OCR-D Manager" \
    org.label-schema.vcs-ref=$VCS_REF \
    org.label-schema.vcs-url="https://github.com/slub/ocrd_manager" \
    org.label-schema.build-date=$BUILD_DATE \
    org.opencontainers.image.vendor="Saxon State and University Library Dresden" \
    org.opencontainers.image.title="OCR-D Manager" \
    org.opencontainers.image.description="Frontend for OCR-D Controller" \
    org.opencontainers.image.source="https://github.com/slub/ocrd_manager" \
    org.opencontainers.image.documentation="https://github.com/slub/ocrd_manager/blob/${VCS_REF}/README.md" \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.created=$BUILD_DATE

ARG KITODO_MQ_CLIENT_VERSION=0.3

# Changelog https://www.mongodb.com/docs/mongodb-shell/changelog/
# Supported MongoDB Version https://www.mongodb.com/docs/mongodb-shell/connect/#supported-mongodb-versions
ARG MONGODB_SHELL_VERSION=1.10.1

ENV HOME=/

# make apt system functional
# get ImageMagick (OCR-D/core#796)
# install SSH server
# install Syslogd
RUN apt-get update && \
    apt-get install -y \
    apt-utils \
    dnsutils \
    imagemagick \
    rsyslog \
    rsync \
    openjdk-11-jre-headless \
    openssh-server \
    openssh-client \
    xmlstarlet && \
    apt-get clean
# configure writing to ocrd.log for profiling
COPY ocrd_logging.conf /etc

# add activemq log4j properties
COPY kitodo-activemq-client-log4j2.properties /opt/kitodo-activemq-client/log4j2.properties
ENV ACTIVEMQ_CLIENT_LOG4J2 /opt/kitodo-activemq-client/log4j2.properties

# add ActiveMQ client library
ADD https://github.com/slub/kitodo-production-activemq/releases/download/${KITODO_MQ_CLIENT_VERSION}/kitodo-activemq-client-${KITODO_MQ_CLIENT_VERSION}.jar /opt/kitodo-activemq-client
ENV ACTIVEMQ_CLIENT /opt/kitodo-activemq-client/kitodo-activemq-client-${KITODO_MQ_CLIENT_VERSION}.jar
RUN chmod go+r $ACTIVEMQ_CLIENT

# configure ActiveMQ client queue
ENV ACTIVEMQ_CLIENT_QUEUE FinalizeTaskQueue

# install mets-mods2tei (for METS updates outside of OCR-D workspace)
RUN pip install mets-mods2tei
# install page-to-alto (for ALTO conversion outside of OCR-D workflow)
RUN pip install ocrd-page-to-alto
# install mongosh (for job information)
RUN wget https://downloads.mongodb.com/compass/mongodb-mongosh_${MONGODB_SHELL_VERSION}_amd64.deb
RUN dpkg -i mongodb-mongosh_${MONGODB_SHELL_VERSION}_amd64.deb
# install socat and sampo (for minimal REST API to CLI entrypoints)
RUN apt-get install socat
RUN wget -O /usr/bin/sampo.sh https://github.com/bertsky/sampo/raw/external-script-cgiopts/docker/sampo/sampo.sh
#COPY sampo.sh /usr/bin/
COPY sampo.conf /usr/bin/
RUN chmod +x /usr/bin/sampo.sh

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
RUN cd /usr/bin; \
    ln -fs process_mets.sh for_presentation.sh; \
    ln -fs process_images.sh for_production.sh
CMD ["/usr/bin/startup.sh"]
EXPOSE 22

WORKDIR /data
VOLUME /data
VOLUME /workflows

# simulate a virtual env for the makefile,
# coinciding with the Python system prefix
ENV PREFIX=/usr
ENV VIRTUAL_ENV $PREFIX
ENV HOME /

# install workflow-configuration (for ocrd-make and METS/PAGE XSLT)
RUN git -C /tmp clone https://github.com/bertsky/workflow-configuration.git && \
    make -C /tmp/workflow-configuration deps-ubuntu install && \
    rm -fr /tmp/workflow-configuration
