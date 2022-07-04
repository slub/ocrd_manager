FROM python:3.7

RUN apt-get update \
    && apt-get install -o Acquire::Retries=3 -y --no-install-recommends \
    libcairo2-dev libgtk-3-bin libgtk-3-dev libglib2.0-dev \
    libgtksourceview-3.0-dev libgirepository1.0-dev gir1.2-webkit2-4.0 \
    python3-dev pkg-config cmake dnsutils \
    && pip3 install -U setuptools wheel \
    && pip3 install browse-ocrd psutil python-dotenv

ENV GDK_BACKEND broadway
ENV BROADWAY_DISPLAY :5

EXPOSE 8085
EXPOSE 8080

VOLUME /data

COPY init.sh /init.sh
COPY serve.py /serve.py

WORKDIR /
CMD ["/init.sh", "/data"]
