# https://github.com/beancount/fava/blob/main/contrib/docker/Dockerfile
ARG BASE_TAG
FROM docker.io/library/debian:$BASE_TAG as builder

RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/10nocheckvalid

ARG URL
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-pip python3-dev git libxml2-dev libxslt-dev gcc musl-dev g++
RUN pip install --prefix="/install" $URL

FROM docker.io/library/debian:$BASE_TAG

RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/10nocheckvalid

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3  && \
    # Cleanup
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

COPY --from=builder /install /usr

ENV FAVA_HOST "0.0.0.0"
EXPOSE 5000
