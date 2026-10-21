ARG BASE_TAG=latest

FROM docker.io/library/debian:$BASE_TAG
RUN sed -i -e 's/^URIs:/# URIs:/' -e 's/^# http:/URIs: http:/' /etc/apt/sources.list.d/debian.sources && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/10nocheckvalid && \
    apt-get update

# Base image for Coder workspaces using the Dev Containers integration:
# docker.io runs the daemon (DinD), nodejs/npm host @devcontainers/cli, and
# the coder CLI is the workspace agent (it self-updates to the server version).
RUN apt-get install -y --no-install-recommends \
      docker-cli docker.io nodejs npm git curl ca-certificates openssh-client \
      fish sudo less procps iproute2 && \
    curl -fsSL https://coder.com/install.sh | sh && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# docker.io's init script also mounts cgroup v1 controllers, which fails
# noisily against the pod's read-only cgroup v2 mount. Skip the v1 bootstrap
# when the unified hierarchy is present.
RUN sed -i 's|^cgroupfs_mount() {$|&\n\t[ -e /sys/fs/cgroup/cgroup.controllers ] \&\& return|' /etc/init.d/docker

# The workspace container root is overlayfs, which the overlay2 storage driver
# cannot layer on; /workspaces is the PVC mount, so data-root there both works
# and persists build cache across workspace restarts.
RUN mkdir -p /etc/docker && \
    echo '{"data-root": "/workspaces/.docker"}' > /etc/docker/daemon.json
