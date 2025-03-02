FROM docker.io/library/debian:$BASE_TAG as builder

RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/10nocheckvalid && \
    apt-get update

ADD scripts /tmp/scripts

ENV PIPX_HOME=/opt/pipx
ENV PIPX_BIN_DIR=/usr/local/bin

RUN apt-get install -y \
        dumb-init openssh-server \
        curl wget vim git jq fish \
        python3-dev python3-venv pipx \
        build-essential make pkg-config clang cmake golang && \
    mkdir /var/run/sshd

# Invalidate cache
ENV _VERSION=$VERSION

# Install commonly used cross projects' dependencies
RUN curl -fsSL https://deb.nodesource.com/setup_current.x | bash - && \
    apt-get install -y nodejs && \
    # Install jsonnet
    GOBIN=/opt/jsonnet go install github.com/google/go-jsonnet/cmd/jsonnet@latest && \
    ln -s /opt/jsonnet/jsonnet /usr/local/bin/ && \
    # Install terraform
    python3 /tmp/scripts/install_terraform.py && \
    # Install beancount
    apt-get install -y \
    bison flex && \
    pipx install git+https://github.com/beancount/beancount#egg=beancount && \
    # Install zig
    mkdir -p /opt/zig && \
    curl -s https://ziglang.org/download/index.json \
    | jq --raw-output '.master."x86_64-linux".tarball' \
    | xargs curl | tar --strip-components=1 -xJC /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/ && \
    # Cleanup
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

# To get latest stable release of zig:
#   jq --raw-output 'del(.master) | to_entries | sort_by(.value.date) | .[-1].value."x86_64-linux".tarball'

ENTRYPOINT ["dumb-init"]