ARG BASE_TAG
FROM docker.io/library/debian:$BASE_TAG

RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/10nocheckvalid

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash curl jq ca-certificates && \
    # Cleanup
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

CMD ["bash"]