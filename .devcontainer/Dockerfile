FROM debian:testing-slim

RUN groupadd --gid 1000 coder && \
    useradd --uid 1000 --gid 1000 -m coder

RUN apt-get update && apt-get install -y
    curl git vim jq fish \
    nodejs npm

RUN apt-get install -y \
    python3 golang \
    && rm -rf /var/lib/apt/lists/*

COPY install_terraform.py /tmp/install_terraform.py
RUN python3 /tmp/install_terraform.py && \
    GOBIN=/usr/local/bin go install github.com/google/go-jsonnet/cmd/jsonnet@latest

# Clean up
RUN rm -rf /tmp/* /var/tmp/*

SHELL ["/usr/bin/fish"]
USER coder