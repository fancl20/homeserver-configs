ARG BASE_TAG
FROM docker.io/debian/snapshot:$BASE_TAG as builder

ENV ROON_DATAROOT /data
ENV ROON_ID_DIR /data

ARG URL
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl bzip2 ffmpeg cifs-utils alsa-utils libicu72 iproute2 \
    && mkdir /app && cd /app \
    && curl -L $URL | tar -xjf - \
    # Cleanup
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENTRYPOINT /app/RoonServer/start.sh