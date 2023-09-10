ARG BASE_IMAGE
FROM $BASE_IMAGE

RUN apt-get update && apt-get upgrade -y && apt-get install -y \
      iproute2 nftables procps curl jq unzip dumb-init && \
    # Install clash premium
    mkdir -p /opt/bin && \
    curl -s --fail -L $(curl -s --fail -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/Dreamacro/clash/releases/tags/premium \
      | jq -r '.assets[] | select(.name | startswith("clash-linux-amd64-20")) | .browser_download_url') \
    | gzip -d > /opt/bin/clash && chmod +x /opt/bin/clash && \
    # Install clash dashboard
    mkdir -p /root/.config/clash/ && \
    curl -s --fail -L -o /tmp/clash-dashboard.zip https://github.com/Dreamacro/clash-dashboard/archive/gh-pages.zip  && \
    unzip /tmp/clash-dashboard.zip -d /root/.config/clash/ && rm /tmp/clash-dashboard.zip && \
    # Cleanup
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

ENTRYPOINT ["dumb-init"]
CMD ["/opt/bin/clash"]