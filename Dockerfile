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
	openssh-client && \
    apt-get clean

RUN mkdir /root/.ssh
COPY initialsetup.sh /usr/bin

RUN dos2unix /usr/bin/initialsetup.sh

ENTRYPOINT ["/usr/bin/initialsetup.sh"]

CMD ["bash"]
