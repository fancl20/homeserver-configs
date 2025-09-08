ARG FETCHER=scratch
ARG BASE_TAG=latest

FROM $FETCHER
COPY . /root
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl bzip2 && \
    mkdir /tmp/roon && curl -s --fail -L $(python3 ./root/update.py url) | tar -C /tmp/roon -xjf -

FROM docker.io/library/debian:$BASE_TAG
RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/10nocheckvalid && \
    apt-get update

ENV ROON_DATAROOT /data
ENV ROON_ID_DIR /data

RUN apt-get install -y --no-install-recommends \
      ffmpeg libasound2-dev alsa-utils cifs-utils \
      ca-certificates iproute2 \
    # Cleanup
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=0 /tmp/roon /opt/roon

CMD ["/opt/roon/RoonServer/start.sh"]
