ARG BASE_TAG
FROM docker.io/debian/snapshot:$BASE_TAG

ARG URL
RUN apt-get update && apt-get install -y \
      iproute2 nftables procps curl unzip dumb-init && \
    # Install clash premium
    mkdir -p /opt/bin && \
    curl -s --fail -L $URL | gzip -d > /opt/bin/clash && chmod +x /opt/bin/clash && \
    # Install clash dashboard
    mkdir -p /root/.config/clash/ && \
    curl -s --fail -L -o /tmp/clash-dashboard.zip https://github.com/Dreamacro/clash-dashboard/archive/gh-pages.zip  && \
    unzip /tmp/clash-dashboard.zip -d /root/.config/clash/ && rm /tmp/clash-dashboard.zip && \
    # Cleanup
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

ENTRYPOINT ["dumb-init"]
CMD ["/opt/bin/clash"]