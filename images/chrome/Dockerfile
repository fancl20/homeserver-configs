ARG FETCHER=scratch
ARG BASE_TAG=latest

FROM $FETCHER
COPY . /root
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip golang && \
    curl -s --fail -L -o /tmp/chrome.zip $(python3 ./root/update.py url) && \
    unzip /tmp/chrome.zip -d /tmp/ && \
    cd /root/mcp-proxy && CGO_ENABLED=0 go build -o /tmp/mcp-proxy .

FROM docker.io/library/debian:$BASE_TAG
RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/10nocheckvalid && \
    apt-get update

RUN apt-get install -y --no-install-recommends nodejs npm

COPY --from=0 /tmp/chrome-linux64 /opt/chrome
RUN while read pkg; do \
      apt-get satisfy -y --no-install-recommends "${pkg}"; \
    done < /opt/chrome/deb.deps && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

COPY --from=0 /tmp/mcp-proxy /opt/mcp-proxy/mcp-proxy
