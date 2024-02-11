ARG BASE_TAG
FROM docker.io/library/debian:$BASE_TAG

RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;\nAcquire::ForceIPv4=true;" > /etc/apt/apt.conf.d/10nocheckvalid

ARG URL
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates iproute2 procps curl unzip dumb-init && \
    # Install dea
    mkdir -p /opt/dae && \
    curl -s --fail -L -o /tmp/dae.zip $URL  && \
    unzip /tmp/dae.zip -d /opt/dae/ && mv /opt/dae/daed-* /opt/dae/daed && chmod +x /opt/dae/daed && \
    # Update geodata
    mkdir -p /usr/local/share/daed && \
    curl -L -o /usr/local/share/daed/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat && \
    curl -L -o /usr/local/share/daed/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat && \
    # Cleanup
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

ENTRYPOINT ["dumb-init"]
CMD ["/opt/dae/daed"]