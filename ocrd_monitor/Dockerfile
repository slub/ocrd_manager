FROM python:3.10

ARG VCS_REF
ARG BUILD_DATE
LABEL \
    maintainer="https://slub-dresden.de" \
    org.label-schema.vcs-ref=$VCS_REF \
    org.label-schema.vcs-url="https://github.com/slub/ocrd_manager/tree/main/ocrd_monitor" \
    org.label-schema.build-date=$BUILD_DATE

RUN apt-get update \
    && apt-get install -o Acquire::Retries=3 -y --no-install-recommends \
    libcairo2-dev libgtk-3-bin libgtk-3-dev libglib2.0-dev \
    libgtksourceview-3.0-dev libgirepository1.0-dev gir1.2-webkit2-4.0 \
    python3-dev pkg-config cmake dnsutils \
    && pip3 install -U setuptools wheel \
    && pip3 install browse-ocrd psutil python-dotenv

# MONITOR_PORT_GTK
EXPOSE 8085
# MONITOR_PORT_LOG
EXPOSE 8080
# MONITOR_PORT_WEB
EXPOSE 5000

VOLUME /data

COPY init.sh /init.sh
COPY ocrdbrowser /usr/local/ocrd-monitor/ocrdbrowser
COPY ocrdmonitor /usr/local/ocrd-monitor/ocrdmonitor
COPY requirements.txt /usr/local/ocrd-monitor/requirements.txt

RUN pip install -r /usr/local/ocrd-monitor/requirements.txt

WORKDIR /
CMD ["/init.sh", "/data"]
