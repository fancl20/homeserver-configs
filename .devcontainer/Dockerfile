FROM debian:testing-slim

RUN groupadd --gid 1000 coder && \
    useradd --uid 1000 --gid 1000 -m coder

RUN apt-get update && apt-get install -y \
    curl git vim jq fish kubectl \
    nodejs npm sudo

RUN echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder && \
    chmod 440 /etc/sudoers.d/coder

RUN apt-get install -y \
    build-essential pkg-config \
    python3 golang

COPY install_terraform.py /tmp/install_terraform.py
RUN python3 /tmp/install_terraform.py && \
    GOBIN=/usr/local/bin go install github.com/google/go-jsonnet/cmd/jsonnet@latest

# Cluster credentials are the pod's mounted service account token, read via
# tokenFile on every invocation so kubelet's rotation of it stays transparent.
COPY --chown=coder:coder kubeconfig /home/coder/.kube/config

# Clean up
RUN rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

SHELL ["/usr/bin/fish"]
USER coder