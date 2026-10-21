FROM debian:testing-slim

RUN groupadd --gid 1000 coder && \
    useradd --uid 1000 --gid 1000 -m coder

RUN apt-get update && apt-get install -y \
    build-essential curl fish git jq pkg-config python3 vim

RUN tag=$(curl -fsSL https://api.github.com/repos/google/go-jsonnet/releases/latest | jq -r .tag_name) && \
    curl -fsSL -o /tmp/jsonnet.deb "https://github.com/google/go-jsonnet/releases/download/${tag}/jsonnet-go_${tag#v}_linux_amd64.deb" && \
    apt-get install -y /tmp/jsonnet.deb

# Cluster credentials are the pod's mounted service account token, read via
# tokenFile on every invocation so kubelet's rotation of it stays transparent.
COPY --chown=coder:coder kubeconfig /home/coder/.kube/config

# Clean up
RUN rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

USER coder
