ARG BASE_TAG
FROM docker.io/debian/snapshot:$BASE_TAG

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash curl jq && \
    # Cleanup
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

CMD ["bash"]