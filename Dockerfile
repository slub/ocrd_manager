# github.com/OCR-D/core
# https://hub.docker.com/r/ocrd/core/dockerfile
# ocrd/core # ubuntu:18.04
FROM ocrd/core:latest

MAINTAINER markus.weigelt@slub-dresden.de

# make apt system functional
RUN apt-get update && \
    apt-get install -y apt-utils && \
    apt-get clean
	
	
CMD "bash"