# https://github.com/beancount/fava/blob/main/contrib/docker/Dockerfile
ARG BASE_TAG
FROM docker.io/library/debian:$BASE_TAG as base
RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/10nocheckvalid && \
    apt-get update

FROM base as builder
COPY . /root
RUN apt-get install -y --no-install-recommends python3-pip python3-dev
RUN pip install --prefix="/install" "$(python3 ./root/update.py url)"

FROM base
RUN apt-get install -y --no-install-recommends python3  && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

COPY --from=builder /install /usr

ENV FAVA_HOST "0.0.0.0"
EXPOSE 5000
