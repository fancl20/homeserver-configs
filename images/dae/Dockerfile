ARG FETCHER=scratch
ARG BASE_TAG=latest

FROM $FETCHER
COPY . /root
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip && \
    # Install dea
    curl -s --fail -L -o /tmp/dae.zip $(python3 ./root/update.py url) && \
    unzip /tmp/dae.zip -d /tmp/dae/ && \
    # Update geodata
    mkdir -p /tmp/geodata && \
    curl -L -o /tmp/geodata/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat && \
    curl -L -o /tmp/geodata/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat

FROM docker.io/library/debian:$BASE_TAG
RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/10nocheckvalid && \
    apt-get update

RUN apt-get install -y --no-install-recommends iproute2 procps dumb-init && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

COPY --from=0 /tmp/dae/ /opt/dae
COPY --from=0 /tmp/geodata/ /usr/local/share/dae

ENTRYPOINT ["dumb-init"]
CMD ["/opt/dae/dae-linux-x86_64_v3_avx2"]
