# https://github.com/beancount/fava/blob/main/contrib/docker/Dockerfile
ARG BASE_TAG
FROM docker.io/debian/snapshot:$BASE_TAG as builder

ARG URL
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-pip python3-dev git libxml2-dev libxslt-dev gcc musl-dev g++
RUN pip install --prefix="/install" $URL

FROM docker.io/debian/snapshot:$BASE_TAG

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3

COPY --from=builder /install /usr/local

ENV FAVA_HOST "0.0.0.0"
EXPOSE 5000
